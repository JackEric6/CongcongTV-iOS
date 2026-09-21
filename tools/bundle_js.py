#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bundle_js.py — 将 drpy2 引擎与其依赖库打包成可由 iOS JavaScriptCore 直接求值的**单文件同步脚本**。

## 为什么这样做
drpy2.min.js 用 ES module 语法（`import cheerio from "assets://js/lib/cheerio.min.js"` 等）。
iOS 的 JavaScriptCore `evaluateScript()` 无法直接求值含 import/export 的脚本，所以：
  * 把每个 `import X from "sp"` 替换为 `var X = require$("name")`。
  * 引擎自身的 `export default{...}` 替换为 `module.exports = {...}`。
  * 每个依赖模块包进一个 IIFE，内部提供局部 `module/exports`（CommonJS 分支），
    求值后把 `module.exports` 收进 `__modules` 注册表。
  * 颗粒级写死哪些依赖还要挂全局（CryptoJS/pako/jinja/NODERSA/gbkTool/Cheerio），
    因为引擎/模板代码里会直接引用这些裸标识符。
  * **模块必须先于引擎求值**：引擎顶层 `const _jinja2=cheerio.jinja2` 在求值时就要读到
    cheerio/jinja 全局。
  * DRIVER 最后求值：注入 console / req / local 桥，并把引擎入口挂到 globalThis.CongcongTV。

## iOS 侧一致约定（见 JSEnv.swift）
  * 只使用 host 注入的原生能力：globalThis.__drpyFetch / __drpyLocal / __drpyLog。
  * JS 内所有网络请求都同步回调 `__drpyFetch(url, obj)` -> {content, headers}（Swift 用
    JSValue 同步桥实现，走 URLSession + 信号量）。
  * 不使用 require('node:...') / process / Buffer。

用法:
    python bundle_js.py <js_dir> <out.js>
"""
import os
import re
import sys

# 需要打包的模块（除 engine 外）。顺序决定 IIFE 求值顺序，无相互依赖关系。
MODULES = [
    "cheerio.min.js",
    "crypto-js.js",
    "gbk.js",
    "json5.js",
    "jinja.js",
    "node-rsa.js",
    "pako.min.js",
    "模板.js",
]

# 注册名重映射：模块实际存进 __modules 的键。必须与 HEADER 里 require$() 的改名一致。
SHORT = {
    "cheerio.min.js": "cheerio",
    "crypto-js.js": "crypto",
    "node-rsa.js": "node-rsa",
    "pako.min.js": "pako",
    "模板.js": "template",
    "gbk.js": "gbk",
    "json5.js": "json5",
    "jinja.js": "jinja",
}

# 每个模块求值后如何接入注册表
#   kind:
#     default            —— 模块把 module.exports 设为导出对象（engine/cheerio/template）
#     gbkTool            —— 模块声明 `function gbkTool(){...}`，直接注册 gbkTool
#     global_crypto      —— UMD CommonJS 分支，注册 module.exports 为 CryptoJS，并挂 globalThis.CryptoJS
#     global_pako        —— 同上，注册 + 挂 globalThis.pako
#     global_jinja       —— 同上，注册 + 挂 globalThis.jinja
#     global_nodersa     —— 同上，注册 + 挂 globalThis.NODERS
#     plain_commonjs     —— 纯 CommonJS（json5），module.exports 直接注册
HANDLER = {
    "cheerio.min.js": "default",
    "crypto-js.js": "global_crypto",
    "gbk.js": "gbkTool",
    "json5.js": "plain_commonjs",
    "jinja.js": "global_jinja",
    "node-rsa.js": "global_nodersa",
    "pako.min.js": "global_pako",
    "模板.js": "default",
}

# engine 里 import 语句 -> (模块 key, 绑定标识符)；None 的绑定 = 纯副作用导入
ENGINE_IMPORTS = [
    ("cheerio.min.js", "cheerio"),
    ("crypto-js.js", None),
    ("node-rsa.js", None),
    ("pako.min.js", None),
    ("模板.js", "模板"),
    ("gbk.js", "gbkTool"),
    ("json5.js", None),
    ("jinja.js", None),
]


def read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def qstr(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def strip_esm_default(src, default_name=None):
    """把 `export default (...)` 换成 `module.exports = (...)`；或 `export {A as default,...}` 换成 `module.exports = A;`"""
    if default_name:
        # export{mh as contains,Eh as default,...};  →  module.exports = Eh;
        pat = re.compile(r"\bexport\s*\{.*?," + default_name + r"\s+as\s+default[^}]*\}\s*;")
        m = pat.search(src)
        if m:
            return src.replace(m.group(0), "module.exports = " + default_name + ";")
        # 可能 default 在最后: {A as x, B as default}
        pat2 = re.compile(r"\bexport\s*\{[^}]*\b(" + default_name + r")\s+as\s+default\s*,?[^}]*\}\s*;")
        m2 = pat2.search(src)
        if m2:
            return src.replace(m2.group(0), "module.exports = " + default_name + ";")
        return src
    # export default <expr>;  →  module.exports = <expr>;
    return re.sub(r"\bexport\s+default\b", "module.exports = ", src, count=1)


def wrap(src, label):
    return (
        "(function(){\n"
        "var module={exports:{}};\n"
        "var exports=module.exports;\n"
        "/*%s*/\n" % label + src + "\n"
        "return module.exports;\n"
        "})()"
    )


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    jsdir, out = sys.argv[1], sys.argv[2]

    engine = read(os.path.join(jsdir, "drpy2.min.js"))

    # 1) 引擎 import → require$ 调用；副作用导入整条删除
    #    drpy2 源码里 specifier 形态不统一（见 drpy2.min.js 前 200B）：
    #      import cheerio from"assets://js/lib/cheerio.min.js"
    #      import"./node-rsa.js" / import"./pako.min.js" / import"./json5.js" / import"./jinja.js"
    #      import 模板 from"./模板.js"
    #      import{gbkTool}from"./gbk.js"
    #    所以模式要 (a) 容忍可选前缀 assets://js/lib/ 与 ./，(b) 用捕获组 1 配同一引号。
    Q = "(['\"])"
    PFX = r'(?:assets://js/lib/|\./)?'
    for key, binding in ENGINE_IMPORTS:
        # 副作用导入：整条删除
        if binding is None:
            pat = r'\bimport\s*' + Q + PFX + re.escape(key) + r'\1\s*;?'
            engine = re.sub(pat, "", engine, count=1)
        else:
            pat = r'\bimport\s*\{?\s*' + re.escape(binding) + r'\s*\}?\s*from\s*' + Q + PFX + re.escape(key) + r'\1\s*;?'
            engine = re.sub(pat, "var " + binding + " = require$(" + qstr(key) + ");", engine, count=1)
    # 2) 引擎尾部 ESM 默认导出 → module.exports；收集引擎默认导出对象
    engine = strip_esm_default(engine)
    # 2b) 引擎 role=search/category 的 js: 载荷通过 eval() 在同一函数作用域执行，
    #     而 searchParse/categoryParse 的块级 `let d=[]` 会与载荷里的 `let d` 冲突。
    #     把 `let d=[]` 换成 `var d=[]`，让载荷 var/let 均不与之冲突。
    engine = re.sub(r'\blet d=\[\]', 'var d=[]', engine)

    # 3) 组装：header + 依赖模块(IIFE) + 引擎(IIFE) + driver，全部同步
    parts = ["/* ================= JSEnv bundle (generated by bundle_js.py) ================= */"]
    parts.append(HEADER)
    parts.append(RUNTIME_EXTRA)

    for key in MODULES:
        src = read(os.path.join(jsdir, key))
        handler = HANDLER[key]
        reg = SHORT.get(key, key)
        parts.append("/* ------ module: %s ------ */" % key)
        if handler == "default":
            # cheerio 的 导出是 `export{A as x,Eh as default,...};`（named-as-default），
            # 不是 `export default <expr>;`，必须显式传 default_name="Eh"。
            default_name = "Eh" if key == "cheerio.min.js" else None
            src = strip_esm_default(src, default_name)
            parts.append("__modules[" + qstr(reg) + "] = " + wrap(src, " " + key + " ") + ";")
        elif handler == "plain_commonjs":
            parts.append("__modules[" + qstr(reg) + "] = " + wrap(src, " " + key + " ") + ";")
        elif handler == "gbkTool":
            src = re.sub(r"\bexport\s+function\s+(gbkTool)\b", r"function \1", src, count=1)
            parts.append(
                "(function(){\n" + src + "\n"
                "globalThis.gbkTool = typeof gbkTool!=='undefined'?gbkTool:null;\n"
                "__modules[" + qstr(reg) + "] = globalThis.gbkTool;\n"
                "})();"
            )
        else:
            globalname = {
                "global_crypto": "CryptoJS",
                "global_pako": "pako",
                "global_jinja": "jinja",
                "global_nodersa": "NODERSA",
            }[handler]
            parts.append(
                "(function(){\n"
                "var module={exports:{}};\n"
                "var exports=module.exports;\n" + src + "\n"
                "var v=module.exports||globalThis[" + qstr(globalname) + "];\n"
                "__modules[" + qstr(reg) + "] = v;\n"
                "globalThis[" + qstr(globalname) + "] = v;\n"
                "})();"
            )

    # 引擎注册到 __drpy 全局，供 iOS 侧 JSEnv 调用
    # host 注入解析器必须在引擎求值之前就位（引擎顶层 `defaultParser={pdfh:pdfh,...}`
    # 在 IIFE 求值时经作用域链向上解析到这些全局函数）。
    parts.append(CC_PARSERS)
    parts.append("/* ---- engine drpy2 ---- */")
    parts.append("var __engine = " + wrap(engine, " engine ") + ";\n"
                 "/* 兼容旧 era：若引擎导出把 search/setResult 等顶到全局，同步到全局（同一 realm）。 */\n"
                 "if(typeof __engine==='object'&&__engine){ globalThis.__drpy=__engine; }")
    parts.append("globalThis.__drpy = (typeof __engine==='object'&&__engine)?__engine:null;")

    # 4) 驱动引擎（console/req/local 桥 + 导出入口）——顺序在引擎求值之后
    parts.append("/* ---- engine driver ---- */")
    parts.append(DRIVER)

    bundled = "\n".join(parts)
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(bundled)
    print("wrote %s (%d bytes)" % (out, len(bundled.encode("utf-8"))))


HEADER = r"""
/* ===== runtime header ===== */
var __modules = {};          /* name -> exports (module.exports or global bound) */
function require$(name){
  if(name==="cheerio.min.js"){ name="cheerio"; }
  if(name==="crypto-js.js"){ name="crypto"; }
  if(name==="node-rsa.js"){ name="node-rsa"; }
  if(name==="pako.min.js"){ name="pako"; }
  if(name==="模板.js"){ name="template"; }
  if(name==="gbk.js"){ name="gbk"; }
  if(name==="json5.js"){ name="json5"; }
  if(name==="jinja.js"){ name="jinja"; }
  var v = __modules[name];
  if(v === undefined || v === null){ throw new Error('module not loaded: '+name); }
  return v;
}
if(typeof global==='undefined'){ var global = globalThis; }
""" + "\n"

# drpy2 引擎顶层引用了三个 **host 注入** 的 CSS 选择器解析器（pdfh/pdfa/pd）——
# 引擎自身从不声明它们（完整源码里 `// 内置 pdfh,pdfa,pd` 即指此意，宿主 app 注入）。
# 本 bundle 即宿主，真实实现放在 module("cheerio")（可调用 $）之上：
#   pdfh(html, parse) —— 单值：选择器链 (A&&B&&...&&action)，action ∈ {Text, html, 属性名}
#   pdfa(html, parse) —— 分组：A&& 前缀代表文档根(可省)，返回尾段匹配的元素数组（cheerio 对象）
#   pd (html, parse, base) —— 取链接：末动作省略时优先 src 再 href；相对链接拼 base
# 三个规则主链路只用 json:/js: 解析（jsp/json 分支自包含，不碰这三个函数），
# 只有 jq 分支会调到它们 —— 实战中即「兔小贝」的搜索规则 `.list-con&&.items;.text&&Text;...`。
CC_PARSERS = r"""
/* ===== host-injected parser: pdfh / pdfa / pd (CSS 选择器，基于 cheerio) ===== */
(function(){
  var _cheerioMod = null;
  function cheerioMod(){
    if(!_cheerioMod){
      try{ _cheerioMod = require$('cheerio'); }catch(e){ _cheerioMod = null; }
    }
    return _cheerioMod;
  }
  /* 归一成 cheerio 文档：字符串 load()；对象直接复用。失败返回 null */
  function _doc(html){
    try{
      if(typeof html === 'string'){ var c = cheerioMod(); return c ? c.load(html) : null; }
      if(html && (typeof html === 'function' || typeof html.find === 'function')){ return html; }
      if(html && typeof html.ele === 'string'){ var c2 = cheerioMod(); return c2 ? c2.load(html.ele) : null; }
    }catch(e){}
    return null;
  }
  function _findAll($, sel){
    try{
      if(typeof $ === 'function'){ return $(sel); }
      if($ && typeof $.find === 'function'){ return $.find(sel); }
    }catch(e){}
    return null;
  }
  function _first($, sel){
    try{
      var c = (sel && sel !== '*') ? _findAll($, sel) : $;
      if(c && typeof c.first === 'function'){ return c.first(); }
      if(c && typeof c.eq === 'function'){ return c.eq(0); }
      return c || null;
    }catch(e){ return null; }
  }
  /* 拆出第一条解析表达式的选择器链 */
  function _chain(parse){
    var first = String(parse == null ? '' : parse).split(';')[0];
    return first.split('&&').map(function(x){ return (x||'').trim(); }).filter(Boolean);
  }
  /* 顺着链条定位到最后一个元素；最后一个 token 作为动作被剥离 */
  function _walkToLast($, chain){
    var cur = $;
    for(var i = 0; i < chain.length - 1; i++){
      cur = _first(cur, chain[i]);
      if(!cur){ return null; }
    }
    return cur;
  }
  function _actionValue(el, action){
    if(!el){ return ''; }
    if(/^Text$/i.test(action)){ return el.text ? (el.text()||'').trim() : ''; }
    if(/^html$/i.test(action)){ return el.html ? (el.html()||'') : ''; }
    if(el.attr){ return el.attr(action) || ''; }
    return '';
  }
  /* 返回包装元素列表（带 attr/text 方法），不是裸 DOM 节点 */
  function _els($, sel){
    var list = _findAll($, sel);
    if(!list){ return []; }
    if(Array.isArray(list)){ return list; }
    var n = (typeof list.length === 'number') ? list.length : 0;
    var out = [];
    for(var i = 0; i < n; i++){
      try{ out.push(list.eq(i)); }catch(e){}
    }
    if(out.length){ return out; }
    if(typeof list.toArray === 'function' && list.toArray().length){ return [list]; }
    return [];
  }

  function pdfh(html, parse){
    try{
      if(!parse || !String(parse).trim()){ return ''; }
      var $ = _doc(html);
      if(!$){ return ''; }
      var chain = _chain(parse);
      if(!chain.length){ return ''; }
      if(chain.length === 1){
        /* 单段选择器：默认取文本，无文本回退 src/href */
        var el0 = _first($, chain[0]);
        if(!el0){ return ''; }
        if(el0.text){ var t = (el0.text()||'').trim(); if(t){ return t; } }
        return el0.attr ? (el0.attr('src') || el0.attr('href') || '') : '';
      }
      var last = chain[chain.length - 1];
      var cur = _walkToLast($, chain);
      if(!cur){ return ''; }
      return _actionValue(cur, last);
    }catch(e){ return ''; }
  }

  function pdfa(html, parse){
    try{
      if(!parse || !String(parse).trim()){ return []; }
      var $ = _doc(html);
      if(!$){ return []; }
      var chain = _chain(parse);
      if(!chain.length){ return []; }
      /* A&& 前缀 = 文档根（这里根就是 $），剥掉；剩下的逐级下钻到最后一段取元素集 */
      if(chain[0] === 'A'){ chain = chain.slice(1); }
      if(!chain.length){ return []; }
      var cur = $;
      for(var i = 0; i < chain.length - 1; i++){
        cur = _first(cur, chain[i]);
        if(!cur){ return []; }
      }
      return _els(cur, chain[chain.length - 1]);
    }catch(e){ return []; }
  }

  function pd(html, parse, base){
    try{
      if(!parse || !String(parse).trim()){ return ''; }
      var $ = _doc(html);
      if(!$){ return ''; }
      var chain = _chain(parse);
      if(!chain.length){ return ''; }
      var raw = '';
      if(chain.length === 1){
        var el0 = _first($, chain[0]);
        if(el0){ raw = el0.attr ? (el0.attr('src') || el0.attr('href') || '') : ''; }
      }else{
        var last = chain[chain.length - 1];
        var cur = _walkToLast($, chain);
        if(cur){ raw = _actionValue(cur, last); }
      }
      raw = String(raw || '');
      if(/^[a-zA-Z][a-zA-Z0-9+.\-]*:/.test(raw)){ /* 绝对 URL/协议 */ return raw; }
      if(raw && base && typeof base === 'string' && base.length){
        return base.replace(/\/+$/, '') + '/' + raw.replace(/^\/+/, '');
      }
      return raw;
    }catch(e){ return ''; }
  }

  globalThis.pdfh = pdfh;
  globalThis.pdfa = pdfa;
  globalThis.pd  = pd;
})();
""" + "\n"

RUNTIME_EXTRA = r"""
/* host 注入：joinUrl —— drpy2 压缩引擎的 urljoin() 引用它，却不定义（dr_py/hipy
   的 urljoin2 在 python 侧，与 JS 引擎无关）。规则解析(/play/x 相对地址)、m3u8
   解析、rule.homeUrl 拼接等都会走到这里，必须在引擎 IIFE 之前定义。 */
function joinUrl(fromPath, nowPath){
  fromPath = fromPath || "";
  nowPath  = nowPath  || "";
  if(/^https?:\/\//i.test(nowPath)){ return nowPath; }        /* 绝对地址原样返回 */
  try{
    var base = fromPath;
    if(/^\/\//.test(nowPath)){                                 /* //host/path -> 补协议 */
      base = (/^https?:/i.test(fromPath)? fromPath.split(/\/\//)[0] : "https:") + nowPath;
      return base;
    }
    /* new URL 原生处理：/根相对、./x、../x、裸相对（相对 fromPath 所在目录） */
    return new URL(nowPath, base).toString();
  }catch(e){
    /* 兜底：直接拼接 */
    if(/^\.\/|^\.\.\//.test(nowPath)){ return fromPath + nowPath.slice(1); }
    return fromPath.replace(/\/+$/,"") + "/" + nowPath.replace(/^\/+/,"");
  }
}
/* console polyfill —— 收集到内存环形池，由 __drpyLog(lines) 桥回 Swift 或吞掉 */
(function(){
  if(typeof console !== 'undefined' && console.log) { return; } /* 已存在则不动 */
  var _logbuf = [];
  var _flush = function(){
    if(_logbuf.length===0){ return; }
    try{
      if(typeof globalThis.__drpyLog === 'function'){
        globalThis.__drpyLog(_logbuf.slice(0, 200));
      }
    }catch(e){}
    _logbuf = [];
  };
  function fmt(args){
    try{
      return args.map(function(a){
        if(typeof a === 'string'){ return a; }
        if(a === undefined){ return 'undefined'; }
        if(a === null){ return 'null'; }
        try{ return JSON.stringify(a); }catch(e){ return String(a); }
      }).join(' ');
    }catch(e){ return ''; }
  }
  var mk = function(level){
    return function(){
      var line = fmt(Array.prototype.slice.call(arguments));
      _logbuf.push((level?level+': ':'')+line);
      if(_logbuf.length >= 200){ _flush(); }
    };
  };
  globalThis.console = {
    log: mk(''), error: mk('ERROR'), warn: mk('WARN'), info: mk('INFO'), debug: mk('DEBUG')
  };
  globalThis.__drpyFlushLog = _flush;
})();
/* 兜底：旧 environment 可能没有 TextDecoder（pako/node-rsa 等会用），
   有原生就留着；没有则装一个只读 UTF-8 的最小实现。 */
if(typeof TextDecoder !== 'function'){
  globalThis.TextDecoder = function(label){ this._l = label||'utf-8'; };
  globalThis.TextDecoder.prototype.decode = function(buf){
    try{
      /* buf: Uint8Array | ArrayBuffer 均可 */
      if(buf && typeof buf.byteLength === 'number' && !(buf instanceof Uint8Array)){
        buf = new Uint8Array(buf);
      }
      if(!buf){ return ''; }
      var out=''; var i=0;
      var u8 = (buf instanceof Uint8Array)?buf:new Uint8Array(buf);
      while(i < u8.length){
        var b = u8[i];
        if(b < 0x80){ out += String.fromCharCode(b); i++; }
        else if((b & 0xE0) === 0xC0 && i+1 < u8.length){
          out += String.fromCharCode(((b&0x1F)<<6)|(u8[i+1]&0x3F)); i+=2;
        }
        else if((b & 0xF0) === 0xE0 && i+2 < u8.length){
          out += String.fromCharCode(((b&0x0F)<<12)|((u8[i+1]&0x3F)<<6)|(u8[i+2]&0x3F)); i+=3;
        }
        else if((b & 0xF8) === 0xF0 && i+3 < u8.length){
          var cp = ((b&0x07)<<18)|((u8[i+1]&0x3F)<<12)|((u8[i+2]&0x3F)<<6)|(u8[i+3]&0x3F);
          cp -= 0x10000;
          out += String.fromCharCode(0xD800+(cp>>10), 0xDC00+(cp&0x3FF)); i+=4;
        }
        else { out += String.fromCharCode(b); i++; }
      }
      return out;
    }catch(e){ return ''; }
  };
}
""" + "\n"

DRIVER = r"""/* ===== engine driver =====
   注入 drpy2 唯一的三个外部依赖，并把入口挂到 globalThis.CongcongTV。

   1) req(url,obj)  —— 引擎里 request() 的唯一网络调用点：
        let res=req(url,obj); let html=res.content||"";
        if(obj.withHeaders){ ...res.headers... }
      约定：返回 { content: string, headers: object }。
      这里一律交给 globalThis.__drpyFetch(url, obj)（Swift 同步桥/Node stub 都实现它）。
   2) local         —— setItem/getItem/clearItem 用：
        local.set(RKEY,k,v) / local.get(RKEY,k)||v / local.delete(RKEY,k)
      内存 Map 兜底 + 双写 globalThis.__drpyLocal（可让 Swift 持久化）。
   3) 入口导出     —— globalThis.CongcongTV = {init,home,homeVod,category,detail,play,search,...}
*/
(function(){

  /* ---------- req ---------- */
  function req(url, obj){
    obj = obj || {};
    var r = null;
    try{
      if(typeof globalThis.__drpyFetch === 'function'){
        r = globalThis.__drpyFetch(url, obj) || null;
      }
    }catch(e){
      try{ console.error('req bridge error: '+e); }catch(_e){}
      return { content: '', headers: {} };
    }
    if(!r){ return { content: '', headers: {} }; }
    if(typeof r === 'string'){
      /* stub / host 可能直接返回 text */
      return { content: r, headers: {} };
    }
    return {
      content: (typeof r.content === 'string') ? r.content : '',
      headers: (r.headers && typeof r.headers === 'object') ? r.headers : {}
    };
  }
  globalThis.req = req;

  /* ---------- local ---------- */
  var _ns = Object.create(null);   /* ns -> (k -> v) */
  function localSet(ns, k, v){
    if(!_ns[ns]){ _ns[ns] = Object.create(null); }
    _ns[ns][k] = String(v);
    try{ if(typeof globalThis.__drpyLocal === 'object' && globalThis.__drpyLocal.set === 'function'){
      globalThis.__drpyLocal.set(ns, k, String(v));
    } }catch(e){}
  }
  function localGet(ns, k){
    var m = _ns[ns];
    return (m && Object.prototype.hasOwnProperty.call(m, k)) ? m[k] : undefined;
  }
  function localDel(ns, k){
    var m = _ns[ns];
    if(m && Object.prototype.hasOwnProperty.call(m, k)){ delete m[k]; }
    try{ if(typeof globalThis.__drpyLocal === 'object' && globalThis.__drpyLocal.delete === 'function'){
      globalThis.__drpyLocal.delete(ns, k);
    } }catch(e){}
  }
  var local = { set: localSet, get: localGet, delete: localDel };
  globalThis.local = local;

  /* ---------- 入口导出 ---------- */
  var engine = globalThis.__drpy;
  if(engine && typeof engine === 'object'){
    var api = {
      init:      (engine.init      || function(){ return ''; }).bind(engine),
      home:      (engine.home      || function(){ return ''; }).bind(engine),
      homeVod:   (engine.homeVod   || function(){ return ''; }).bind(engine),
      category:  (engine.category  || function(){ return ''; }).bind(engine),
      detail:    (engine.detail    || function(){ return ''; }).bind(engine),
      play:      (engine.play      || function(){ return ''; }).bind(engine),
      search:    (engine.search    || function(){ return ''; }).bind(engine),
      proxy:     (engine.proxy     || function(){ return ''; }).bind(engine),
      sniffer:   (engine.sniffer   || function(){ return ''; }).bind(engine),
      isVideo:   (engine.isVideo   || function(){ return ''; }).bind(engine),
      getRule:   (engine.getRule   || function(){ return null; }).bind(engine),
      fixAdM3u8Ai:(engine.fixAdM3u8Ai || function(){ return ''; }).bind(engine)
    };
    globalThis.CongcongTV = api;
    /* 兼容旧 JSEnv 的全部入口名 */
    globalThis.drpy = api;
    globalThis.__drpyApi = api;
  }

})();
""" + "\n"


if __name__ == "__main__":
    main()

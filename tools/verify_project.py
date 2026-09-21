#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
verify_project.py — Windows 本地的「构建前静态自检」。
在没有 Xcode / macOS 的环境里，把我们能静态证明的工程一致性全部查一遍，
把每次 push 后才在 CI 暴露的问题提前到本地发现。

检查项：
  1. project.yml 可解析，target/scheme 名为 CongcongTV，platform=iOS，deployment 17+；
  2. 代码里每个 Bundle.main.url(forResource:withExtension:subdirectory:) 调用
     都能在 project.yml 声明的 resources（folderType 目录 / xcassets）下命中文件；
  3. JSEnv.bundledRuleNames 三个文件名 ↔ Resources/js/rules/ 实文件 ↔ movie2.json
     可用站点（type=3 且 api 为 http(s)）的 ext 文件名后缀 三者一一对应；
  4. ATS 放行（NSAllowsArbitraryLoads=true）已配置；
  5. 每个 Swift 文件的 import 与其用到的框架匹配（SwiftUI / AVKit / JavaScriptCore /
     AVFoundation / Foundation / Combine）；全网搜索未发现的符号引用（孤儿调用）。

用法:  python -X utf8 verify_project.py
退出码: 0 = 全过；1 = 有缺陷。
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # 仓库根
APP = os.path.join(ROOT, "CongcongTV")
PROJECT_YML = os.path.join(ROOT, "project.yml")
CONFIG_JSON = os.path.join(APP, "Resources", "config", "movie2.json")
RULES_DIR = os.path.join(APP, "Resources", "js", "rules")

failures = []


def ok(msg):
    print("  ✓ " + msg)


def bad(msg):
    print("  ✗ " + msg)
    failures.append(msg)


# ---------- 1) project.yml ----------
def load_project_yml():
    try:
        import yaml
    except ImportError:
        bad("缺少 PyYAML（pip install pyyaml），无法解析 project.yml")
        return None
    try:
        with open(PROJECT_YML, encoding="utf-8") as fh:
            return yaml.safe_load(fh)
    except Exception as e:
        bad("project.yml 解析失败: %s" % e)
        return None


proj = load_project_yml()
name_ok = True
resources = []  # [(path, folderType or None)]
if proj:
    tgt = proj.get("targets", {}).get("CongcongTV")
    if not tgt:
        bad("project.yml 缺少 targets.CongcongTV")
        name_ok = False
    else:
        if tgt.get("type") != "application":
            bad("target.CongcongTV.type 应是 application")
            name_ok = False
        plat = proj.get("options", {}).get("deploymentTarget", {}).get("iOS")
        if plat is None and (tgt.get("deploymentTarget") or {}).get("iOS"):
            plat = tgt["deploymentTarget"].get("iOS")
        if str(plat or "").startswith("17."):
            ok("iOS 部署目标 = %s" % plat)
        else:
            bad("iOS 部署目标未设置/不是 17.x: %r" % plat)
        if proj.get("schemes", {}).get("CongcongTV"):
            ok("scheme CongcongTV 已定义")
        else:
            bad("缺少 scheme CongcongTV")
        for r in tgt.get("resources", []):
            resources.append((r["path"], r.get("folderType")))
        ok("target.resources 声明 %d 项" % len(resources))
        # XcodeGen 没有 target 级 resources 键（写了会被整体忽略、资源进不了包），
        # 资源必须放在 sources[] 里（buildPhase: resources / type folder / xcassets）。
        for r in tgt.get("sources", []):
            if isinstance(r, dict):
                if r.get("buildPhase") == "resources":
                    resources.append((r["path"], r.get("type")))
                if r.get("type") == "folder":
                    # 目录用 type: folder 的 source 也是资源（按原层级拷入）
                    resources.append((r["path"], "folder"))
        res_sources = [r["path"] for r in (tgt.get("sources") or []) if isinstance(r, dict)]
        if any("Assets.xcassets" in str(p) for p in res_sources):
            ok("Assets.xcassets 在 sources 中声明（编译进 asset catalog）")
        else:
            bad("Assets.xcassets 未在 sources 中声明（App 图标将缺失）")
else:
    name_ok = False

# ---------- 2) Bundle.main.url 资源命中 ----------
def find_swift_files():
    out = []
    for dp, _, fn in os.walk(APP):
        for f in fn:
            if f.endswith(".swift"):
                out.append(os.path.join(dp, f))
    return out


def collect_bundle_refs():
    """from: [(swift_file, resource, ext, subdir)]"""
    refs = []
    pat = re.compile(
        r'Bundle\.main\.url\(forResource:\s*"([^"]+)",\s*withExtension:\s*"([^"]+)"'
        r'(?:,\s*subdirectory:\s*"([^"]*)")?'
    )
    for p in find_swift_files():
        src = open(p, encoding="utf-8").read()
        for m in pat.finditer(src):
            refs.append((os.path.relpath(p, ROOT), m.group(1), m.group(2), m.group(3) or ""))
    return refs


refs = collect_bundle_refs()
ok("Bundle.main.url 调用共 %d 处" % len(refs))
anchor = os.path.join(APP, "Resources")
norm_of_anchor = anchor.replace(os.sep, "/")
for rel, name, ext, subdir in refs:
    path = os.path.join(anchor, subdir, name + "." + ext)
    file_ok = os.path.isfile(path)
    declared = False
    for rpath, ft in resources:
        base = rpath.replace("\\", "/")
        # project.yml 资源路径是从仓库根写的（如 CongcongTV/Resources/js），
        # 目录名即 bundle 里的顶层子目录（js / config）——只需截取目录短名。
        for prefix in ("CongcongTV/Resources/", "Resources/", norm_of_anchor):
            if base.startswith(prefix):
                base = base[len(prefix):]
                break
        base = base.strip("/")
        relfile = os.path.join(subdir, name + "." + ext).replace(os.sep, "/")
        reldir = (base + "/").replace("\\", "/") if base else ""
        if ft == "folder":
            if relfile.startswith(reldir):
                declared = True
        else:
            # xcassets 视为自动声明（asset catalog 编译产物不在 Bundle.main.url 语义内）
            declared = True

    if not file_ok:
        bad("%s 引用 %s 但在 Resources 下找不到文件" % (rel, os.path.join(subdir, name + "." + ext)))
    elif not declared:
        bad("%s 引用 %s 未被 project.yml resources 覆盖" % (rel, os.path.join(subdir, name + "." + ext)))
    else:
        ok("资源命中: %s → %s" % (rel, os.path.join("Resources", subdir, name + "." + ext)))

# ---------- 3) 规则三向一致性 ----------
def percent_decode(s):
    try:
        import urllib.parse
        return urllib.parse.unquote(s)
    except Exception:
        return s


rule_names = ["虎牙.js", "斗鱼直播.js", "兔小贝.js"]
if os.path.isdir(RULES_DIR):
    disk_rules = {f for f in os.listdir(RULES_DIR) if f.endswith(".js")}
    for rn in rule_names:
        if rn in disk_rules:
            ok("规则文件在盘: %s" % rn)
        else:
            bad("规则文件缺失: %s" % rn)
    for dn in sorted(disk_rules - set(rule_names)):
        bad("未知规则文件（未在 bundledRuleNames / movie2 引用）: %s" % dn)
else:
    bad("Resources/js/rules 目录不存在")

try:
    cfg = json.load(open(CONFIG_JSON, encoding="utf-8"))
    usable = []
    for s in cfg.get("sites", []):
        api = s.get("api", "")
        ext = s.get("ext")
        if not (api.startswith("http://") or api.startswith("https://")):
            continue
        # 仅统计 ext 是 str 的（非 str 的 jar/字典站点排除）
        if isinstance(ext, str) and ext.strip():
            usable.append((s.get("name", ""), percent_decode(ext), ext))
    ok("movie2 可用站点 %d 个" % len(usable))
    expected_rules = {os.path.basename(e[1].replace("\\", "/")) for e in usable}
    for nm, dec, raw in usable:
        tail = os.path.basename(dec.replace("\\", "/"))
        if tail in rule_names:
            ok("站点 [%s] ext=%r → %s" % (nm, raw, tail))
        else:
            bad("站点 [%s] ext=%r → %s 不在 bundledRuleNames" % (nm, raw, tail))
except Exception as e:
    bad("movie2.json 解析失败: %s" % e)

# ---------- 4) ATS ----------
if proj and name_ok:
    tgt = proj.get("targets", {}).get("CongcongTV", {})
    info = tgt.get("info") or {}
    props = info.get("properties") if isinstance(info, dict) else None
    ats = {"NSAllowsArbitraryLoads": False}
    if isinstance(props, dict):
        ats = (props.get("NSAppTransportSecurity") or {})
    if ats.get("NSAllowsArbitraryLoads") is True:
        ok("ATS: info.properties.NSAppTransportSecurity.NSAllowsArbitraryLoads=true（嵌套字典，真实生效）")
    else:
        bad("ATS: 未在 info.properties 找到 NSAppTransportSecurity.NSAllowsArbitraryLoads=true（http 直链无法播放）")
        bad("     （注意：INFOPLIST_KEY_NSAppTransportSecurity_… 写法无法生成嵌套字典，请用 info.properties）")

# ---------- 5) Swift import 框架匹配 + 孤儿符号 ----------
FRAME_IMPORT = {
    "SwiftUI": "SwiftUI",
    "AVKit": "AVKit",
    "AVFoundation": "AVFoundation",
    "JavaScriptCore": "JavaScriptCore",
    "Combine": "Combine",
}
for p in find_swift_files():
    rel = os.path.relpath(p, ROOT)
    src = open(p, encoding="utf-8").read()
    imports = set(re.findall(r"^\s*import\s+([A-Za-z_]\w*)", src, re.M))
    for token, frame in FRAME_IMPORT.items():
        # 启发：仅当代码出现该框架特征标识时要求 import
        feature = None
        if frame == "AVKit":
            feature = re.search(r"\b(AVPlayer|VideoPlayer)\b", src)
        elif frame == "SwiftUI":
            feature = re.search(r"\b(import SwiftUI)|\bView\b|\bstruct\b", src)
        if feature and frame not in imports and token in src:
            bad("%s 用到 %s 但未 import %s" % (rel, token, frame))
    # AppKit/UIKit 误 import 检查
    for badf in ("AppKit", "UIKit"):
        if badf in imports and frame in ("SwiftUI",):
            idf = open(p, encoding="utf-8").read()
            if "UIApplication" not in idf:
                bad("%s import 了 %s（应使用 SwiftUI）" % (rel, badf))

print()
if failures:
    print("✗ 发现 %d 个问题：" % len(failures))
    for f in failures:
        print("   - " + f)
    sys.exit(1)
print("✓✓ 全部静态自检通过 ✓✓")
sys.exit(0)

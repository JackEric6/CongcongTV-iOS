import Foundation
import JavaScriptCore

final class JavaScriptSpiderRunner {
    func call(site: TVBoxSite, method: String, arguments: [Any]) async throws -> String {
        let apiSource = try await HTTPClient.text(site.api)
        let extensionSource: String?
        if Self.isRemoteJavaScript(site.ext) {
            extensionSource = try? await HTTPClient.text(site.ext)
        } else {
            extensionSource = nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let value = try Self.execute(apiSource: apiSource, extensionSource: extensionSource,
                                                 site: site, method: method, arguments: arguments)
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func execute(apiSource: String, extensionSource: String?, site: TVBoxSite,
                                method: String, arguments: [Any]) throws -> String {
        if let data = apiSource.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
            return apiSource
        }

        let context = JSContext()!
        var scriptError: Error?
        context.exceptionHandler = { _, exception in
            if let exception {
                scriptError = TVBoxError.script(exception.toString() ?? "JavaScript exception")
            }
        }

        let bridge: @convention(block) (String, [String: Any]?) -> [String: Any] = { address, options in
            let headers = options?["headers"] as? [String: String] ?? [:]
            let body = HTTPClient.syncText(address, headers: headers)
            return [
                "ok": !body.isEmpty,
                "status": body.isEmpty ? 500 : 200,
                "url": address,
                "body": body,
                "content": body,
                "headers": [:] as [String: String]
            ]
        }
        context.setObject(bridge, forKeyedSubscript: "__nativeHttp" as NSString)
        context.setObject(bridge, forKeyedSubscript: "__drpyFetch" as NSString)
        _ = context.evaluateScript("""
        function http(url, options) { return __nativeHttp(String(url), options || {}); }
        function req(url, options) { return http(url, options); }
        function fetch(url, options) { return http(url, options); }
        function print() { return Array.prototype.slice.call(arguments).join(' '); }
        function log() { return print.apply(null, arguments); }
        var MOBILE_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 Mobile';
        var IOS_UA = MOBILE_UA;
        var PC_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15';
        var UA = MOBILE_UA;
        var VERSION = 'ios-codex';
        var RKEY = '';
        function getProxyUrl() { return ''; }
        var global = this;
        var window = this;
        var self = this;
        """)

        if let runtime = bundledRuntime() {
            _ = context.evaluateScript(runtime)
        } else {
            installBundledModules(in: context)
            installCompatParsers(in: context)
        }
        let siteSource: String?
        if let extensionSource, !extensionSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            siteSource = extensionSource
        } else if isDrpyEngine(apiSource) {
            siteSource = nil
        } else {
            siteSource = apiSource
        }
        if let siteSource {
            _ = context.evaluateScript(normalizeSiteSource(siteSource))
        }
        if let scriptError { throw scriptError }

        guard let spider = context.objectForKeyedSubscript("__drpy"), spider.isObject else {
            throw TVBoxError.script("drpy2 运行时没有正确加载")
        }
        if let initFunction = spider.forProperty("init"), initFunction.isObject {
            let ext: Any
            if let rule = context.objectForKeyedSubscript("__siteRule"), !rule.isUndefined, !rule.isNull,
               let object = rule.toObject() {
                ext = object
            } else {
                ext = parseExtension(site.ext)
            }
            _ = initFunction.call(withArguments: [ext])
        }
        if let scriptError { throw scriptError }
        guard let function = spider.forProperty(method), function.isObject else {
            throw TVBoxError.script("脚本未提供 \(method) 方法")
        }
        let result = function.call(withArguments: arguments)
        if let scriptError { throw scriptError }
        guard let result else { throw TVBoxError.script("\(method) 没有返回结果") }
        if result.isString { return result.toString() ?? "" }
        if let object = result.toObject(), JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object, options: []) {
            return String(decoding: data, as: UTF8.self)
        }
        return result.toString() ?? ""
    }

    private static func isRemoteJavaScript(_ value: String) -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return url.path.lowercased().hasSuffix(".js") || url.absoluteString.lowercased().contains(".js?")
    }

    private static func isDrpyEngine(_ source: String) -> Bool {
        source.contains("function init_test") && source.contains("function category(") && source.contains("function search(")
    }

    private static func bundledRuntime() -> String? {
        guard let base = resourceDirectory() else { return nil }
        return try? String(contentsOf: base.appendingPathComponent("JSEnv.bundle.js"), encoding: .utf8)
    }

    private static func resourceDirectory() -> URL? {
        Bundle.main.url(forResource: "Resources", withExtension: nil)?.appendingPathComponent("JS")
            ?? Bundle.main.url(forResource: "JS", withExtension: nil)
    }

    private static func parseExtension(_ ext: String) -> Any {
        guard let data = ext.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return ext
        }
        return object
    }

    private static func normalizeSiteSource(_ source: String) -> String {
        var result = source
        result = result.replacingOccurrences(of: #"import\s+cheerio\s+from\s*["'][^"']+["']\s*;?"#, with: "var cheerio = globalThis.__cheerio;", options: .regularExpression)
        result = result.replacingOccurrences(of: #"import\s+模板\s+from\s*["'][^"']+["']\s*;?"#, with: "var 模板 = globalThis.__template;", options: .regularExpression)
        result = result.replacingOccurrences(of: #"import\s*\{\s*gbkTool\s*\}\s*from\s*["'][^"']+["']\s*;?"#, with: "var gbkTool = globalThis.gbkTool;", options: .regularExpression)
        result = result.replacingOccurrences(of: #"import\s*(?:[^;"']+\s+from\s*)?["'][^"']+["']\s*;?"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"__JS_SPIDER__\s*="#, with: "globalThis.__siteRule =", options: .regularExpression)
        result = result.replacingOccurrences(of: #"export\s+default"#, with: "globalThis.__siteRule =", options: .regularExpression)
        result += "\nif (typeof rule !== 'undefined' && typeof globalThis.__siteRule === 'undefined') { globalThis.__siteRule = rule; }\n"
        return result
    }

    private static func installBundledModules(in context: JSContext) {
        guard let base = resourceDirectory() else { return }

        func source(_ name: String) -> String? {
            try? String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)
        }

        if let cheerio = source("cheerio.min.js") {
            _ = context.evaluateScript(transformNamedExports(cheerio, globalName: "__cheerio"))
        }
        if let crypto = source("crypto-js.js") { evaluateCommonJS(crypto, name: "CryptoJS", in: context) }
        if let pako = source("pako.min.js") { evaluateCommonJS(pako, name: "pako", in: context) }
        if let jinja = source("jinja.js") { evaluateCommonJS(jinja, name: "jinja", in: context) }
        if let rsa = source("node-rsa.js") { evaluateCommonJS(rsa, name: "NODERSA", in: context) }
        if let json5 = source("json5.js") { evaluateCommonJS(json5, name: "JSON5", in: context) }
        if let gbk = source("gbk.js") {
            let code = "(function(){\n" + gbk.replacingOccurrences(of: "export function gbkTool", with: "function gbkTool") + "\nglobalThis.gbkTool = gbkTool;\n})();"
            _ = context.evaluateScript(code)
        }
        if let template = source("模板.js") {
            let code = "(function(){\n" + template.replacingOccurrences(of: "export default {muban,getMubans};", with: "globalThis.__template = {muban: muban, getMubans: getMubans};") + "\n})();"
            _ = context.evaluateScript(code)
        }
    }

    private static func installCompatParsers(in context: JSContext) {
        _ = context.evaluateScript("""
        function __tvLoad(html) {
            return globalThis.__cheerio.load(String(html || ''), null, false);
        }
        function pdfh(html, parse) {
            if (!parse) { return ''; }
            var parts = String(parse).split('&&');
            var node = __tvLoad(html)(parts[0]).first();
            var field = parts.length > 1 ? parts[parts.length - 1] : 'Text';
            if (field === 'Text') { return node.text().trim(); }
            if (field === 'Html') { return node.html() || ''; }
            return node.attr(field) || '';
        }
        function pdfa(html, parse) {
            if (!parse) { return []; }
            var $ = __tvLoad(html);
            var result = [];
            $(String(parse)).each(function(_, element) {
                result.push(globalThis.__cheerio.html(element));
            });
            return result;
        }
        function pd(html, parse) { return pdfh(html, parse); }
        """)
    }

    private static func evaluateCommonJS(_ source: String, name: String, in context: JSContext) {
        let safeName = name.replacingOccurrences(of: "-", with: "_")
        let code = "(function(){var module={exports:{}};var exports=module.exports;\n\(source)\nglobalThis.__\(safeName)=module.exports||globalThis.__\(safeName);})();"
        _ = context.evaluateScript(code)
        _ = context.evaluateScript("globalThis.\(name) = globalThis.__\(safeName);")
    }

    private static func transformNamedExports(_ source: String, globalName: String) -> String {
        guard let start = source.range(of: "export{", options: .backwards),
              let end = source.range(of: "};", range: start.lowerBound..<source.endIndex) else {
            return source + "\nglobalThis.\(globalName) = globalThis.\(globalName) || {};"
        }
        let body = String(source[start.upperBound..<end.lowerBound])
        let fields = body.split(separator: ",").compactMap { item -> String? in
            let parts = item.split(separator: " as ").map(String.init)
            guard parts.count == 2 else { return nil }
            return "\(parts[1]): \(parts[0])"
        }.joined(separator: ",")
        var trimmed = source
        trimmed.removeSubrange(start.lowerBound..<end.upperBound)
        return "(function(){\n" + trimmed + "\nglobalThis.\(globalName) = {\(fields)};\n})();"
    }
}

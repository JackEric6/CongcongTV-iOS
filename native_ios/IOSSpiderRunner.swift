import Foundation
import JavaScriptCore

enum IOSSpiderError: LocalizedError {
    case invalidURL
    case script(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "动态脚本地址无效"
        case .script(let message): return "动态脚本执行失败：\(message)"
        case .emptyResult: return "动态脚本没有返回结果"
        }
    }
}

final class IOSSpiderRunner {
    func call(api: String, ext: String, method: String, arguments: [Any]) async throws -> String {
        let apiSource = try await HTTPClient.text(api)
        let extensionSource: String?
        if Self.isRemoteJavaScript(ext) {
            extensionSource = try? await HTTPClient.text(ext)
        } else {
            extensionSource = nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try Self.execute(
                        apiSource: apiSource,
                        extensionSource: extensionSource,
                        method: method,
                        arguments: arguments
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func execute(
        apiSource: String,
        extensionSource: String?,
        method: String,
        arguments: [Any]
    ) throws -> String {
        if let data = apiSource.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
            return apiSource
        }

        let context = JSContext()!
        var scriptError: Error?
        context.exceptionHandler = { _, exception in
            if let exception {
                scriptError = IOSSpiderError.script(exception.toString() ?? "JavaScript exception")
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

        guard let base = resourceDirectory(),
              let runtime = try? String(contentsOf: base.appendingPathComponent("JSEnv.bundle.js"), encoding: .utf8) else {
            throw IOSSpiderError.script("缺少 JSEnv.bundle.js 资源")
        }
        _ = context.evaluateScript(runtime)

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
            throw IOSSpiderError.script("drpy2 运行时没有正确加载")
        }
        if let initFunction = spider.forProperty("init"), initFunction.isObject {
            let extValue: Any = parseExtension(ext)
            _ = initFunction.call(withArguments: [extValue])
        }
        if let scriptError { throw scriptError }
        guard let function = spider.forProperty(method), function.isObject else {
            throw IOSSpiderError.script("脚本未提供 \(method) 方法")
        }
        let result = function.call(withArguments: arguments)
        if let scriptError { throw scriptError }
        guard let result else { throw IOSSpiderError.emptyResult }
        if result.isString { return result.toString() ?? "" }
        if let object = result.toObject(),
           JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object, options: []) {
            return String(decoding: data, as: UTF8.self)
        }
        return result.toString() ?? ""
    }

    private static func resourceDirectory() -> URL? {
        Bundle.main.bundleURL.appendingPathComponent("flutter_assets/assets/js")
    }

    private static func parseExtension(_ ext: String) -> Any {
        guard let data = ext.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return ext
        }
        return object
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
}

private enum HTTPClient {
    static func text(_ address: String, headers: [String: String] = [:]) async throws -> String {
        let (data, _) = try await get(address, headers: headers)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    static func get(_ address: String, headers: [String: String] = [:]) async throws -> (Data, URLResponse) {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw IOSSpiderError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("丛丛影视/1.0 (Flutter iOS)", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await URLSession.shared.data(for: request)
    }

    static func syncText(_ address: String, headers: [String: String] = [:]) -> String {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else { return "" }
        let semaphore = DispatchSemaphore(value: 0)
        var result = ""
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("丛丛影视/1.0 (Flutter iOS)", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data { result = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self) }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 20)
        return result
    }
}

import Foundation
import GCDWebServer

/// Localhost-only adapter for the Xigua CMS endpoint used by movie2.json.
final class XiguaCMSProxy {
    static let shared = XiguaCMSProxy()
    static let baseURL = "http://127.0.0.1:9978/xgzy"

    private let server = GCDWebServer()
    private let stateLock = NSLock()
    private var started = false

    private let upstream = URL(string: "https://caiji.xgzyapi.com/api.php/provide/vod/from/xiguam3u8/")!
    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1"
    private let childCategories: [String: [String]] = [
        "1": ["6", "7", "8", "9", "10", "11", "12", "20", "34", "37"],
        "2": ["13", "14", "15", "16", "21", "22", "23", "24"],
        "3": ["25", "26", "27", "28"],
        "4": ["29", "30", "31", "32", "33"]
    ]

    private init() {}

    /// Starts the proxy once and binds it to the loopback interface only.
    @discardableResult
    func startIfNeeded() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        if started { return true }

        server.addHandler(
            forMethod: "GET",
            path: "/xgzy",
            request: GCDWebServerRequest.self,
            processBlock: { [weak self] request in
                guard let self else { return nil }
                return self.handle(request)
            }
        )

        do {
            try server.start(options: [
                GCDWebServerOption_Port: 9978,
                GCDWebServerOption_BindToLocalhost: true
            ])
            started = true
            return true
        } catch {
            return false
        }
    }

    private func handle(_ request: GCDWebServerRequest) -> GCDWebServerResponse {
        let params = request.query ?? [:]
        do {
            let result: [String: Any]
            let ids = value(params, "ids")
            let keyword = value(params, "wd")
            let type = value(params, "t")
            let play = value(params, "play")
            if !play.isEmpty {
                return playResponse(play)
            } else if !ids.isEmpty {
                result = try fetch(["ac": "detail", "ids": ids])
            } else if !keyword.isEmpty {
                let details = try fetch(["ac": "detail", "wd": keyword])
                result = listIsEmpty(details) ? try fetch(["ac": "list", "wd": keyword]) : details
            } else if !type.isEmpty {
                result = try category(type: type, page: value(params, "pg"))
            } else {
                var home = try fetch(["ac": "videolist", "pg": "1"])
                if var list = home["list"] as? [[String: Any]] {
                    hydrateImages(&list)
                    home["list"] = list
                }
                result = home
            }
            return response(normalize(result))
        } catch {
            return errorResponse("西瓜资源适配失败: \(errorMessage(error))")
        }
    }

    private func category(type: String, page: String) throws -> [String: Any] {
        let pageValue = page.isEmpty ? "1" : page
        guard let children = childCategories[type] else {
            var result = try fetch(["ac": "videolist", "t": type, "pg": pageValue])
            if var list = result["list"] as? [[String: Any]] {
                hydrateImages(&list)
                result["list"] = list
            }
            return result
        }

        var merged: [[String: Any]] = []
        var classes: Any?
        var total = 0
        for child in children {
            let item = try fetch(["ac": "videolist", "t": child, "pg": pageValue])
            if classes == nil { classes = item["class"] }
            total += integer(item["total"])
            if let list = item["list"] as? [[String: Any]] {
                merged.append(contentsOf: list.prefix(max(0, 20 - merged.count)))
            }
        }
        hydrateImages(&merged)
        var result: [String: Any] = [
            "code": 1,
            "msg": "数据列表",
            "page": integer(pageValue) == 0 ? 1 : integer(pageValue),
            "pagecount": max(1, (total + 19) / 20),
            "limit": "20",
            "total": total,
            "list": merged
        ]
        if let classes { result["class"] = classes }
        return result
    }

    private func fetch(_ parameters: [String: String]) throws -> [String: Any] {
        var components = URLComponents(url: upstream, resolvingAgainstBaseURL: false)!
        components.queryItems = parameters.compactMap { key, value in
            value.isEmpty ? nil : URLQueryItem(name: key, value: value)
        }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[String: Any], Error> = .failure(ProxyError.invalidJSON)
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                result = .failure(ProxyError.http(status))
                return
            }
            guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                result = .failure(ProxyError.invalidJSON)
                return
            }
            result = .success(object)
        }.resume()
        _ = semaphore.wait(timeout: .now() + 20)
        return try result.get()
    }

    private func playResponse(_ rawValue: String) -> GCDWebServerResponse {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageURL = URL(string: value), isHTTPURL(pageURL) else {
            return errorResponse("播放地址必须是 HTTP/HTTPS URL")
        }

        let mediaURL: String
        if isDirectMediaURL(pageURL) {
            mediaURL = pageURL.absoluteString
        } else {
            mediaURL = extractedMediaURL(from: pageURL) ?? pageURL.absoluteString
        }
        return response(["code": 1, "url": mediaURL])
    }

    private func extractedMediaURL(from pageURL: URL) -> String? {
        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,*/*", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            defer { semaphore.signal() }
            guard let self,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data,
                  let body = String(data: data, encoding: .utf8) else { return }
            result = self.findMediaURL(in: body, relativeTo: pageURL)
        }.resume()
        _ = semaphore.wait(timeout: .now() + 20)
        return result
    }

    private func findMediaURL(in body: String, relativeTo pageURL: URL) -> String? {
        let patterns = [
            #"(?i)[\"'](?:url|playurl|play_url|file|src)[\"']\s*[:=]\s*[\"']([^\"']+)[\"']"#,
            #"(?i)(?:url|playurl|play_url|file|src)\s*=\s*[\"']([^\"']+)[\"']"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(body.startIndex..<body.endIndex, in: body)
            for match in regex.matches(in: body, range: range) {
                guard match.numberOfRanges > 1,
                      let valueRange = Range(match.range(at: 1), in: body) else { continue }
                let candidate = String(body[valueRange])
                    .replacingOccurrences(of: "\\/", with: "/")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = absoluteURL(candidate, relativeTo: pageURL),
                      isHTTPURL(url), isDirectMediaURL(url) else { continue }
                return url.absoluteString
            }
        }
        return nil
    }

    private func absoluteURL(_ value: String, relativeTo baseURL: URL) -> URL? {
        var candidate = value
        if candidate.hasPrefix("//") {
            candidate = "\(baseURL.scheme ?? "https"):\(candidate)"
        }
        return URL(string: candidate, relativeTo: baseURL)?.absoluteURL
    }

    private func isHTTPURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    private func isDirectMediaURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return [".m3u8", ".mp4", ".flv", ".ts", ".mkv", ".webm", ".mov"]
            .contains { path.hasSuffix($0) }
    }

    private func hydrateImages(_ list: inout [[String: Any]]) {
        let ids = list.compactMap { item -> String? in
            let pic = value(item, "vod_pic")
            let id = value(item, "vod_id")
            return pic.isEmpty && !id.isEmpty ? id : nil
        }
        guard !ids.isEmpty else { return }
        var details: [String: [String: Any]] = [:]
        for start in stride(from: 0, to: ids.count, by: 10) {
            let batch = Array(ids[start..<min(start + 10, ids.count)]).joined(separator: ",")
            if let object = try? fetch(["ac": "detail", "ids": batch]),
               let values = object["list"] as? [[String: Any]] {
                for item in values {
                    let id = value(item, "vod_id")
                    if !id.isEmpty { details[id] = item }
                }
            }
        }
        for index in list.indices {
            let id = value(list[index], "vod_id")
            guard let detail = details[id] else { continue }
            for key in ["vod_pic", "vod_pic_thumb", "vod_pic_slide"] where value(list[index], key).isEmpty {
                let image = value(detail, key)
                if !image.isEmpty { list[index][key] = image }
            }
        }
    }

    private func normalize(_ object: [String: Any]) -> [String: Any] {
        var copy = object
        if var list = copy["list"] as? [[String: Any]] {
            for index in list.indices {
                for key in ["vod_pic", "vod_pic_thumb", "vod_pic_slide"] {
                    let image = value(list[index], key)
                    if image.hasPrefix("//") { list[index][key] = "https:" + image }
                }
            }
            copy["list"] = list
        }
        return copy
    }

    private func response(_ object: [String: Any]) -> GCDWebServerResponse {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            return errorResponse("JSON 编码失败")
        }
        let response = GCDWebServerDataResponse(data: data, contentType: "application/json; charset=utf-8")
        response.setValue("no-store", forAdditionalHeader: "Cache-Control")
        return response
    }

    private func errorResponse(_ message: String) -> GCDWebServerResponse {
        response([
            "code": 0,
            "msg": message,
            "page": 1,
            "pagecount": 1,
            "limit": "20",
            "total": 0,
            "list": []
        ])
    }

    private func listIsEmpty(_ object: [String: Any]) -> Bool {
        guard let list = object["list"] as? [Any] else { return true }
        return list.isEmpty
    }

    private func value(_ dictionary: [String: Any], _ key: String) -> String {
        if let value = dictionary[key] as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = dictionary[key] as? NSNumber { return value.stringValue }
        return ""
    }

    private func integer(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    private func errorMessage(_ error: Error) -> String {
        if let proxyError = error as? ProxyError { return proxyError.description }
        return error.localizedDescription
    }

    private enum ProxyError: Error, CustomStringConvertible {
        case http(Int)
        case invalidJSON

        var description: String {
            switch self {
            case .http(let status): return "HTTP \(status)"
            case .invalidJSON: return "上游返回无效 JSON"
            }
        }
    }
}

import Foundation

/// 西瓜资源 CMS 的原生 iOS 客户端。
/// Android 端同样通过该 JSON API 的 `ac=detail` 搜索与详情接口取得 xiguam3u8 直链。
actor XiguaCMSService {
    static let shared = XiguaCMSService()

    static let sourceKey = "xgzy"
    static let sourceName = "西瓜资源"

    private let endpoint = URL(string: "https://caiji.xgzyapi.com/api.php/provide/vod/from/xiguam3u8/")!
    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    /// 西瓜 CMS 对仅含 wd 的请求偶发返回空结果，因此优先使用 ac=detail。
    func search(_ keyword: String) async -> [VOD] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let detailResults = await loadVods([
            URLQueryItem(name: "ac", value: "detail"),
            URLQueryItem(name: "wd", value: trimmed)
        ])
        if !detailResults.isEmpty { return detailResults }

        return await loadVods([
            URLQueryItem(name: "ac", value: "list"),
            URLQueryItem(name: "wd", value: trimmed)
        ])
    }

    func detail(vodId: String) async -> VOD? {
        guard !vodId.isEmpty else { return nil }
        return await loadVods([
            URLQueryItem(name: "ac", value: "detail"),
            URLQueryItem(name: "ids", value: vodId)
        ]).first
    }

    /// 将西瓜播放字段解析为可直接交给播放器的媒体地址。
    /// 已经是 m3u8、mp4、flv、ts 等直链时不会发起额外请求；普通播放页解析失败则回退原地址。
    func resolvePlaybackURL(_ value: String) async -> String {
        let original = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return value }
        guard let pageURL = URL(string: original), isHTTPURL(pageURL) else { return value }
        guard !isDirectMediaURL(pageURL) else { return original }

        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let body = String(data: data, encoding: .utf8),
                  let mediaURL = extractMediaURL(from: body, baseURL: pageURL) else {
                return value
            }
            return mediaURL
        } catch {
            return value
        }
    }

    private func loadVods(_ queryItems: [URLQueryItem]) async -> [VOD] {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return []
        }
        components.queryItems = queryItems
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }
            return vods(from: data)
        } catch {
            return []
        }
    }

    private func vods(from data: Data) -> [VOD] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["list"] as? [[String: Any]] else {
            return []
        }
        return list.compactMap(vod(from:))
    }

    private func vod(from value: [String: Any]) -> VOD? {
        guard let id = stringValue(value["vod_id"]),
              let name = stringValue(value["vod_name"]),
              !id.isEmpty,
              !name.isEmpty else {
            return nil
        }
        return VOD(
            vod_id: id,
            vod_name: name,
            vod_pic: stringValue(value["vod_pic"]) ?? "",
            vod_remarks: stringValue(value["vod_remarks"]) ?? "",
            vod_content: stringValue(value["vod_content"]) ?? "",
            vod_play_from: stringValue(value["vod_play_from"]) ?? "",
            vod_play_url: stringValue(value["vod_play_url"]) ?? "",
            sourceKey: Self.sourceKey,
            sourceName: Self.sourceName
        )
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func extractMediaURL(from body: String, baseURL: URL) -> String? {
        let content = unescape(body)
        let patterns = [
            #"(?i)[\"'](?:url|playurl|play_url|file|src)[\"']\s*[:=]\s*[\"']([^\"']+)[\"']"#,
            #"(?i)(?:url|playurl|play_url|file|src)\s*=\s*[\"']([^\"']+)[\"']"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            for match in regex.matches(in: content, range: range) {
                guard match.numberOfRanges > 1,
                      let valueRange = Range(match.range(at: 1), in: content) else { continue }
                let rawCandidate = String(content[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let candidate = absoluteURL(rawCandidate, relativeTo: baseURL),
                      isDirectMediaURL(candidate) else { continue }
                return candidate.absoluteString
            }
        }
        return nil
    }

    private func absoluteURL(_ value: String, relativeTo baseURL: URL) -> URL? {
        var candidate = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\/", with: "/")
        if candidate.hasPrefix("//") {
            candidate = "\(baseURL.scheme ?? "https"):\(candidate)"
        }
        return URL(string: candidate, relativeTo: baseURL)?.absoluteURL
    }

    private func isDirectMediaURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return [".m3u8", ".mp4", ".flv", ".ts", ".mkv", ".webm", ".mov"]
            .contains(where: { path.hasSuffix($0) })
    }

    private func isHTTPURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    private func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u002f", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}

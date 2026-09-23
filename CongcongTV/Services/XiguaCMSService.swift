import Foundation

/// 西瓜资源 CMS 的原生 iOS 客户端。
/// Android 端同样通过该 JSON API 的 `ac=detail` 搜索与详情接口取得 xiguam3u8 直链。
actor XiguaCMSService {
    static let shared = XiguaCMSService()

    static let sourceKey = "xgzy"
    static let sourceName = "西瓜资源"

    /// 西瓜代理对父分类做了子分类聚合，iOS 端固定展示这四个入口。
    static let parentCategories: [Category] = [
        Category(type_id: "1", type_name: "电影"),
        Category(type_id: "2", type_name: "连续剧"),
        Category(type_id: "3", type_name: "综艺"),
        Category(type_id: "4", type_name: "动漫")
    ]

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

    func categories() -> [Category] {
        Self.parentCategories
    }

    /// 读取代理聚合后的父分类片单。代理负责将父分类映射到西瓜子分类并补齐海报。
    func category(tid: String, page: Int = 1) async -> [VOD] {
        guard Self.parentCategories.contains(where: { $0.type_id == tid }) else { return [] }
        return await loadVods([
            URLQueryItem(name: "t", value: tid),
            URLQueryItem(name: "pg", value: String(max(1, page)))
        ])
    }

    func detail(vodId: String) async -> VOD? {
        guard !vodId.isEmpty else { return nil }
        return await loadVods([
            URLQueryItem(name: "ac", value: "detail"),
            URLQueryItem(name: "ids", value: vodId)
        ]).first
    }

    /// 通过应用内代理将西瓜播放字段解析为可直接交给播放器的媒体地址。
    /// 代理请求失败或没有返回有效地址时回退原始地址。
    func resolvePlaybackURL(_ value: String) async -> String {
        let original = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return value }
        guard XiguaCMSProxy.shared.startIfNeeded() else { return value }
        guard var components = URLComponents(string: XiguaCMSProxy.baseURL) else { return value }
        components.queryItems = [URLQueryItem(name: "play", value: original)]
        guard let url = components.url else { return value }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let mediaURL = stringValue(root?["url"]),
                  !mediaURL.isEmpty else {
                return value
            }
            return mediaURL
        } catch {
            return value
        }
    }

    private func loadVods(_ queryItems: [URLQueryItem]) async -> [VOD] {
        guard XiguaCMSProxy.shared.startIfNeeded(),
              var components = URLComponents(string: XiguaCMSProxy.baseURL) else {
            return []
        }
        components.queryItems = queryItems
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
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

}

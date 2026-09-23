import Foundation

/// 豆瓣当年热门影音条目，供首页推荐与搜索热榜复用。
struct DoubanTrendingItem: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let cover: String
    let rate: String
}

/// 读取豆瓣热门影音并按中国自然日缓存。
/// 服务本身不负责把条目转换为 VOD，也不承担导航或 UI 逻辑。
actor DoubanTrendingService {
    static let shared = DoubanTrendingService()

    private let endpoint = URL(string: "https://movie.douban.com/j/new_search_subjects")!
    private let session: URLSession
    private let defaults: UserDefaults
    private let calendar: Calendar

    private enum Keys {
        static let items = "congcongtv.doubanTrending.items"
        static let day = "congcongtv.doubanTrending.day"
    }

    private init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.session = session
        self.defaults = defaults
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        self.calendar = calendar
    }

    /// 加载热门条目。任何失败均回退到历史缓存，且不会向调用方抛出异常。
    func loadTrending() async -> [DoubanTrendingItem] {
        let today = dayString(for: Date())
        if defaults.string(forKey: Keys.day) == today {
            let cached = readCache()
            if !cached.isEmpty {
                return cached
            }
        }

        do {
            let data = try await fetch()
            let items = parse(data).prefix(20).map { $0 }
            guard !items.isEmpty else { return readCache() }
            writeCache(items, day: today)
            return items
        } catch {
            return readCache()
        }
    }

    /// 兼容首页/搜索页面更直观的调用命名。
    func loadHotItems() async -> [DoubanTrendingItem] {
        await loadTrending()
    }

    private func fetch() async throws -> Data {
        let year = calendar.component(.year, from: Date())
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "sort", value: "U"),
            URLQueryItem(name: "range", value: "0,10"),
            URLQueryItem(name: "tags", value: ""),
            URLQueryItem(name: "playable", value: "1"),
            URLQueryItem(name: "start", value: "0"),
            URLQueryItem(name: "year_range", value: "\(year),\(year)")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func parse(_ data: Data) -> [DoubanTrendingItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = root["data"] as? [[String: Any]] else { return [] }

        var seen = Set<String>()
        return values.compactMap { value in
            let title = (value["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let cover = value["cover"] as? String ?? ""
            let id = stringValue(value["id"]) ?? (cover.isEmpty ? title : cover)
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            return DoubanTrendingItem(
                id: id,
                title: title,
                cover: cover,
                rate: stringValue(value["rate"]) ?? ""
            )
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func readCache() -> [DoubanTrendingItem] {
        guard let data = defaults.data(forKey: Keys.items),
              let items = try? JSONDecoder().decode([DoubanTrendingItem].self, from: data) else {
            return []
        }
        return Array(items.prefix(20))
    }

    private func writeCache(_ items: [DoubanTrendingItem], day: String) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Keys.items)
        defaults.set(day, forKey: Keys.day)
    }

    private func dayString(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

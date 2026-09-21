import Foundation
import Combine

/// 配置仓库：内置 movie2 配置 + 用户自定义配置 URL / JSON。
/// 「最主要的一点：还得用原有配置文件」—— 这里默认加载内置的旧 movie2 配置原文，
/// 用户也可以填任意配置 URL（如 https://pse.is/9mr5uw 或直接贴 JSON）。
/// 配置文件本身从不被改写；解析出来的站点/直播只用原字段展示与调用。
final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    /// 默认配置：丛丛影视原有的 movie2（ghproxy 镜像）
    static let defaultConfigURL = "https://ghproxy.net/https://raw.githubusercontent.com/JackEric6/movie/refs/heads/main/movie2"

    /// 用户保存的配置 URL（UserDefaults 持久化）
    @Published private(set) var userConfigURL: String {
        didSet {
            UserDefaults.standard.set(userConfigURL, forKey: Keys.userConfigURL)
        }
    }

    /// 当前生效的解析结果
    @Published private(set) var config: AppConfig = AppConfig()
    /// 最近一次加载/解析错误
    @Published private(set) var lastError: String?

    private(set) var lastLoadedFrom: LoadSource = .none

    enum LoadSource: Equatable {
        case none
        case builtin
        case remote
        case paste
    }

    private enum Keys {
        static let userConfigURL = "congcongtv.config.url"
        static let history = "congcongtv.history"
        static let favorites = "congcongtv.favorites"
    }

    private let decoder = JSONDecoder()

    private init() {
        let saved = UserDefaults.standard.string(forKey: Keys.userConfigURL)
        /// 默认即内置 movie2；若用户从未设置，则用默认 URL（引导到内置配置加载）
        userConfigURL = saved ?? Self.defaultConfigURL
        loadBuiltin()
    }

    // MARK: 加载

    /// 从内置 bundle 加载 movie2.json
    @discardableResult
    func loadBuiltin() -> Bool {
        guard let url = Bundle.main.url(forResource: "movie2", withExtension: "json", subdirectory: "config"),
              let data = try? Data(contentsOf: url) else {
            lastError = "内置配置缺失：movie2.json"
            return false
        }
        do {
            let cfg = try AppConfig.parse(data)
            config = cfg
            lastLoadedFrom = .builtin
            lastError = nil
            return true
        } catch {
            lastError = "内置配置解析失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 从用户 URL 拉取配置（原样保留 JSON）
    @discardableResult
    func loadRemote(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else {
            lastError = "配置 URL 无效"
            return false
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            let (data, _) = try await URLSession.shared.data(for: request)
            let cfg = try AppConfig.parse(data)
            await MainActor.run {
                config = cfg
                userConfigURL = urlString
                lastLoadedFrom = .remote
                lastError = nil
            }
            return true
        } catch {
            await MainActor.run {
                lastError = "配置加载失败：\(error.localizedDescription)"
            }
            return false
        }
    }

    /// 用户粘贴的整段 JSON 文本
    @discardableResult
    func loadPasted(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else {
            lastError = "配置文本编码错误"
            return false
        }
        do {
            let cfg = try AppConfig.parse(data)
            config = cfg
            lastLoadedFrom = .paste
            lastError = nil
            return true
        } catch {
            lastError = "配置 JSON 解析失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: 历史 / 收藏（UserDefaults 持久化）

    struct HistoryItem: Codable, Identifiable, Hashable {
        var id: String { vod_id }
        var vod_id: String
        var vod_name: String
        var vod_pic: String
        var sourceKey: String
        var sourceName: String
        var episodeName: String = ""
        var timestamp: Date = Date()
    }

    @Published private(set) var history: [HistoryItem] = []
    @Published private(set) var favorites: [VOD] = []

    func loadPersisted() {
        history = loadArray(Keys.history) ?? []
        favorites = loadArray(Keys.favorites) ?? []
    }

    func addHistory(_ item: HistoryItem) {
        history.removeAll { $0.vod_id == item.vod_id && $0.sourceKey == item.sourceKey }
        history.insert(item, at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
        saveArray(Keys.history, history)
    }

    func removeHistory(_ item: HistoryItem) {
        history.removeAll { $0 == item }
        saveArray(Keys.history, history)
    }

    func clearHistory() {
        history.removeAll()
        saveArray(Keys.history, history)
    }

    func toggleFavorite(_ vod: VOD) {
        if favorites.contains(where: { $0.vod_id == vod.vod_id }) {
            favorites.removeAll { $0.vod_id == vod.vod_id }
        } else {
            favorites.insert(vod, at: 0)
        }
        saveArray(Keys.favorites, favorites)
    }

    func isFavorite(_ vod: VOD) -> Bool {
        favorites.contains { $0.vod_id == vod.vod_id }
    }

    private func loadArray<T: Codable>(_ key: String) -> [T]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([T].self, from: data)
    }

    private func saveArray<T: Codable>(_ key: String, _ value: [T]) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

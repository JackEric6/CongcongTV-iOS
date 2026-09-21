import Foundation

/// 全局配置模型：与 catvod 原配置 JSON 一一对应（原样使用，不改写）。
struct AppConfig: Codable {
    var spider: String = ""
    var wallpaper: String = ""
    var sites: [Site] = []
    var lives: [LiveChannel] = []
    var logo: String = ""
    var hosts: [String: String] = [:]

    static func parse(_ data: Data) throws -> AppConfig {
        let decoder = JSONDecoder()
        let cfg = try decoder.decode(AppConfig.self, from: data)
        return cfg
    }

    /// 可用于 iOS 引擎的站点（drpy2 JS 源，api 是 http(s)）
    var usableSites: [Site] {
        sites.filter { $0.isUsableOnIOS }
    }
}

import Foundation

/// 全局配置模型：与 catvod 原配置 JSON 一一对应（原样使用，不改写）。
struct AppConfig: Codable {
    var spider: String = ""
    var wallpaper: String = ""
    var sites: [Site] = []
    var lives: [LiveChannel] = []
    var logo: String = ""
    var hosts: [String: String] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case spider
        case wallpaper
        case sites
        case lives
        case logo
        case hosts
    }

    /// 上游配置可能只提供 sites；站点自身也可能省略带默认值的字段。
    /// 使用 decodeIfPresent 保留模型默认值，同时维持 key/name 为必填字段。
    private struct DecodedSite: Decodable {
        let key: String
        let name: String
        let type: Int
        let api: String
        let ext: String
        let searchable: Int
        let quickSearch: Int
        let changeable: Int

        private enum CodingKeys: String, CodingKey {
            case key
            case name
            case type
            case api
            case ext
            case searchable
            case quickSearch
            case changeable
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try container.decode(String.self, forKey: .key)
            name = try container.decode(String.self, forKey: .name)
            type = try container.decodeIfPresent(Int.self, forKey: .type) ?? 1
            api = try container.decodeIfPresent(String.self, forKey: .api) ?? ""
            ext = try container.decodeIfPresent(String.self, forKey: .ext) ?? ""
            searchable = try container.decodeIfPresent(Int.self, forKey: .searchable) ?? 0
            quickSearch = try container.decodeIfPresent(Int.self, forKey: .quickSearch) ?? 0
            changeable = try container.decodeIfPresent(Int.self, forKey: .changeable) ?? 0
        }

        var site: Site {
            Site(
                key: key,
                name: name,
                type: type,
                api: api,
                ext: ext,
                searchable: searchable,
                quickSearch: quickSearch,
                changeable: changeable
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spider = try container.decodeIfPresent(String.self, forKey: .spider) ?? ""
        wallpaper = try container.decodeIfPresent(String.self, forKey: .wallpaper) ?? ""
        let decodedSites = try container.decodeIfPresent([DecodedSite].self, forKey: .sites) ?? []
        sites = decodedSites.map(\.site)
        lives = try container.decodeIfPresent([LiveChannel].self, forKey: .lives) ?? []
        logo = try container.decodeIfPresent(String.self, forKey: .logo) ?? ""
        hosts = try container.decodeIfPresent([String: String].self, forKey: .hosts) ?? [:]
    }

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

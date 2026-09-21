import Foundation

/// 一条剧集/视频（同 TVBox / catvod 的 vod 结构，字段名与配置约定一致）
struct VOD: Codable, Identifiable, Hashable {
    var vod_id: String
    var vod_name: String
    var vod_pic: String = ""
    var vod_remarks: String = ""
    var vod_content: String = ""
    var vod_play_from: String = ""
    var vod_play_url: String = ""

    // 运行时来源标记（引擎返回的裸 VOD 不带这两个字段；
    // 可选类型保证合成 Codable 解码兼容——缺失时解码为 nil，也不进持久化重点字段）
    var sourceKey: String?
    var sourceName: String?

    var id: String { vod_id }
}

/// 分集（从 vod_play_url 中按规则拆出：剧名$m3u8地址#剧名$m3u8地址……）
struct Episode: Identifiable, Hashable {
    let name: String
    let url: String
    var id: String { "\(name)|\(url)" }
}

/// 直播台（来自配置的 lives 段）
struct LiveChannel: Codable, Identifiable, Hashable {
    var name: String
    var url: String
    var id: String { "\(name)|\(url)" }

    // 可选字段（playerType=2 的直播源；部分需要自定义 UA）
    var playerType: Int? = nil
    var ua: String? = nil
}

/// 站点（来自配置 sites 段）
struct Site: Codable, Identifiable, Hashable {
    var key: String
    var name: String
    var type: Int = 1
    var api: String = ""
    var ext: String = ""
    var searchable: Int = 0
    var quickSearch: Int = 0
    var changeable: Int = 0

    var id: String { key }

    /// 播放时是否可嵌套进 AVPlayer：这里是 true 的站点走 drpy2 JS 引擎；
    /// csp_* 的 jar 站点（Android 专用爬虫）在 iOS 上不可用。
    var isUsableOnIOS: Bool {
        api.hasPrefix("http://") || api.hasPrefix("https://")
    }
}

/// 分类（home/ category 返回的 class 列表）
struct Category: Codable, Identifiable, Hashable {
    var type_id: String
    var type_name: String
    var id: String { type_id }
}

/// play() 返回值
struct PlayResult: Codable, Hashable {
    var parse: Int = 1
    var url: String = ""
    var flag: String = ""
    var jx: Int = 0
    var header: [String: String]? = nil
}

import Foundation

struct TVBoxSite: Identifiable, Hashable, Codable {
    let key: String
    let name: String
    let api: String
    let type: Int
    let searchable: Bool
    let filterable: Bool
    let ext: String
    let jar: String
    let playerURL: String
    let icon: String
    let categories: [String]

    var id: String { key }
}

struct TVBoxCategory: Identifiable, Hashable {
    let id: String
    let name: String
}

struct VideoItem: Identifiable, Hashable {
    let id: String
    let name: String
    let poster: String
    let remark: String
    let sourceKey: String
}

struct Episode: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    let flag: String
}

struct VideoDetail: Identifiable {
    let id: String
    let name: String
    let poster: String
    let remark: String
    let description: String
    let episodes: [Episode]
    let sourceKey: String
}

struct HomePage {
    let categories: [TVBoxCategory]
    let videos: [VideoItem]
}

struct PlayResult {
    let url: URL
    let headers: [String: String]
}

enum TVBoxError: LocalizedError {
    case invalidURL
    case invalidResponse
    case emptyConfig
    case unsupportedSite(String)
    case malformedPayload(String)
    case script(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "配置地址无效"
        case .invalidResponse: return "网络响应无效"
        case .emptyConfig: return "配置中没有可用影视站点"
        case .unsupportedSite(let name): return "暂不支持站点：\(name)"
        case .malformedPayload(let message): return message
        case .script(let message): return "动态脚本执行失败：\(message)"
        }
    }
}

enum TVBoxConfigParser {
    static func decode(_ data: Data) throws -> [TVBoxSite] {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return sites(from: object)
    }

    static func sites(from object: Any) -> [TVBoxSite] {
        guard let root = object as? [String: Any] else { return [] }
        let container = (root["data"] as? [String: Any]) ?? root
        let rawSites = (container["sites"] as? [[String: Any]]) ?? []
        let defaultJar = string(root["spider"] ?? container["spider"]) ?? ""
        return rawSites.compactMap { item in
            guard let key = string(item["key"] ?? item["id"]),
                  let api = string(item["api"]), !key.isEmpty, !api.isEmpty else {
                return nil
            }
            let name = string(item["name"]) ?? key
            return TVBoxSite(
                key: key,
                name: name,
                api: api,
                type: integer(item["type"]) ?? 1,
                searchable: (integer(item["searchable"]) ?? 1) != 0,
                filterable: (integer(item["filterable"]) ?? 1) != 0,
                ext: jsonString(item["ext"]) ?? "",
                jar: string(item["jar"]) ?? defaultJar,
                playerURL: string(item["playUrl"] ?? item["play_url"]) ?? "",
                icon: string(item["icon"]) ?? "",
                categories: (item["categories"] as? [String]) ?? []
            )
        }
    }

    static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    static func jsonString(_ value: Any?) -> String? {
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: []) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}

enum TVBoxResponseParser {
    static func home(data: Data, siteKey: String, baseURL: URL?) -> HomePage {
        if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return homeJSON(object, siteKey: siteKey, baseURL: baseURL)
        }
        return HomePage(categories: [], videos: XMLVideoParser.parse(data, siteKey: siteKey, baseURL: baseURL))
    }

    static func detail(data: Data, siteKey: String, baseURL: URL?) -> VideoDetail? {
        if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return detailJSON(object, siteKey: siteKey, baseURL: baseURL)
        }
        let videos = XMLVideoParser.parse(data, siteKey: siteKey, baseURL: baseURL)
        guard let first = videos.first else { return nil }
        return VideoDetail(id: first.id, name: first.name, poster: first.poster, remark: first.remark,
                           description: "", episodes: [Episode(id: first.id, name: "播放", url: first.id, flag: "")],
                           sourceKey: siteKey)
    }

    static func search(data: Data, siteKey: String, baseURL: URL?) -> [VideoItem] {
        if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return listJSON(object, siteKey: siteKey, baseURL: baseURL)
        }
        return XMLVideoParser.parse(data, siteKey: siteKey, baseURL: baseURL)
    }

    private static func homeJSON(_ object: Any, siteKey: String, baseURL: URL?) -> HomePage {
        let root = unwrap(object)
        let categories = categoryValues(root).enumerated().compactMap { index, value -> TVBoxCategory? in
            guard let dict = value as? [String: Any] else { return nil }
            let id = TVBoxConfigParser.string(dict["type_id"] ?? dict["id"] ?? dict["typeId"]) ?? "\(index + 1)"
            let name = TVBoxConfigParser.string(dict["type_name"] ?? dict["name"] ?? dict["title"]) ?? id
            return TVBoxCategory(id: id, name: name)
        }
        return HomePage(categories: categories, videos: listJSON(root, siteKey: siteKey, baseURL: baseURL))
    }

    private static func detailJSON(_ object: Any, siteKey: String, baseURL: URL?) -> VideoDetail? {
        let root = unwrap(object)
        guard let dict = firstDictionary(in: root) else { return nil }
        let id = TVBoxConfigParser.string(dict["vod_id"] ?? dict["id"] ?? dict["url"]) ?? UUID().uuidString
        let name = TVBoxConfigParser.string(dict["vod_name"] ?? dict["name"] ?? dict["title"]) ?? "未命名"
        let poster = absolute(TVBoxConfigParser.string(dict["vod_pic"] ?? dict["pic"] ?? dict["poster"]) ?? "", baseURL: baseURL)
        let remark = TVBoxConfigParser.string(dict["vod_remarks"] ?? dict["remarks"] ?? dict["remark"]) ?? ""
        let description = TVBoxConfigParser.string(dict["vod_content"] ?? dict["vod_blurb"] ?? dict["content"] ?? dict["desc"]) ?? ""
        let sources = TVBoxConfigParser.string(dict["vod_play_from"] ?? dict["play_from"] ?? dict["from"]) ?? ""
        let urls = TVBoxConfigParser.string(dict["vod_play_url"] ?? dict["play_url"] ?? dict["url"]) ?? ""
        let flags = sources.split(separator: "$$$").map(String.init)
        let groups = urls.split(separator: "$$$").map(String.init)
        var episodes: [Episode] = []
        for (groupIndex, group) in groups.enumerated() {
            let flag = groupIndex < flags.count ? flags[groupIndex] : "线路\(groupIndex + 1)"
            for pair in group.split(separator: "#").map(String.init) {
                let parts = pair.split(separator: "$").map(String.init)
                let title = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "播放"
                let url = parts.dropFirst().first ?? parts.first ?? ""
                if !url.isEmpty { episodes.append(Episode(id: "\(groupIndex)-\(title)-\(url)", name: "\(flag) · \(title)", url: absolute(url, baseURL: baseURL), flag: flag)) }
            }
        }
        return VideoDetail(id: id, name: name, poster: poster, remark: remark, description: description, episodes: episodes, sourceKey: siteKey)
    }

    private static func listJSON(_ object: Any, siteKey: String, baseURL: URL?) -> [VideoItem] {
        let root = unwrap(object)
        let values: [Any]
        if let array = root as? [[String: Any]] { values = array }
        else if let dict = root as? [String: Any] {
            values = (dict["list"] as? [Any]) ?? (dict["vod"] as? [Any]) ?? (dict["data"] as? [Any]) ?? (dict["result"] as? [Any]) ?? []
        } else { values = [] }
        return values.enumerated().compactMap { index, value in
            guard let dict = value as? [String: Any] else { return nil }
            let id = TVBoxConfigParser.string(dict["vod_id"] ?? dict["id"] ?? dict["url"]) ?? "item-\(index)"
            let name = TVBoxConfigParser.string(dict["vod_name"] ?? dict["name"] ?? dict["title"]) ?? "未命名"
            let poster = absolute(TVBoxConfigParser.string(dict["vod_pic"] ?? dict["pic"] ?? dict["poster"]) ?? "", baseURL: baseURL)
            let remark = TVBoxConfigParser.string(dict["vod_remarks"] ?? dict["remarks"] ?? dict["remark"]) ?? ""
            return VideoItem(id: id, name: name, poster: poster, remark: remark, sourceKey: siteKey)
        }
    }

    private static func unwrap(_ object: Any) -> Any {
        guard let dict = object as? [String: Any] else { return object }
        if let data = dict["data"], data is [String: Any] || data is [[String: Any]] { return data }
        if let result = dict["result"], result is [String: Any] || result is [[String: Any]] { return result }
        return object
    }

    private static func firstDictionary(in object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] {
            if let list = dict["list"] as? [[String: Any]], let first = list.first { return first }
            if let vod = dict["vod"] as? [[String: Any]], let first = vod.first { return first }
            if dict["vod_id"] != nil || dict["id"] != nil || dict["vod_name"] != nil { return dict }
            if let data = dict["data"] { return firstDictionary(in: data) }
            if let result = dict["result"] { return firstDictionary(in: result) }
        }
        if let array = object as? [[String: Any]] { return array.first }
        return nil
    }

    private static func categoryValues(_ object: Any) -> [Any] {
        guard let dict = object as? [String: Any] else { return [] }
        return (dict["class"] as? [Any]) ?? (dict["categories"] as? [Any]) ?? (dict["type"] as? [Any]) ?? []
    }

    private static func absolute(_ value: String, baseURL: URL?) -> String {
        guard !value.isEmpty else { return "" }
        if URL(string: value)?.scheme != nil { return value }
        return baseURL.flatMap { URL(string: value, relativeTo: $0)?.absoluteURL.absoluteString } ?? value
    }
}

private final class XMLVideoParser: NSObject, XMLParserDelegate {
    private var items: [VideoItem] = []
    private var current: [String: String] = [:]
    private var currentKey = ""
    private var siteKey = ""
    private var baseURL: URL?

    static func parse(_ data: Data, siteKey: String, baseURL: URL?) -> [VideoItem] {
        let parser = XMLVideoParser()
        parser.siteKey = siteKey
        parser.baseURL = baseURL
        let xml = XMLParser(data: data)
        xml.delegate = parser
        _ = xml.parse()
        return parser.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName.lowercased() == "video" || elementName.lowercased() == "vod" { current = [:] }
        currentKey = elementName.lowercased()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        current[currentKey, default: ""] += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName.lowercased() == "video" || elementName.lowercased() == "vod" else { return }
        let id = current["id"] ?? current["vod_id"] ?? UUID().uuidString
        let name = current["name"] ?? current["vod_name"] ?? "未命名"
        let poster = current["pic"] ?? current["vod_pic"] ?? ""
        let remark = current["remarks"] ?? current["vod_remarks"] ?? ""
        let resolved = URL(string: poster, relativeTo: baseURL)?.absoluteURL.absoluteString ?? poster
        items.append(VideoItem(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), poster: resolved, remark: remark.trimmingCharacters(in: .whitespacesAndNewlines), sourceKey: siteKey))
        current = [:]
    }
}

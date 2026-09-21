import Foundation

/// 解析 / 业务模型扩展：把引擎返回的 JSON 字符串/字典转成强类型。
enum Mapper {
    /// 引擎入口统一返回 JSON 字符串（如 `{"list":[...]}`），也可能直接是字典。
    /// 这里统一归一化成 [String: Any]。
    static func object(from json: Any?) -> [String: Any]? {
        if let d = json as? [String: Any] { return d }
        if let s = json as? String {
            guard let data = s.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        return nil
    }

    /// 解析 VOD 列表（homeVod / category / search 返回 { list: [...] }）
    static func vodList(from json: Any?) -> [VOD] {
        guard let j = object(from: json),
              let list = j["list"] as? [[String: Any]] else { return [] }
        return list.compactMap { try? VOD(dict: $0) }
    }

    /// 解析分类列表（home / category 返回 { class: [...] }，本实现也兼容 { list: [...] }）
    static func categoryList(from json: Any?) -> [Category] {
        guard let j = object(from: json) else { return [] }
        if let cl = j["class"] as? [[String: Any]] {
            return cl.compactMap { c in
                guard let id = c["type_id"] as? String, let name = c["type_name"] as? String else { return nil }
                return Category(type_id: id, type_name: name)
            }
        }
        if let list = j["list"] as? [[String: Any]] {
            return list.compactMap { c in
                guard let id = String(any: c["type_id"]), let name = c["type_name"] as? String else { return nil }
                return Category(type_id: id, type_name: name)
            }
        }
        return []
    }

    /// 解析播放结果
    static func playResult(from json: Any?) -> PlayResult? {
        guard let j = object(from: json) else { return nil }
        var r = PlayResult()
        r.parse = Int(any: j["parse"]) ?? 1
        r.url = String(any: j["url"]) ?? ""
        r.flag = String(any: j["flag"]) ?? ""
        r.jx = Int(any: j["jx"]) ?? 0
        if let h = j["header"] as? [String: String] { r.header = h }
        return r
    }

    /// 详情接口返回 { list: [vod] }，取第一条
    static func vodDetail(from json: Any?) -> VOD? {
        guard let j = object(from: json),
              let list = j["list"] as? [[String: Any]],
              let first = list.first else { return nil }
        return try? VOD(dict: first)
    }

    /// 把 vod_play_url 拆成分集（# 分隔，$ 分隔 名称+地址）
    static func episodes(from playUrl: String) -> [Episode] {
        var out: [Episode] = []
        for part in playUrl.split(separator: "#") {
            let seg = String(part)
            let pieces = seg.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
            if pieces.count == 2 {
                let name = String(pieces[0]).trimmingCharacters(in: .whitespaces)
                let url = String(pieces[1]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, !url.isEmpty {
                    out.append(Episode(name: name, url: url))
                }
            }
        }
        return out
    }

    /// 把 lives 段转成直播台列表
    static func lives(from arr: Any?) -> [LiveChannel] {
        guard let arr = arr as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let name = d["name"] as? String, let url = String(any: d["url"]), !name.isEmpty else { return nil }
            return LiveChannel(name: name, url: url)
        }
    }
}

extension VOD {
    init(dict: [String: Any]) throws {
        let formatter = try JSONSerialization.data(withJSONObject: dict, options: [])
        self = try JSONDecoder().decode(VOD.self, from: formatter)
    }
}

extension Int {
    init?(any v: Any?) {
        switch v {
        case let i as Int: self = i
        case let d as Double: self = Int(d)
        case let f as Float: self = Int(f)
        case let b as Bool: self = b ? 1 : 0
        case let s as String: self.init(s)
        default: return nil
        }
    }
}

extension Double {
    init?(any v: Any?) {
        switch v {
        case let d as Double: self = d
        case let f as Float: self = Double(f)
        case let i as Int: self = Double(i)
        case let b as Bool: self = b ? 1 : 0
        case let s as String: self.init(s)
        default: return nil
        }
    }
}

extension String {
    init?(any v: Any?) {
        switch v {
        case let s as String: self = s
        case let i as Int: self = String(i)
        case let d as Double: self = String(d)
        case let b as Bool: self = String(b)
        default: return nil
        }
    }
}

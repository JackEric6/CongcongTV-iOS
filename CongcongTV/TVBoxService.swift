import Foundation

final class TVBoxService {
    private let spider = JavaScriptSpiderRunner()

    func home(site: TVBoxSite) async throws -> HomePage {
        switch site.type {
        case 3:
            guard site.api.hasPrefix("http://") || site.api.hasPrefix("https://") else {
                throw TVBoxError.unsupportedSite("\(site.name)（Android spider2.jar）")
            }
            let text = try await spider.call(site: site, method: "home", arguments: [])
            let page = parseHome(text, site: site)
            if !page.videos.isEmpty { return page }
            let homeVod = try? await spider.call(site: site, method: "homeVod", arguments: [])
            let videos = homeVod.map { TVBoxResponseParser.search(data: Data($0.utf8), siteKey: site.key, baseURL: URL(string: site.api)) } ?? []
            return HomePage(categories: page.categories, videos: videos)
        default:
            let data = try await request(site: site, parameters: [:])
            return TVBoxResponseParser.home(data: data, siteKey: site.key, baseURL: URL(string: site.api))
        }
    }

    func category(site: TVBoxSite, categoryID: String, page: Int = 1) async throws -> [VideoItem] {
        switch site.type {
        case 3:
            guard site.api.hasPrefix("http://") || site.api.hasPrefix("https://") else {
                throw TVBoxError.unsupportedSite("\(site.name)（Android spider2.jar）")
            }
            let text = try await spider.call(site: site, method: "category", arguments: [categoryID, String(page), false, [:]])
            return TVBoxResponseParser.search(data: Data(text.utf8), siteKey: site.key, baseURL: URL(string: site.api))
        default:
            let data = try await request(site: site, parameters: ["ac": "list", "t": categoryID, "pg": String(page), "class": categoryID])
            return TVBoxResponseParser.search(data: data, siteKey: site.key, baseURL: URL(string: site.api))
        }
    }

    func search(site: TVBoxSite, query: String) async throws -> [VideoItem] {
        switch site.type {
        case 3:
            guard site.api.hasPrefix("http://") || site.api.hasPrefix("https://") else {
                throw TVBoxError.unsupportedSite("\(site.name)（Android spider2.jar）")
            }
            let text = try await spider.call(site: site, method: "search", arguments: [query, false])
            return TVBoxResponseParser.search(data: Data(text.utf8), siteKey: site.key, baseURL: URL(string: site.api))
        default:
            let data = try await request(site: site, parameters: ["wd": query, "pg": "1", "ac": "list"])
            return TVBoxResponseParser.search(data: data, siteKey: site.key, baseURL: URL(string: site.api))
        }
    }

    func detail(site: TVBoxSite, item: VideoItem) async throws -> VideoDetail {
        switch site.type {
        case 3:
            guard site.api.hasPrefix("http://") || site.api.hasPrefix("https://") else {
                throw TVBoxError.unsupportedSite("\(site.name)（Android spider2.jar）")
            }
            let text = try await spider.call(site: site, method: "detail", arguments: [item.id])
            guard let detail = TVBoxResponseParser.detail(data: Data(text.utf8), siteKey: site.key, baseURL: URL(string: site.api)) else {
                throw TVBoxError.malformedPayload("动态脚本没有返回详情数据")
            }
            return detail
        default:
            let data = try await request(site: site, parameters: ["ac": "detail", "ids": item.id])
            guard let detail = TVBoxResponseParser.detail(data: data, siteKey: site.key, baseURL: URL(string: site.api)) else {
                throw TVBoxError.malformedPayload("站点没有返回详情数据")
            }
            return detail
        }
    }

    func play(site: TVBoxSite, episode: Episode) async throws -> PlayResult {
        if let url = URL(string: episode.url), url.scheme != nil {
            return PlayResult(url: url, headers: [:])
        }
        if site.type == 3 {
            let text = try await spider.call(site: site, method: "play", arguments: [episode.flag, episode.url, []])
            if let result = Self.parsePlay(text) { return result }
        }
        if !site.playerURL.isEmpty, let url = URL(string: site.playerURL + episode.url) {
            return PlayResult(url: url, headers: [:])
        }
        throw TVBoxError.malformedPayload("此选集没有可播放地址")
    }

    private func parseHome(_ text: String, site: TVBoxSite) -> HomePage {
        TVBoxResponseParser.home(data: Data(text.utf8), siteKey: site.key, baseURL: URL(string: site.api))
    }

    private func request(site: TVBoxSite, parameters: [String: String]) async throws -> Data {
        let address = Self.url(site.api, parameters: parameters)
        let (data, response) = try await HTTPClient.get(address)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw TVBoxError.malformedPayload("站点返回 HTTP \(http.statusCode)")
        }
        return data
    }

    static func parsePlay(_ text: String) -> PlayResult? {
        if let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let root = (object["data"] as? [String: Any]) ?? object
            let address = TVBoxConfigParser.string(root["url"] ?? root["playUrl"] ?? root["play_url"])
            if let address, let url = URL(string: address) {
                let headers = (root["header"] as? [String: String]) ?? (root["headers"] as? [String: String]) ?? [:]
                return PlayResult(url: url, headers: headers)
            }
        }
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil {
            return PlayResult(url: url, headers: [:])
        }
        return nil
    }

    static func url(_ address: String, parameters: [String: String]) -> String {
        guard var components = URLComponents(string: address) else { return address }
        var query = components.queryItems ?? []
        let existing = Set(query.map(\.name))
        for (key, value) in parameters where !existing.contains(key) {
            query.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = query
        return components.url?.absoluteString ?? address
    }
}

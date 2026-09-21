import Foundation

struct HTTPClient {
    static func get(_ address: String, headers: [String: String] = [:]) async throws -> (Data, URLResponse) {
        let requested = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: requested) else {
            throw TVBoxError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.httpMethod = "GET"
        request.setValue("丛丛影视/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            guard let fallback = fallbackAddress(requested), fallback != requested,
                  let fallbackURL = URL(string: fallback) else {
                throw error
            }
            request.url = fallbackURL
            return try await URLSession.shared.data(for: request)
        }
    }

    static func text(_ address: String, headers: [String: String] = [:]) async throws -> String {
        let (data, _) = try await get(address, headers: headers)
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    static func syncText(_ address: String, headers: [String: String] = [:]) -> String {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else { return "" }
        let semaphore = DispatchSemaphore(value: 0)
        var result = ""
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.httpMethod = "GET"
        request.setValue("丛丛影视/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data { result = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self) }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 20)
        return result
    }

    private static func fallbackAddress(_ address: String) -> String? {
        guard let url = URL(string: address),
              let host = url.host?.lowercased(),
              ["ghproxy.net", "git.yylx.win"].contains(host) else {
            return nil
        }
        let prefix = "https://"
        guard let start = address.range(of: prefix, range: address.index(address.startIndex, offsetBy: prefix.count)..<address.endIndex) else {
            return nil
        }
        return String(address[start.lowerBound...])
    }
}

struct ConfigLoadResult {
    let sites: [TVBoxSite]
    let address: String
    let fromCache: Bool
}

final class ConfigStore {
    static let defaultAddress = "https://ghproxy.net/https://raw.githubusercontent.com/JackEric6/movie/refs/heads/main/movie2"

    private let defaults = UserDefaults.standard
    private let addressKey = "congcong.config.address"
    private let cacheName = "tvbox-config.json"

    var savedAddress: String {
        get { defaults.string(forKey: addressKey) ?? Self.defaultAddress }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: addressKey) }
    }

    func load(address: String? = nil) async throws -> ConfigLoadResult {
        let requested = (address ?? savedAddress).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requested.isEmpty else { throw TVBoxError.invalidURL }
        savedAddress = requested

        do {
            let data = try await loadData(from: requested, depth: 0)
            let sites = try TVBoxConfigParser.decode(data)
            guard !sites.isEmpty else { throw TVBoxError.emptyConfig }
            try? data.write(to: cacheURL(), options: [.atomic])
            return ConfigLoadResult(sites: sites, address: requested, fromCache: false)
        } catch {
            if let data = try? Data(contentsOf: cacheURL()), let sites = try? TVBoxConfigParser.decode(data), !sites.isEmpty {
                return ConfigLoadResult(sites: sites, address: requested, fromCache: true)
            }
            throw error
        }
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL())
    }

    private func loadData(from address: String, depth: Int) async throws -> Data {
        guard depth < 3 else { throw TVBoxError.malformedPayload("配置仓库嵌套层级过深") }
        let cleanAddress = address.components(separatedBy: ";pk;").first ?? address
        let (data, response) = try await HTTPClient.get(cleanAddress)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw TVBoxError.malformedPayload("配置地址返回 HTTP \(http.statusCode)")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let root = object as? [String: Any],
              let urls = root["urls"] as? [[String: Any]],
              root["sites"] == nil else {
            return data
        }
        for item in urls {
            if let next = TVBoxConfigParser.string(item["url"] ?? item["api"]) {
                do { return try await loadData(from: next, depth: depth + 1) } catch { continue }
            }
        }
        throw TVBoxError.emptyConfig
    }

    private func cacheURL() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(cacheName)
    }
}

import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var sites: [TVBoxSite] = []
    @Published var selectedSiteID = ""
    @Published var categories: [TVBoxCategory] = []
    @Published var videos: [VideoItem] = []
    @Published var configURL: String
    @Published var isLoading = false
    @Published var message = "正在加载配置…"
    @Published var lastError = ""
    @Published var isShowingSettings = false

    let service = TVBoxService()
    private let configStore = ConfigStore()

    init() {
        configURL = configStore.savedAddress
        Task { [weak self] in
            await self?.loadConfig()
        }
    }

    var selectedSite: TVBoxSite? {
        sites.first(where: { $0.id == selectedSiteID }) ?? sites.first
    }

    func loadConfig(address: String? = nil) async {
        isLoading = true
        lastError = ""
        message = "正在读取配置…"
        do {
            let result = try await configStore.load(address: address ?? configURL)
            configURL = result.address
            sites = result.sites
            if !sites.contains(where: { $0.id == selectedSiteID }) { selectedSiteID = sites.first?.id ?? "" }
            message = result.fromCache ? "网络不可用，已使用上次缓存配置" : "配置已更新"
            await loadHome()
        } catch {
            isLoading = false
            lastError = error.localizedDescription
            message = "配置加载失败"
        }
    }

    func selectSite(_ site: TVBoxSite) {
        selectedSiteID = site.id
        Task { await loadHome() }
    }

    func loadHome() async {
        guard let site = selectedSite else {
            isLoading = false
            message = "配置中没有可用影视站点"
            return
        }
        isLoading = true
        lastError = ""
        do {
            let page = try await service.home(site: site)
            categories = page.categories
            videos = page.videos
            message = "\(site.name) · \(videos.count) 个内容"
        } catch {
            lastError = error.localizedDescription
            message = "首页加载失败"
        }
        isLoading = false
    }

    func loadCategory(_ category: TVBoxCategory) async {
        guard let site = selectedSite else { return }
        isLoading = true
        do {
            videos = try await service.category(site: site, categoryID: category.id)
            message = "\(category.name) · \(videos.count) 个内容"
        } catch {
            lastError = error.localizedDescription
            message = "分类加载失败"
        }
        isLoading = false
    }

    func search(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let site = selectedSite else {
            await loadHome()
            return
        }
        isLoading = true
        do {
            videos = try await service.search(site: site, query: query)
            message = "搜索“\(query)” · \(videos.count) 个结果"
        } catch {
            lastError = error.localizedDescription
            message = "搜索失败"
        }
        isLoading = false
    }

    func clearCache() {
        configStore.clearCache()
        message = "缓存已清除"
    }
}

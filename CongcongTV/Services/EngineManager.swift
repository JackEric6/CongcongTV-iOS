import Foundation
import Combine

/// 站点引擎调度层：把 movie2 配置里的站点按 iOS 可用性分组，
/// 在启动时预初始化 3 个 drpy2 JS 规则源，并向 SwiftUI 暴露异步接口。
///
/// 站点分类（依据 movie2 原配置）：
///  - 可用（api 为 http(s)，drpy2 JS 源）：虎牙js / 斗鱼js / dr_兔小贝，规则离线打包在 bundle 内。
///  - 不可用（api 为 csp_*Guard 的 jar 爬虫，Android TVBox 专用）：仅展示并提示「仅 Android 源」。
///
/// drpy2 引擎一次只激活一个 rule，因此所有引擎调用都要带上来源站点，
/// JSEnv 会先把该站点的规则 init 进引擎再执行（见 JSEnv.asyncHomeVod(for:) 等）。
final class EngineManager: ObservableObject {
    static let shared = EngineManager()

    /// 已预初始化的可用站点（key → 站点信息）
    @Published private(set) var prepared: [String: Site] = [:]
    @Published private(set) var preparing = false
    @Published private(set) var errorMessage: String?

    private let js = JSEnv.shared
    private let store = ConfigStore.shared

    private init() {}

    /// 启动时调用：绑定配置变化并预初始化可用站点。
    func bootstrap() {
        // 配置变化（用户换了配置 URL）时重新准备引擎
        store.$config
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.prepare() }
            .store(in: &cancellables)
        prepare()
    }

    private var cancellables = Set<AnyCancellable>()

    /// 后台线程加载 bundle 并缓存三个规则（~1MB JS 解析较慢，不放主线程）。
    /// 规则只在引擎首次需要时 init（activateSite 惰性执行），这里只缓存文本。
    func prepare() {
        let usable = store.config.usableSites
        guard !usable.isEmpty else {
            prepared = [:]
            return
        }
        preparing = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.js.warmUp()
            let texts = self.js.bundledRuleTexts()
            self.js.cacheRuleTexts(texts)
            let ready = usable.reduce(into: [String: Site]()) { acc, s in
                if texts[self.js.ruleName(for: s)] != nil { acc[s.key] = s }
            }
            let missing = usable.filter { texts[self.js.ruleName(for: $0)] == nil }
            DispatchQueue.main.async {
                self.prepared = ready
                self.errorMessage = missing.isEmpty ? nil : "缺少规则文件：\(missing.map(\.name).joined(separator: "、"))"
                self.preparing = false
            }
        }
    }

    var usableSites: [Site] {
        store.config.usableSites
    }

    // MARK: 站点能力（async 封装；引擎调用在 JSEnv execQueue 上串行）

    /// 各站点首页推荐片单。所有可用的 JS 源都会跑一遍，合并结果并附 sourceKey/sourceName。
    func loadHomeVods() async -> [VOD] {
        let sites = usableSites
        let names = sites.reduce(into: [String: String]()) { $0[$1.key] = $1.name }
        let items = await withTaskGroup(of: (String, [VOD]).self) { group in
            for s in sites {
                group.addTask { [js] in
                    let v = await js.asyncHomeVod(for: s)
                    return (s.key, v)
                }
            }
            var collected: [String: [VOD]] = [:]
            for await (key, vods) in group { collected[key] = vods }
            return collected
        }
        return merged(items, names: names)
    }

    /// 某站点的首页分类列表（进入站点首页时调用）。
    func loadCategories(for site: Site) async -> [Category] {
        await js.asyncHomeCategories(for: site)
    }

    /// 分类片单
    func loadCategory(for site: Site, tid: String, pg: Int = 1) async -> [VOD] {
        let vods = await js.asyncCategory(for: site, tid: tid, pg: pg)
        return annotate(vods, site: site)
    }

    /// 搜索：跑所有可用站点，合并结果。
    func searchSites(_ wd: String, pg: Int = 1) async -> [VOD] {
        let sites = usableSites
        let names = sites.reduce(into: [String: String]()) { $0[$1.key] = $1.name }
        let items = await withTaskGroup(of: (String, [VOD]).self) { group in
            for s in sites {
                group.addTask { [js] in
                    let v = await js.asyncSearch(for: s, wd: wd, pg: pg)
                    return (s.key, v)
                }
            }
            var collected: [String: [VOD]] = [:]
            for await (key, vods) in group { collected[key] = vods }
            return collected
        }
        return merged(items, names: names)
    }

    /// 详情（返回完整 VOD，含分集列表）
    func loadDetail(for site: Site, vodId: String) async -> VOD? {
        await js.asyncDetail(for: site, vodId: vodId)
    }

    /// 取播放地址
    func loadPlay(for site: Site, flag: String, url: String) async -> PlayResult {
        await js.asyncPlay(for: site, flag: flag, url: url)
    }

    // MARK: 结果合并

    private func merged(_ items: [String: [VOD]], names: [String: String]) -> [VOD] {
        items.keys.sorted().flatMap { key in
            annotate(items[key] ?? [], siteKey: key, siteName: names[key] ?? key)
        }
    }

    private func annotate(_ vods: [VOD], site: Site) -> [VOD] {
        annotate(vods, siteKey: site.key, siteName: site.name)
    }

    private func annotate(_ vods: [VOD], siteKey: String, siteName: String) -> [VOD] {
        vods.map { v -> VOD in
            var vv = v
            vv.sourceKey = siteKey
            vv.sourceName = siteName
            return vv
        }
    }
}

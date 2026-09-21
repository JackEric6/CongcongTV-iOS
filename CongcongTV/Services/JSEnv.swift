import Foundation
import JavaScriptCore

/// drpy2 引擎桥：加载 JSEnv.bundle.js 到单个 JSContext，注入 iOS 侧宿主钩子，
/// 对外提供 homeVod / category / detail / play / search 等调用。
///
/// 契约（与 bundle 尾部 driver 确认一致）：
///  - 引擎所有网络请求最终都走 `globalThis.__drpyFetch(url, obj)`，
///    返回 `{ content: string, headers: object }`（同步）。
///  - 日志经 `globalThis.__drpyLog(lines)` 回流（可忽略）。
///  - 本地存储经 `globalThis.__drpyLocal.set/get/delete`（内存即可）。
///  - 导出 `globalThis.CongcongTV = {init, home, homeVod, category, detail, play, search, ...}`。
///  - 规则 JS 用 `CongcongTV.init(ruleJS)` 传入引擎并 eval 执行。
///
/// 重要：drpy2 引擎同一时刻只激活一个 `rule`（每次 init 都替换全局 rule 对象），
/// 因此引擎入口调用前必须先 `activateSite(_:)` 切到对应站点的规则。
/// 所有引擎指令在 `execQueue` 串行执行，保证“激活规则 + 调用”不被打断。
final class JSEnv {
    static let shared = JSEnv()

    /// 已打包进 bundle 的规则文件（文件名 → 站点解析用）。与 movie2 配置的可用站点对应：
    /// 虎牙.js / 斗鱼直播.js / 兔小贝.js。规则随包分发，离线可用，不必再走网络下载 ext。
    /// 名称全是中文，用后一半（含 .js 扩展名）做模糊匹配可绕过控制台 GBK 编码差异——
    /// 实际取文件名后缀时见 ruleName(for:)：先做百分号解码，再取 lastPathComponent。
    static let bundledRuleNames = ["虎牙.js", "斗鱼直播.js", "兔小贝.js"]

    private(set) var context: JSContext?
    private let initQueue = DispatchQueue(label: "com.congcongtv.jscontext", qos: .userInitiated)
    private let execQueue = DispatchQueue(label: "com.congcongtv.exec", qos: .userInitiated)

    /// 规则文件名 → 规则 JS 文本（prepare 时由 EngineManager 填充）
    private var cachedRuleTexts: [String: String] = [:]
    /// 当前激活的规则文件名
    private var activeRuleName: String?

    private init() {}

    /// JSContext 惰性初始化（线程安全，只建一次）。
    private func ensureContext() -> JSContext? {
        if let c = context { return c }
        return initQueue.sync {
            if let c = context { return c }
            guard let url = Bundle.main.url(forResource: "JSEnv.bundle", withExtension: "js", subdirectory: "js"),
                  let bundle = try? String(contentsOf: url, encoding: .utf8) else {
                NSLog("[JSEnv] JSEnv.bundle.js 缺失")
                return nil
            }
            let ctx = JSContext()!
            injectHosts(into: ctx)
            ctx.exceptionHandler = { _, exc in
                if let e = exc { NSLog("[JSEnv] JS exception: %@", e.toString()) }
            }
            ctx.evaluateScript(bundle)
            context = ctx
            return ctx
        }
    }

    /// 触发懒初始化，让 bundle 加载的开销（~1MB 解析）发生在后台 prepare 而非首次点击。
    func warmUp() {
        _ = ensureContext()
    }

    // MARK: 宿主钩子注入

    private func injectHosts(into ctx: JSContext) {
        // __drpyFetch：同步 URLSession。obj 可带 method/body/headers/timeout/withHeaders。
        let fetch: @convention(block) (String, [String: Any]) -> [String: Any] = { urlString, obj in
            JSEnv.shared.syncFetch(urlString: urlString, obj: obj)
        }
        ctx.setObject(fetch, forKeyedSubscript: "__drpyFetch" as NSString)

        // __drpyLog：只把明显错误/警告级别的日志打到系统日志，避免刷屏
        let log: @convention(block) ([String]) -> Void = { lines in
            let interesting = lines.filter { $0.range(of: "rror") != nil || $0.range(of: "arn") != nil }
            for l in interesting.prefix(5) {
                NSLog("[JSEnv/JS] %@", l)
            }
        }
        ctx.setObject(log, forKeyedSubscript: "__drpyLog" as NSString)

        // __drpyLocal：内存字典（JS 会话内持久，无需跨启动保存）
        let local = LocalHost()
        ctx.setObject(local, forKeyedSubscript: "__drpyLocal" as NSString)
    }

    /// 线程安全的同步网络请求（JS 引擎调用是同步的，用信号量等待 URLSession 完成）。
    func syncFetch(urlString: String, obj: [String: Any]) -> [String: Any] {
        var out: [String: Any] = ["content": "", "headers": [:]]
        guard let url = URL(string: urlString) else { return out }

        var request = URLRequest(url: url)
        request.httpMethod = (obj["method"] as? String) ?? "GET"
        if let timeout = obj["timeout"] as? Double, timeout > 0 {
            request.timeoutInterval = min(timeout, 30)
        } else {
            request.timeoutInterval = 15
        }
        // 引擎默认带疑似的 User-Agent（可选 obj headers 覆盖）
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        }
        if let headers = obj["headers"] as? [String: String] {
            for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        }
        if let body = obj["body"] as? String {
            request.httpBody = body.data(using: .utf8)
        }

        let sema = DispatchSemaphore(value: 0)
        var responseData: Data? = nil
        var responseHeaders: [String: String] = [:]
        var responseError: Error? = nil

        URLSession.shared.dataTask(with: request) { data, resp, error in
            responseError = error
            if let d = data { responseData = d }
            if let http = resp as? HTTPURLResponse {
                for (k, v) in http.allHeaderFields {
                    responseHeaders["\(k)"] = "\(v)"
                }
            }
            sema.signal()
        }.resume()

        _ = sema.wait(timeout: .now() + 35)

        if let err = responseError {
            NSLog("[JSEnv/fetch] %@ -> %@", urlString, err.localizedDescription)
            return out
        }
        // 内容尽量按文本读取（JS 端只认 string）；二进制场景由响应头判断
        var content = ""
        if let data = responseData {
            if let s = String(data: data, encoding: .utf8) {
                content = s
            } else if let s = String(data: data, encoding: .isoLatin1) {
                content = s
            } else {
                content = data.base64EncodedString()
            }
        }
        out["content"] = content
        out["headers"] = responseHeaders
        return out
    }

    // MARK: 规则管理

    /// 从 bundle 读取规则 JS 文本（Resources/js/rules/ 下）。
    func bundledRuleTexts() -> [String: String] {
        var out: [String: String] = [:]
        for name in Self.bundledRuleNames {
            if let url = Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: "js", subdirectory: "js/rules"),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                out[name] = text
            }
        }
        return out
    }

    /// 缓存规则文本（prepare 时调用）。返回已缓存条数。
    @discardableResult
    func cacheRuleTexts(_ texts: [String: String]) -> Int {
        var count = 0
        for (k, v) in texts {
            if v.isEmpty { continue }
            cachedRuleTexts[k] = v
            count += 1
        }
        return count
    }

    /// 站点 ext → 规则文件名（% 解码后取最后一段，如 …/虎牙.js → 虎牙.js）
    func ruleName(for site: Site) -> String {
        (site.ext.removingPercentEncoding ?? site.ext).lastPathComponent
    }

    /// 把站点规则切为当前激活规则（同站点则跳过，避免重复 eval）。线程安全。
    @discardableResult
    func activateSite(_ site: Site) -> Bool {
        execQueue.sync { activateSiteCore(site) }
    }

    private func activateSiteCore(_ site: Site) -> Bool {
        let name = ruleName(for: site)
        guard let text = cachedRuleTexts[name] ?? cachedRuleTexts.first(where: { $0.key == name })?.value else {
            NSLog("[JSEnv] 未缓存的规则 %@", name)
            return false
        }
        if activeRuleName == name { return true }
        guard let ctx = ensureContext() else { return false }
        ctx.evaluateScript("globalThis.CongcongTV.init(arguments[0]);", withArguments: [text])
        activeRuleName = name
        return true
    }

    // MARK: 引擎入口（Core 不排队，公开方法在 execQueue 上串行；async 包装见 EngineManager 尾部）

    private func homeCore() -> [Category] {
        guard let ctx = context else { return [] }
        let v = ctx.evaluateScript("globalThis.CongcongTV.home(false, '', '')").toObject()
        return Mapper.categoryList(from: v)
    }

    private func homeVodCore(_ params: [String: Any]? = nil) -> [VOD] {
        guard let ctx = context else { return [] }
        if let p = params, !p.isEmpty {
            let json = (try? JSONSerialization.data(withJSONObject: p)) ?? Data()
            let str = String(data: json, encoding: .utf8) ?? "{}"
            let js = "globalThis.CongcongTV.homeVod(JSON.parse(arguments[0]))"
            if let v = ctx.evaluateScript(js, withArguments: [str]).toObject() {
                return Mapper.vodList(from: v)
            }
        } else {
            if let v = ctx.evaluateScript("globalThis.CongcongTV.homeVod({})").toObject() {
                return Mapper.vodList(from: v)
            }
        }
        return []
    }

    private func categoryCore(tid: String, pg: Int) -> [VOD] {
        guard let ctx = context else { return [] }
        let js = "globalThis.CongcongTV.category(arguments[0], arguments[1], false, '')"
        if let v = ctx.evaluateScript(js, withArguments: [tid, pg]).toObject() {
            return Mapper.vodList(from: v)
        }
        return []
    }

    private func detailCore(vodId: String) -> VOD? {
        guard let ctx = context else { return nil }
        let js = "globalThis.CongcongTV.detail(arguments[0])"
        let v = ctx.evaluateScript(js, withArguments: [vodId]).toObject()
        return Mapper.vodDetail(from: v)
    }

    private func searchCore(wd: String, pg: Int = 1) -> [VOD] {
        guard let ctx = context else { return [] }
        let encoded = wd.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? wd
        let js = "globalThis.CongcongTV.search(arguments[0], true, arguments[1])"
        if let v = ctx.evaluateScript(js, withArguments: [encoded, pg]).toObject() {
            return Mapper.vodList(from: v)
        }
        return []
    }

    private func playCore(flag: String, url: String) -> PlayResult {
        guard let ctx = context else { return PlayResult() }
        let js = "globalThis.CongcongTV.play(arguments[0], arguments[1], '')"
        if let v = ctx.evaluateScript(js, withArguments: [flag, url]).toObject() {
            return Mapper.playResult(from: v) ?? PlayResult()
        }
        return PlayResult()
    }

    // MARK: 公开同步入口（内部串行）

    func home() -> [Category] { execQueue.sync { homeCore() } }
    func homeVod(_ params: [String: Any]? = nil) -> [VOD] { execQueue.sync { homeVodCore(params) } }
    func category(tid: String, pg: Int) -> [VOD] { execQueue.sync { categoryCore(tid: tid, pg: pg) } }
    func detail(vodId: String) -> VOD? { execQueue.sync { detailCore(vodId: vodId) } }
    func search(wd: String, pg: Int = 1) -> [VOD] { execQueue.sync { searchCore(wd: wd, pg: pg) } }
    func play(flag: String, url: String) -> PlayResult { execQueue.sync { playCore(flag: flag, url: url) } }

    // MARK: async 入口（先激活站点规则，再在 execQueue 上执行核心；调用方线程安全）

    func asyncHomeCategories(for site: Site) async -> [Category] {
        await withCheckedContinuation { cont in
            execQueue.async {
                guard self.activateSiteCore(site) else { cont.resume(returning: []); return }
                cont.resume(returning: self.homeCore())
            }
        }
    }

    func asyncHomeVod(for site: Site) async -> [VOD] {
        await withCheckedContinuation { cont in
            execQueue.async {
                guard self.activateSiteCore(site) else { cont.resume(returning: []); return }
                cont.resume(returning: self.homeVodCore())
            }
        }
    }

    func asyncCategory(for site: Site, tid: String, pg: Int) async -> [VOD] {
        await withCheckedContinuation { cont in
            execQueue.async {
                guard self.activateSiteCore(site) else { cont.resume(returning: []); return }
                cont.resume(returning: self.categoryCore(tid: tid, pg: pg))
            }
        }
    }

    func asyncDetail(for site: Site, vodId: String) async -> VOD? {
        await withCheckedContinuation { cont in
            execQueue.async {
                guard self.activateSiteCore(site) else { cont.resume(returning: nil); return }
                cont.resume(returning: self.detailCore(vodId: vodId))
            }
        }
    }

    func asyncSearch(for site: Site, wd: String, pg: Int) async -> [VOD] {
        await withCheckedContinuation { cont in
            execQueue.async {
                guard self.activateSiteCore(site) else { cont.resume(returning: []); return }
                cont.resume(returning: self.searchCore(wd: wd, pg: pg))
            }
        }
    }

    func asyncPlay(for site: Site, flag: String, url: String) async -> PlayResult {
        await withCheckedContinuation { cont in
            execQueue.async {
                guard self.activateSiteCore(site) else { cont.resume(returning: PlayResult()); return }
                cont.resume(returning: self.playCore(flag: flag, url: url))
            }
        }
    }
}

private extension String {
    /// 文件路径最后一段（用于把带路径的 ext 名解析到 bundle 文件名）
    var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }
}

// MARK: - 本地存储宿主

final class LocalHost: NSObject {
    private var store: [String: [String: String]] = [:]
    private let lock = NSLock()

    func set(_ ns: String, _ key: String, _ value: String) {
        lock.lock()
        defer { lock.unlock() }
        store[ns, default: [:]][key] = value
    }

    func get(_ ns: String, _ key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return store[ns]?[key] ?? ""
    }

    func delete(_ ns: String, _ key: String) {
        lock.lock()
        defer { lock.unlock() }
        store[ns]?.removeValue(forKey: key)
    }
}

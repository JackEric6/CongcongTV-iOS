import SwiftUI
import KSPlayer

/// 详情页：紧凑信息头 + 简介 + 分集列表，点击分集进入播放器。
/// 需要 source 信息才能调用引擎的 detail/play，因此通过 sourceKey 反查站点。
struct DetailView: View {
    let vod: VOD

    @EnvironmentObject private var engine: EngineManager
    @EnvironmentObject private var store: ConfigStore

    @State private var detail: VOD?
    @State private var episodes: [Episode] = []
    @State private var playSources: [PlaySource] = []
    @State private var selectedFlag: String = ""
    @State private var loadingDetail = false
    @State private var errorText: String?
    /// 播放器 sheet 用的 Identifiable 包装
    @State private var playerItem: PlayerItem?

    private var site: Site? {
        guard let key = vod.sourceKey else { return nil }
        return store.config.sites.first { $0.key == key && $0.isUsableOnIOS }
    }

    private var isXiguaSource: Bool {
        vod.sourceKey == XiguaCMSService.sourceKey
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 标题下直接展示来源、备注与简介，避免海报占据详情页首屏高度。
                VStack(alignment: .leading, spacing: 7) {
                    Text(detail?.vod_name ?? vod.vod_name)
                        .font(.title3.bold())
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if let rem = detail?.vod_remarks, !rem.isEmpty {
                            Text(rem)
                        }
                        if let sn = vod.sourceName {
                            Text(sn)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if let content = detail?.vod_content, !content.isEmpty {
                        Text(content)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(4)
                    }
                }
                .padding(.horizontal, 12)

                if loadingDetail {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在加载播放信息…")
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                }

                // 分集
                if playSources.count > 1 {
                    Picker("线路", selection: $selectedFlag) {
                        ForEach(playSources) { source in
                            Text(source.name).tag(source.name)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                }

                if !episodes.isEmpty {
                    Text("选集")
                        .font(.headline)
                        .padding(.horizontal, 12)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                        ForEach(episodes) { ep in
                            Button {
                                play(episode: ep)
                            } label: {
                                Text(ep.name)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemFill))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetailIfNeeded() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.toggleFavorite(detail ?? vod)
                } label: {
                    Image(systemName: store.isFavorite(detail ?? vod) ? "star.fill" : "star")
                }
                .accessibilityLabel(store.isFavorite(detail ?? vod) ? "取消收藏" : "收藏")
            }
        }
        .fullScreenCover(item: $playerItem) { item in
            ZStack(alignment: .topTrailing) {
                KSVideoPlayerView(url: item.url, options: item.options, title: item.title)
                    .ignoresSafeArea()

                Button {
                    playerItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("关闭播放器")
                .padding(.top, 18)
                .padding(.trailing, 18)
            }
        }
        .alert("无法播放", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("确定", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "未知错误")
        }
        .onChange(of: selectedFlag) { _, newValue in
            episodes = playSources.first(where: { $0.name == newValue })?.episodes ?? []
        }
    }

    private func play(episode: Episode) {
        errorText = nil
        if isXiguaSource {
            startPlayback(
                urlString: episode.url,
                sourceName: XiguaCMSService.sourceName,
                episodeName: episode.name
            )
            return
        }
        guard let site else {
            errorText = "该站点不可用"
            return
        }
        Task {
            let pr = await engine.loadPlay(for: site, flag: selectedFlag, url: episode.url)
            guard !pr.url.isEmpty, let url = URL(string: pr.url) else {
                errorText = "解析失败：\(episode.url)"
                return
            }
            startPlayback(url: url, headers: pr.header, sourceName: site.name, episodeName: episode.name)
        }
    }

    private func loadDetailIfNeeded() async {
        guard detail == nil, !loadingDetail else { return }
        loadingDetail = true
        defer { loadingDetail = false }

        let d: VOD?
        if isXiguaSource {
            d = await XiguaCMSService.shared.detail(vodId: vod.vod_id)
        } else if let site {
            d = await engine.loadDetail(for: site, vodId: vod.vod_id)
        } else {
            return
        }
        guard let d else {
            errorText = "未能加载影片详情，请稍后重试"
            return
        }
        detail = d
        configurePlaySources(for: d)
        if episodes.isEmpty {
            errorText = "该影片暂无可播放分集"
        }
    }

    private func configurePlaySources(for vod: VOD) {
        let flags = vod.vod_play_from.components(separatedBy: "$$$")
        let urls = vod.vod_play_url.components(separatedBy: "$$$")
        playSources = zip(flags, urls).compactMap { flag, urls in
            let name = flag.trimmingCharacters(in: .whitespacesAndNewlines)
            let episodes = Mapper.episodes(from: urls)
            guard !name.isEmpty, !episodes.isEmpty else { return nil }
            return PlaySource(name: name, episodes: episodes)
        }
        if playSources.isEmpty, !vod.vod_play_url.isEmpty {
            playSources = [PlaySource(name: "播放", episodes: Mapper.episodes(from: vod.vod_play_url))]
        }
        selectedFlag = playSources.first?.name ?? "播放"
        episodes = playSources.first?.episodes ?? []
    }

    private func startPlayback(urlString: String, sourceName: String) {
        let normalizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalizedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            errorText = "播放地址无效"
            return
        }
        startPlayback(url: url, headers: nil, sourceName: sourceName)
    }

    private func startPlayback(
        urlString: String,
        sourceName: String,
        episodeName: String
    ) {
        let normalizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalizedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            errorText = "播放地址无效"
            return
        }
        startPlayback(url: url, headers: nil, sourceName: sourceName, episodeName: episodeName)
    }

    private func startPlayback(
        url: URL,
        headers: [String: String]?,
        sourceName: String,
        episodeName: String? = nil
    ) {
        let options = KSOptions()
        if let headers, !headers.isEmpty {
            options.appendHeader(headers)
        }
        let resolvedEpisodeName = episodeName
            ?? episodes.first(where: { $0.url == url.absoluteString })?.name
            ?? "播放"
        playerItem = PlayerItem(
            url: url,
            options: options,
            title: episodeName.map { "\(vod.vod_name) - \($0)" } ?? vod.vod_name
        )
        store.addHistory(ConfigStore.HistoryItem(
            vod_id: vod.vod_id,
            vod_name: vod.vod_name,
            vod_pic: vod.vod_pic,
            sourceKey: vod.sourceKey ?? "",
            sourceName: sourceName,
            episodeName: resolvedEpisodeName
        ))
    }
}

private struct PlaySource: Identifiable {
    let name: String
    let episodes: [Episode]

    var id: String { name }
}

/// sheet 的 .item 包装
struct PlayerItem: Identifiable {
    let id = UUID()
    let url: URL
    let options: KSOptions
    let title: String
}

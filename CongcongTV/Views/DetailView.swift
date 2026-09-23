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
    @State private var isSynopsisExpanded = false
    @State private var isEpisodeReversed = false
    @State private var showAllEpisodes = true
    @State private var playerItem: PlayerItem?

    private var site: Site? {
        guard let key = vod.sourceKey else { return nil }
        return store.config.sites.first { $0.key == key && $0.isUsableOnIOS }
    }

    private var isXiguaSource: Bool {
        vod.sourceKey == XiguaCMSService.sourceKey
    }

    private var visibleEpisodes: [Episode] {
        let filtered = showAllEpisodes ? episodes : Array(episodes.prefix(12))
        return isEpisodeReversed ? Array(filtered.reversed()) : filtered
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Color.black
                    if let item = playerItem {
                        KSVideoPlayerView(url: item.url, options: item.options, title: item.title)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "play.rectangle")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text(loadingDetail ? "正在加载播放信息…" : "请选择分集开始播放")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(detail?.vod_name ?? vod.vod_name)
                            .font(.title3.bold())
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Button {
                            store.toggleFavorite(detail ?? vod)
                        } label: {
                            Image(systemName: store.isFavorite(detail ?? vod) ? "star.fill" : "star")
                                .foregroundStyle(.yellow)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(store.isFavorite(detail ?? vod) ? "取消收藏" : "收藏")
                    }
                    HStack(spacing: 8) {
                        if let rem = detail?.vod_remarks, !rem.isEmpty { Text(rem) }
                        if let sn = vod.sourceName { Text(sn) }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if let content = detail?.vod_content, !content.isEmpty {
                        Text(content)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(isSynopsisExpanded ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(isSynopsisExpanded ? "收起简介" : "展开简介") {
                            isSynopsisExpanded.toggle()
                        }
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 12)

                if !episodes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("选集")
                                .font(.headline)
                            Spacer()
                            Button {
                                isEpisodeReversed.toggle()
                            } label: {
                                Label(isEpisodeReversed ? "正序" : "倒序", systemImage: "arrow.up.arrow.down")
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            Button {
                                showAllEpisodes.toggle()
                            } label: {
                                Label(showAllEpisodes ? "部分" : "全部", systemImage: "square.grid.2x2")
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                            ForEach(visibleEpisodes) { ep in
                                Button {
                                    play(episode: ep)
                                } label: {
                                    Text(ep.name)
                                        .font(.caption)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(isCurrentEpisode(ep) ? Color.accentColor : Color(.secondarySystemFill))
                                        .foregroundStyle(isCurrentEpisode(ep) ? .white : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 12)
                }

                if playSources.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("换源")
                                .font(.headline)
                            Spacer()
                            Text("当前：\(selectedFlag)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(playSources) { source in
                                    Button {
                                        selectedFlag = source.name
                                    } label: {
                                        Text(source.name)
                                            .font(.subheadline)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(selectedFlag == source.name ? Color.accentColor : Color(.secondarySystemFill))
                                            .foregroundStyle(selectedFlag == source.name ? .white : .primary)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetailIfNeeded() }
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
            Task { @MainActor in
                let resolvedURL = await XiguaCMSService.shared.resolvePlaybackURL(episode.url)
                guard let url = URL(string: resolvedURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else {
                    errorText = "解析失败：\(episode.url)"
                    return
                }
                startPlayback(
                    url: url,
                    headers: nil,
                    sourceName: XiguaCMSService.sourceName,
                    episodeName: episode.name
                )
            }
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

    private func isCurrentEpisode(_ episode: Episode) -> Bool {
        guard let title = playerItem?.title else { return false }
        return title.hasSuffix(" - \(episode.name)")
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

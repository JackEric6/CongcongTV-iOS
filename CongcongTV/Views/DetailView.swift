import SwiftUI
import AVKit

/// 详情页：海报 + 简介 + 分集列表，点击分集进入播放器。
/// 需要 source 信息才能调用引擎的 detail/play，因此通过 sourceKey 反查站点。
struct DetailView: View {
    let vod: VOD

    @EnvironmentObject private var engine: EngineManager
    @EnvironmentObject private var store: ConfigStore

    @State private var detail: VOD?
    @State private var episodes: [Episode] = []
    @State private var selectedFlag: String = ""
    @State private var playing: AVPlayer?
    @State private var errorText: String?
    /// 播放器 sheet 用的 Identifiable 包装
    @State private var playerItem: PlayerItem?

    private var site: Site? {
        guard let key = vod.sourceKey else { return nil }
        return store.config.sites.first { $0.key == key && $0.isUsableOnIOS }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 头部：海报 + 标题/备注
                HStack(alignment: .top, spacing: 12) {
                    RemoteImage(url: (detail?.vod_pic ?? vod.vod_pic), placeholder: "play.rectangle")
                        .frame(width: 110, height: 165)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(detail?.vod_name ?? vod.vod_name)
                            .font(.headline)
                            .lineLimit(3)
                        if let rem = detail?.vod_remarks, !rem.isEmpty {
                            Text(rem)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let sn = vod.sourceName {
                            Text("来自：\(sn)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        HStack(spacing: 10) {
                            Button {
                                store.toggleFavorite(detail ?? vod)
                            } label: {
                                Label(store.isFavorite(detail ?? vod) ? "已收藏" : "收藏",
                                      systemImage: store.isFavorite(detail ?? vod) ? "star.fill" : "star")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)

                // 简介
                if let content = detail?.vod_content, !content.isEmpty {
                    Text(content)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(6)
                        .padding(.horizontal, 12)
                }

                // 分集
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
        .sheet(item: $playerItem) { _ in
            NavigationStack {
                PlayerSheetView(player: playing, onClose: {
                    playing = nil
                    playerItem = nil
                })
            }
            .presentationDetents([.large])
        }
        .onChange(of: playing) { newValue in
            if newValue != nil, playerItem == nil {
                playerItem = PlayerItem(flag: selectedFlag)
            }
        }
    }

    private func play(episode: Episode) {
        errorText = nil
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
            let player = AVPlayer(url: url)
            playing = player
            store.addHistory(ConfigStore.HistoryItem(
                vod_id: vod.vod_id,
                vod_name: vod.vod_name,
                vod_pic: vod.vod_pic,
                sourceKey: site.key,
                sourceName: site.name,
                episodeName: episode.name
            ))
        }
    }

    private func loadDetailIfNeeded() async {
        guard detail == nil, let site else { return }
        let d = await engine.loadDetail(for: site, vodId: vod.vod_id)
        detail = d
        if let d {
            // vod_play_from 是来源名的 # 分隔（一般单源）
            let flags = d.vod_play_from.split(separator: "#").map(String.init)
            selectedFlag = flags.first ?? "播放"
            episodes = Mapper.episodes(from: d.vod_play_url)
        }
    }
}

/// sheet 的 .item 包装
struct PlayerItem: Identifiable {
    let id = UUID()
    let flag: String
}

/// 播放器 sheet
struct PlayerSheetView: View {
    let player: AVPlayer?
    var onClose: () -> Void

    var body: some View {
        VStack {
            if let player {
                VideoPlayer(player: player)
            } else {
                Text("无法播放")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { onClose() }
            }
        }
    }
}

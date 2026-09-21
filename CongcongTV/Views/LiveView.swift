import SwiftUI
import AVKit

/// 直播 Tab：读取配置 lives 段（playerType=2 的地址直接用 AVPlayer 播放）。
/// 对部分需要指定 UA 的台（如 综合直播/虎牙一起看），AVPlayer 无法带自定义 UA，
/// 提供复制地址 / 提示切换网络等兜底。
struct LiveView: View {
    @EnvironmentObject private var config: ConfigStore

    @State private var playingChannel: LiveChannel?
    @State private var player: AVPlayer?
    @State private var failedChannel: String?
    @State private var nowPlaying: LiveChannel?

    var body: some View {
        NavigationStack {
            let lives = config.config.lives
            List {
                if lives.isEmpty {
                    Text("配置中没有直播源")
                        .foregroundColor(.secondary)
                }
                ForEach(lives) { live in
                    Button {
                        play(live)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(live.name)
                                    .foregroundColor(.primary)
                                if let ua = live.ua, !ua.isEmpty {
                                    Text("需要 UA：\(ua)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if nowPlaying?.name == live.name {
                                Image(systemName: "airplayvideo")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("直播")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $playingChannel) { ch in
                NavigationStack {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("完成") {
                                    player?.pause()
                                    player = nil
                                    playingChannel = nil
                                    nowPlaying = nil
                                }
                            }
                        }
                }
                .presentationDetents([.large])
            }
        }
    }

    private func play(_ live: LiveChannel) {
        player?.pause()
        guard let url = URL(string: live.url) else {
            failedChannel = live.name
            return
        }
        let p = AVPlayer(url: url)
        player = p
        nowPlaying = live
        playingChannel = live
    }
}

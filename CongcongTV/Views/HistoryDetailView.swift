import SwiftUI

/// 历史条目跳回详情（需要把 source 还原成可用的站点再进 DetailView）。
struct HistoryDetailView: View {
    let item: ConfigStore.HistoryItem

    @EnvironmentObject private var store: ConfigStore

    private var site: Site? {
        store.config.sites.first { $0.key == item.sourceKey && $0.isUsableOnIOS }
    }

    var body: some View {
        Group {
            if let site {
                let vod = VOD(vod_id: item.vod_id,
                              vod_name: item.vod_name,
                              vod_pic: item.vod_pic,
                              sourceKey: site.key,
                              sourceName: site.name)
                DetailView(vod: vod)
            } else {
                // 历史里的 jar 站（Android 专用）在 iOS 上不可用
                ScrollView {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("该来源在 iOS 上不可用（Android 专用源）")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                }
                .navigationTitle("记录")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

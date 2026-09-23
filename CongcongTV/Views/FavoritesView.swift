import SwiftUI

/// 收藏列表：支持进入影片详情和取消收藏。
struct FavoritesView: View {
    @EnvironmentObject private var store: ConfigStore

    var body: some View {
        NavigationStack {
            List {
                if store.favorites.isEmpty {
                    Text("暂无收藏")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(store.favorites, id: \.self) { vod in
                        NavigationLink(value: vod) {
                            HStack(spacing: 10) {
                                RemoteImage(url: vod.vod_pic, placeholder: "play.rectangle")
                                    .frame(width: 44, height: 62)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vod.vod_name)
                                        .font(.subheadline)
                                    if let sourceName = vod.sourceName {
                                        Text(sourceName)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .onDelete { indexes in
                        indexes.map { store.favorites[$0] }.forEach(store.toggleFavorite)
                    }
                }
            }
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: VOD.self) { vod in
                DetailView(vod: vod)
            }
        }
    }
}

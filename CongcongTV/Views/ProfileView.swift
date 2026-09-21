import SwiftUI

/// “我的” Tab：历史 / 收藏 / 设置入口。
struct ProfileView: View {
    @EnvironmentObject private var store: ConfigStore
    @EnvironmentObject private var appModel: AppModel

    private var recentHistory: [ConfigStore.HistoryItem] {
        Array(store.history.prefix(20))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("最近观看") {
                    if recentHistory.isEmpty {
                        Text("暂无历史")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(recentHistory) { item in
                            NavigationLink {
                                HistoryDetailView(item: item)
                            } label: {
                                HStack(spacing: 10) {
                                    RemoteImage(url: item.vod_pic, placeholder: "play.rectangle")
                                        .frame(width: 44, height: 62)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.vod_name)
                                            .font(.subheadline)
                                        Text("\(item.sourceName) · \(item.episodeName)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { idx in
                            for i in idx {
                                store.removeHistory(recentHistory[i])
                            }
                        }
                    }
                }

                Section("收藏") {
                    if store.favorites.isEmpty {
                        Text("暂无收藏")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(store.favorites) { vod in
                            NavigationLink(value: vod) {
                                HStack(spacing: 10) {
                                    RemoteImage(url: vod.vod_pic, placeholder: "play.rectangle")
                                        .frame(width: 44, height: 62)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(vod.vod_name)
                                            .font(.subheadline)
                                        if let sn = vod.sourceName {
                                            Text(sn).font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .onDelete { idx in
                            for i in idx {
                                store.toggleFavorite(store.favorites[i])
                            }
                        }
                    }
                }

                Section("设置") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("配置与关于", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: VOD.self) { DetailView(vod: $0) }
        }
    }
}

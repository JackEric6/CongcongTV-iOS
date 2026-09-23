import SwiftUI

/// 首页：展示豆瓣实时热门影音，点击条目后交给站内搜索寻找可播放资源。
struct HomeView: View {
    @State private var trendingItems: [DoubanTrendingItem] = []
    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if loaded && !trendingItems.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("热门推荐")
                                .font(.title2)
                                .bold()
                                .padding(.horizontal, 12)
                                .padding(.top, 8)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 100), spacing: 10)],
                                spacing: 14
                            ) {
                                ForEach(trendingItems) { item in
                                    NavigationLink {
                                        SearchView(initialQuery: item.title)
                                    } label: {
                                        TrendingCard(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                } else if failed {
                    VStack(spacing: 16) {
                        EmptyPlaceholder(systemImage: "wifi.exclamationmark", text: "热门推荐加载失败\n请检查网络后重试")
                        Button("重新加载") {
                            Task { await load(force: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView("正在加载热门推荐…")
                }
            }
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SearchView()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("搜索")
                }
            }
            .task { await load() }
            .refreshable { await load(force: true) }
            .navigationDestination(for: VOD.self) { DetailView(vod: $0) }
        }
    }

    private func load(force: Bool = false) async {
        guard force || !loaded else { return }
        failed = false
        let items = await DoubanTrendingService.shared.loadTrending()
        trendingItems = items
        loaded = true
        failed = items.isEmpty
    }
}

private struct TrendingCard: View {
    let item: DoubanTrendingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: item.cover, placeholder: "film")
                .aspectRatio(2.0 / 3.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(item.title)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(2)

            if !item.rate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(item.rate, systemImage: "star.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

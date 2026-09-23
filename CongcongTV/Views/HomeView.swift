import SwiftUI

/// 首页：展示豆瓣实时热门影音，点击条目后直接寻找并打开可播放资源。
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
                                        TrendingDetailRoute(item: item)
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
                    HStack(spacing: 16) {
                        NavigationLink {
                            CategoryView()
                        } label: {
                            Image(systemName: "square.grid.2x2")
                        }
                        .accessibilityLabel("分类")

                        NavigationLink {
                            SearchView()
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("搜索")
                    }
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
            TrendingPoster(url: item.cover)
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

/// 首页目的地：后台查询西瓜资源，成功后直接展示详情页，不展示搜索结果列表。
private struct TrendingDetailRoute: View {
    let item: DoubanTrendingItem

    @State private var vod: VOD?
    @State private var isLoading = true
    @State private var retryToken = 0

    var body: some View {
        Group {
            if let vod {
                DetailView(vod: vod)
            } else if isLoading {
                ProgressView("正在查找片源…")
            } else {
                VStack(spacing: 14) {
                    EmptyPlaceholder(
                        systemImage: "film.slash",
                        text: "未找到“\(item.title)”的可播放片源"
                    )
                    Button("重新查找") {
                        retryToken += 1
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: retryToken) {
            isLoading = true
            vod = nil
            let results = await XiguaCMSService.shared.search(item.title)
            let normalizedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            vod = results.first(where: {
                $0.vod_name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(normalizedTitle) == .orderedSame
            }) ?? results.first
            isLoading = false
        }
    }
}

/// 豆瓣图片常见为 http 或需要移动端请求头，首页单独补足请求并保留清晰占位态。
private struct TrendingPoster: View {
    let url: String

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(.systemGray6)
                    Image(systemName: "film")
                        .font(.system(size: 28))
                        .foregroundColor(.gray)
                }
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        image = nil
        let value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let secureURL = value.hasPrefix("http://") ? "https://" + String(value.dropFirst(7)) : value
        guard let imageURL = URL(string: secureURL) else { return }

        var request = URLRequest(url: imageURL)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let loadedImage = UIImage(data: data) else { return }
        image = loadedImage
    }
}

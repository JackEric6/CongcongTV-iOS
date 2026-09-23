import SwiftUI

/// 全局搜索页：优先搜索可直接播放的西瓜 CMS 资源。
struct SearchView: View {
    private let initialQuery: String?
    @State private var query = ""
    @State private var results: [VOD] = []
    @State private var searching = false
    @State private var searchedOnce = false
    @State private var trendingItems: [DoubanTrendingItem] = []
    @State private var trendingLoading = false
    @State private var didStart = false

    init(initialQuery: String? = nil) {
        self.initialQuery = initialQuery
    }

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty && !searchedOnce {
                    idleContent
                } else if results.isEmpty && searchedOnce && !searching {
                    EmptyPlaceholder(systemImage: "questionmark.circle", text: "没有找到相关内容")
                } else {
                    ScrollView {
                        VodGrid(vods: results)
                    }
                }
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索全网影片")
            .onSubmit(of: .search) {
                Task { await doSearch() }
            }
            .overlay {
                if searching {
                    ProgressView("搜索中…")
                }
            }
            .task {
                await startIfNeeded()
            }
            .navigationDestination(for: VOD.self) { DetailView(vod: $0) }
        }
    }

    @ViewBuilder
    private var idleContent: some View {
        if trendingLoading {
            ProgressView("正在加载豆瓣热搜…")
        } else if trendingItems.isEmpty {
            EmptyPlaceholder(systemImage: "magnifyingglass", text: "暂无豆瓣热搜，输入关键词搜索影片")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("豆瓣热搜")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.bottom, 8)

                    ForEach(Array(trendingItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            query = item.title
                            Task { await doSearch() }
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(index < 3 ? Color.accentColor : Color.secondary)
                                    .frame(width: 24, alignment: .leading)
                                Text(item.title)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if !item.rate.isEmpty {
                                    Text(item.rate)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top)
            }
        }
    }

    private func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true

        if let initialQuery {
            let trimmed = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                await loadTrending()
                return
            }
            query = trimmed
            await doSearch()
        } else {
            await loadTrending()
        }
    }

    private func loadTrending() async {
        guard !trendingLoading, trendingItems.isEmpty else { return }
        trendingLoading = true
        trendingItems = await DoubanTrendingService.shared.loadTrending()
        trendingLoading = false
    }

    private func doSearch() async {
        let wd = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wd.isEmpty else { return }
        searching = true
        searchedOnce = true
        let items = await XiguaCMSService.shared.search(wd)
        results = items
        searching = false
    }
}

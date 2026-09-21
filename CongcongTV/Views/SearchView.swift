import SwiftUI

/// 全局搜索页：多站点并发搜索，结果按来源分组展示。
struct SearchView: View {
    @EnvironmentObject private var engine: EngineManager
    @EnvironmentObject private var config: ConfigStore

    @State private var query = ""
    @State private var results: [VOD] = []
    @State private var searching = false
    @State private var searchedOnce = false

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty && !searchedOnce {
                    EmptyPlaceholder(systemImage: "magnifyingglass", text: "输入关键词搜索影片")
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
            .navigationDestination(for: VOD.self) { DetailView(vod: $0) }
        }
    }

    private func doSearch() async {
        let wd = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wd.isEmpty else { return }
        searching = true
        searchedOnce = true
        let items = await engine.searchSites(wd)
        results = items
        searching = false
    }
}

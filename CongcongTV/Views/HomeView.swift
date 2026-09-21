import SwiftUI

/// 首页：横幅口号 + 全部可用站点的首页推荐流（合并各 JS 源结果，保留来源名称）。
struct HomeView: View {
    @EnvironmentObject private var engine: EngineManager
    @EnvironmentObject private var store: ConfigStore

    @State private var vods: [VOD] = []
    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if loaded && !vods.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("丛丛影视 · 精选")
                                .font(.title2).bold()
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                            VodGrid(vods: vods, columns: [GridItem(.adaptive(minimum: 100), spacing: 10)])
                        }
                    }
                } else if failed {
                    VStack(spacing: 16) {
                        EmptyPlaceholder(systemImage: "wifi.exclamationmark", text: "加载失败\n请检查网络后在设置中重试")
                        Button("重新加载") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView("正在加载…")
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
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .navigationDestination(for: VOD.self) { DetailView(vod: $0) }
        }
    }

    private func load() async {
        guard !loaded || failed else { return }
        failed = false
        let items = await engine.loadHomeVods()
        vods = items
        loaded = true
        failed = vods.isEmpty
    }
}

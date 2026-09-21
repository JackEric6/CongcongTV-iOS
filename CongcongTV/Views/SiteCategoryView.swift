import SwiftUI

/// 某站点的分类页（home() 的分类 + 每类的片单）。
struct SiteCategoryView: View {
    let site: Site

    @EnvironmentObject private var engine: EngineManager
    @State private var categories: [Category] = []
    @State private var selected: Category?
    @State private var vods: [VOD] = []
    @State private var loadedCats = false
    @State private var loading = false
    @State private var page = 1
    @State private var endReached = false

    var body: some View {
        VStack(spacing: 0) {
            if !categories.isEmpty {
                // 分类横向滚动选择
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories) { cat in
                            Button {
                                selected = cat
                                vods = []
                                page = 1
                                endReached = false
                                Task { await loadPage(reset: true) }
                            } label: {
                                Text(cat.type_name)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selected == cat ? Color.orange.opacity(0.2) : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selected == cat ? Color.orange : Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(.secondarySystemBackground))
            }

            ScrollView {
                if vods.isEmpty && loading {
                    ProgressView("加载中…")
                        .padding(.top, 60)
                } else if vods.isEmpty {
                    EmptyPlaceholder(systemImage: "film", text: "暂无内容")
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 12) {
                        ForEach(vods) { vod in
                            NavigationLink(value: vod) {
                                VodCard(vod: vod)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                // 滚动到底触发下一页
                                if vod.id == vods.last?.id && !endReached && !loading {
                                    page += 1
                                    Task { await loadPage(reset: false) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 20)

                    if loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
        .navigationTitle(site.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCategoriesIfNeeded()
        }
        .navigationDestination(for: VOD.self) { DetailView(vod: $0) }
    }

    private func loadCategoriesIfNeeded() async {
        guard !loadedCats else {
            if selected == nil, let first = categories.first {
                selected = first
                await loadPage(reset: true)
            }
            return
        }
        let cats = await engine.loadCategories(for: site)
        categories = cats
        loadedCats = true
        if let first = cats.first {
            selected = first
            await loadPage(reset: true)
        }
    }

    private func loadPage(reset: Bool) async {
        guard let sel = selected else { return }
        loading = true
        let items = await engine.loadCategory(for: site, tid: sel.type_id, pg: reset ? 1 : page)
        loading = false
        if items.isEmpty {
            endReached = true
        } else if reset {
            vods = items
        } else {
            vods.append(contentsOf: items)
        }
    }
}

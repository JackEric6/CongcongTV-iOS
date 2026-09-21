import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sitePicker
                    categoryBar
                    statusBar
                    if model.isLoading && model.videos.isEmpty {
                        ProgressView("正在加载")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else if !model.lastError.isEmpty && model.videos.isEmpty {
                        EmptyStateView(title: model.message, detail: model.lastError, actionTitle: "重试") {
                            Task { await model.loadHome() }
                        }
                    } else if model.videos.isEmpty {
                        EmptyStateView(title: model.message, detail: "请在设置中检查配置地址") {
                            model.isShowingSettings = true
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(model.videos) { item in
                                NavigationLink {
                                    DetailView(item: item)
                                        .environmentObject(model)
                                } label: {
                                    VideoCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .navigationTitle("丛丛影视")
            .searchable(text: $searchText, prompt: "搜索影视")
            .onSubmit(of: .search) {
                Task { await model.search(searchText) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .refreshable { await model.loadConfig() }
            .sheet(isPresented: $model.isShowingSettings) {
                SettingsView()
                    .environmentObject(model)
            }
        }
    }

    private var sitePicker: some View {
        Group {
            if model.sites.count > 1 {
                Menu {
                    ForEach(model.sites) { site in
                        Button {
                            model.selectSite(site)
                        } label: {
                            if site.id == model.selectedSite?.id { Label(site.name, systemImage: "checkmark") }
                            else { Text(site.name) }
                        }
                    }
                } label: {
                    Label(model.selectedSite?.name ?? "选择站点", systemImage: "square.grid.2x2")
                        .font(.headline)
                }
            } else if let site = model.selectedSite {
                Label(site.name, systemImage: "play.tv")
                    .font(.headline)
            }
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("推荐") { Task { await model.loadHome() } }
                    .buttonStyle(CategoryButtonStyle(selected: model.categories.isEmpty))
                ForEach(model.categories) { category in
                    Button(category.name) { Task { await model.loadCategory(category) } }
                        .buttonStyle(CategoryButtonStyle(selected: false))
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isLoading { ProgressView().controlSize(.small) }
            Text(model.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
    }
}

private struct CategoryButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct VideoCard: View {
    let item: VideoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: item.poster)) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: Color.secondary.opacity(0.12).overlay(Image(systemName: "film").font(.title2).foregroundStyle(.secondary))
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(0.68, contentMode: .fit)
                .clipped()
                if !item.remark.isEmpty {
                    Text(item.remark)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.72))
                        .lineLimit(1)
                }
            }
            Text(item.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

private struct EmptyStateView: View {
    let title: String
    let detail: String
    var actionTitle: String = "打开设置"
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

struct DetailView: View {
    @EnvironmentObject private var model: AppModel
    let item: VideoItem
    @State private var detail: VideoDetail?
    @State private var isLoading = true
    @State private var error = ""
    @State private var target: PlayerTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if isLoading {
                    ProgressView("读取详情")
                } else if !error.isEmpty {
                    Text(error).foregroundStyle(.secondary)
                } else if let detail {
                    Text(detail.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("选集")
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                        ForEach(detail.episodes) { episode in
                            Button(episode.name) {
                                Task { await play(episode) }
                            }
                            .buttonStyle(.bordered)
                            .lineLimit(1)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $target) { target in
            VideoPlayerView(url: target.url, headers: target.headers)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: URL(string: item.poster)) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Color.secondary.opacity(0.12) }
            }
            .frame(width: 112, height: 158)
            .clipped()
            VStack(alignment: .leading, spacing: 8) {
                Text(item.name).font(.title3.weight(.semibold))
                if !item.remark.isEmpty { Text(item.remark).font(.subheadline).foregroundStyle(.secondary) }
                if let detail { Text(detail.episodes.isEmpty ? "暂无选集" : "共 \(detail.episodes.count) 集").font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    private func load() async {
        guard let site = model.selectedSite else { return }
        do {
            detail = try await model.service.detail(site: site, item: item)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func play(_ episode: Episode) async {
        guard let site = model.selectedSite else { return }
        do {
            let result = try await model.service.play(site: site, episode: episode)
            target = PlayerTarget(url: result.url, headers: result.headers)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PlayerTarget: Identifiable {
    let id = UUID()
    let url: URL
    let headers: [String: String]
}

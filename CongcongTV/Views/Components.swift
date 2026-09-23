import SwiftUI

/// 远程图片加载（配置里的 vod_pic / 海报地址多为 http，ATS 已在 Info.plist 放行）。
struct RemoteImage: View {
    let url: String
    let placeholder: String?

    @State private var image: UIImage?

    init(url: String, placeholder: String? = nil) {
        self.url = url
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else if let placeholder {
                placeholderView(systemName: placeholder)
            } else {
                placeholderView(systemName: "photo")
            }
        }
        .onAppear { load() }
        .task(id: url) { load() }
    }

    private func placeholderView(systemName: String) -> some View {
        ZStack {
            Color(.systemGray6)
            Image(systemName: systemName)
                .font(.system(size: 28))
                .foregroundColor(.gray)
        }
    }

    private func load() {
        guard image == nil, !url.isEmpty else { return }
        guard let u = URL(string: url) else {
            image = nil
            return
        }
        URLSession.shared.dataTask(with: u) { data, _, _ in
            if let data, let img = UIImage(data: data) {
                DispatchQueue.main.async { image = img }
            }
        }.resume()
    }
}

/// 视频卡片（首页/分类/搜索/收藏共用）。
struct VodCard: View {
    let vod: VOD
    var showSourceName = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(url: vod.vod_pic, placeholder: "play.rectangle")
                    .aspectRatio(2.0 / 3.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if !vod.vod_remarks.isEmpty {
                    Text(vod.vod_remarks)
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(4)
                }
            }
            Text(vod.vod_name)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(1)
            if showSourceName {
                Text(vod.sourceName ?? "")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// 竖排卡片网格（LazyVGrid + 自适应列）。
struct VodGrid: View {
    let vods: [VOD]
    let columns: [GridItem]

    init(vods: [VOD], columns: [GridItem] = [GridItem(.adaptive(minimum: 100), spacing: 10)]) {
        self.vods = vods
        self.columns = columns
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(vods) { vod in
                NavigationLink {
                    DetailView(vod: vod)
                } label: {
                    VodCard(vod: vod)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
    }
}

/// 空状态
struct EmptyPlaceholder: View {
    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundColor(.gray)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

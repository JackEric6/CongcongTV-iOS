import SwiftUI

/// 播放历史：按最近观看顺序展示，并支持删除和回到影片详情。
struct HistoryView: View {
    @EnvironmentObject private var store: ConfigStore

    var body: some View {
        NavigationStack {
            List {
                if store.history.isEmpty {
                    Text("暂无历史")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(store.history, id: \.self) { item in
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
                    .onDelete { indexes in
                        indexes.map { store.history[$0] }.forEach(store.removeHistory)
                    }
                }
            }
            .navigationTitle("历史")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

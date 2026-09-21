import SwiftUI

/// 分类页：站点列表。可用的 JS 源进入该站点的分类 / 片单；
/// jar 源（Android 专用）显示「仅 Android 源」占位提示。
struct CategoryView: View {
    @EnvironmentObject private var engine: EngineManager
    @EnvironmentObject private var config: ConfigStore

    var body: some View {
        NavigationStack {
            let sites = config.config.sites
            List {
                if sites.isEmpty {
                    Text("暂无站点")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
                ForEach(sites) { site in
                    if site.isUsableOnIOS {
                        NavigationLink {
                            SiteCategoryView(site: site)
                        } label: {
                            siteRow(site, badge: "可用")
                        }
                    } else {
                        siteRow(site, badge: "仅 Android 源")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    private func siteRow(_ site: Site, badge: String) -> some View {
        HStack(spacing: 12) {
            Text(site.name)
                .font(.subheadline)
            Spacer()
            Text(badge)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(badge == "可用" ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                .foregroundColor(badge == "可用" ? .green : .gray)
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }
}

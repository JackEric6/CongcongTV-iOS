import SwiftUI
import AVKit

/// 主界面容器：底部 TabBar（首页 / 历史 / 收藏 / 设置）。
struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView(selection: $appModel.selectedTab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(AppModel.Tab.home)

            HistoryView()
                .tabItem { Label("历史", systemImage: "clock.fill") }
                .tag(AppModel.Tab.history)

            FavoritesView()
                .tabItem { Label("收藏", systemImage: "star.fill") }
                .tag(AppModel.Tab.favorites)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(AppModel.Tab.settings)
        }
        .tint(.orange)
    }
}

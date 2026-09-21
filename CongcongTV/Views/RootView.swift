import SwiftUI
import AVKit

/// 主界面容器：底部 TabBar（首页 / 分类 / 直播 / 我的）+ 配置入口。
struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView(selection: $appModel.selectedTab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(AppModel.Tab.home)

            CategoryView()
                .tabItem { Label("分类", systemImage: "square.grid.2x2.fill") }
                .tag(AppModel.Tab.category)

            LiveView()
                .tabItem { Label("直播", systemImage: "tv.fill") }
                .tag(AppModel.Tab.live)

            ProfileView()
                .tabItem { Label("我的", systemImage: "person.fill") }
                .tag(AppModel.Tab.settings)
        }
        .tint(.orange)
    }
}

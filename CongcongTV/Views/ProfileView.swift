import SwiftUI

/// 兼容旧引用的“我的”页面；新的底部导航使用独立的历史、收藏和设置 Tab。
struct ProfileView: View {
    @EnvironmentObject private var store: ConfigStore

    var body: some View {
        NavigationStack {
            SettingsView()
                .navigationTitle("我的")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

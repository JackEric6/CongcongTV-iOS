import SwiftUI
import Combine

/// 全局 UI 状态（导航、当前播放、配置面板等），由 App 环境注入。
final class AppModel: ObservableObject {
    @Published var selectedTab: Tab = .home
    /// 播放器全屏开关
    @Published var isFullScreen = false

    enum Tab: Hashable {
        case home
        case category
        case search
        case live
        case settings
    }
}

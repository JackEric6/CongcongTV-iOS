import SwiftUI

@main
struct CongcongTVApp: App {
    @StateObject private var store = ConfigStore.shared
    @StateObject private var engine = EngineManager.shared
    @StateObject private var appModel = AppModel()

    init() {
        // 预先加载持久化的历史/收藏
        ConfigStore.shared.loadPersisted()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(engine)
                .environmentObject(appModel)
                .onAppear {
                    engine.bootstrap()
                }
                .preferredColorScheme(.dark)
        }
    }
}

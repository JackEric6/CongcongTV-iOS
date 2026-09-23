import SwiftUI
import KSPlayer

/// KSPlayer 播放容器，供需要在其他页面复用时使用。
struct NativePlayerView: View {
    let url: URL
    let options: KSOptions
    let title: String

    var body: some View {
        KSVideoPlayerView(url: url, options: options, title: title)
            .ignoresSafeArea()
    }
}

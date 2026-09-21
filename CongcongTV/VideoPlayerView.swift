import AVKit
import SwiftUI

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL
    let headers: [String: String]

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        var assetURL = url
        if !headers.isEmpty {
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            controller.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        } else {
            controller.player = AVPlayer(url: assetURL)
        }
        controller.entersFullScreenWhenPlaybackBegins = true
        controller.exitsFullScreenWhenPlaybackEnds = true
        controller.allowsPictureInPicturePlayback = true
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}

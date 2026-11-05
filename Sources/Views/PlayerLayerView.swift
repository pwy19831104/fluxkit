import AVFoundation
import SwiftUI

/// A bare `AVPlayerLayer` host used only as the source for Picture in Picture.
/// The visible player stays the standard `VideoPlayer` (with its controls).
final class PlayerLayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var onLayerReady: ((AVPlayerLayer) -> Void)?

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        onLayerReady?(view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        uiView.playerLayer.player = player
        onLayerReady?(uiView.playerLayer)
    }
}

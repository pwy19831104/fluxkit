import AVFoundation
import AVKit
import Foundation

/// Wraps `AVPictureInPictureController` and exposes a tiny observable surface for SwiftUI.
@MainActor
final class PiPManager: NSObject, ObservableObject {

    @Published private(set) var isActive = false

    private var controller: AVPictureInPictureController?

    var onStop: (() -> Void)?
    var onFailure: ((String) -> Void)?

    var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    var isPossible: Bool {
        controller?.isPictureInPicturePossible ?? false
    }

    func attach(layer: AVPlayerLayer) {
        guard isSupported else { return }
        if controller == nil {
            guard let controller = AVPictureInPictureController(playerLayer: layer) else { return }
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            self.controller = controller
        }
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        }
    }

    func stop() {
        controller?.stopPictureInPicture()
    }
}

extension PiPManager: AVPictureInPictureControllerDelegate {

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in self.isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            self.isActive = false
            self.onStop?()
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            self.isActive = false
            self.onFailure?(error.localizedDescription)
        }
    }
}

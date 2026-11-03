import Foundation
import Photos
import UIKit

enum PhotoSaverError: LocalizedError {
    case accessDenied
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Photo access was denied. Enable it in Settings to save videos."
        case .failed(let reason):
            return "Could not save to Photos: \(reason)"
        }
    }
}

enum PhotoSaver {
    static func saveVideo(at fileURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoSaverError.accessDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoSaverError.failed(error?.localizedDescription ?? "Unknown error"))
                }
            }
        }
    }
}

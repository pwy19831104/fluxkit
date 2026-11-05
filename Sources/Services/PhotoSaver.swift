import Foundation
import Photos
import UIKit

enum PhotoSaverError: LocalizedError {
    case accessDenied
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return L("Photo access was denied. Enable it in Settings to save videos.",
                     "没有相册权限。请到「设置」里允许访问相册后再保存。")
        case .failed(let reason):
            #if DEBUG
            NSLog("Photo save failed: \(reason)")
            #endif
            return L("Couldn't save to Photos. Please try again.",
                     "无法保存到相册，请重试。")
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
                    let reason = error?.localizedDescription ?? L("Unknown error", "未知错误")
                    continuation.resume(throwing: PhotoSaverError.failed(reason))
                }
            }
        }
    }
}

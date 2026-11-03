import AVFoundation
import CoreGraphics
import Foundation
import UIKit

enum ThumbnailService {

    /// Extracts a frame and writes it as a JPEG next to the download.
    /// Returns the file name (not a full URL) so records stay portable.
    static func makeThumbnail(for videoURL: URL, recordID: UUID) async -> String? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        let candidateTimes = [0.5, 2.0, 5.0, 0.0]
        var image: CGImage?
        for seconds in candidateTimes {
            if let created = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image {
                image = created
                break
            }
        }
        guard let cgImage = image else { return nil }

        let name = "\(recordID.uuidString).jpg"
        let destination = AppPaths.thumbnailURL(fileName: name)
        guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.72) else { return nil }
        do {
            try data.write(to: destination, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func duration(of url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}

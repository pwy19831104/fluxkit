#if DEBUG
import Foundation
import UIKit

/// Development-only fixtures for screenshots and UI tests.
/// Launch with `-seedLibrary` to replace the library with deterministic items.
enum DebugSeed {
    @MainActor
    static func seedIfRequested(library: LibraryStore) {
        guard ProcessInfo.processInfo.arguments.contains("-seedLibrary") else { return }
        for record in library.records {
            library.remove(record.id)
        }

        let titles = ["Alpha Clip", "Bravo Clip", "Charlie Clip"]
        // Deliberately mixed aspect ratios (landscape / portrait / tall portrait): the library grid
        // has to line up anyway, so screenshots exercise exactly the case that used to look ragged.
        let thumbnailSizes = [CGSize(width: 1280, height: 720),
                              CGSize(width: 720, height: 1280),
                              CGSize(width: 1080, height: 1920)]
        for (index, title) in titles.enumerated() {
            let url = URL(string: "https://example.com/demo-\(index).mp4")!
            var record = DownloadRecord(
                media: ResolvedMedia(kind: .progressive, url: url, title: title)
            )
            record.state = .finished
            record.bytesReceived = Int64(1_000_000 * (index + 1))
            record.bytesExpected = record.bytesReceived
            record.duration = 60
            record.createdAt = Date().addingTimeInterval(-Double(index) * 3600)
            record.thumbnailName = Self.writeThumbnail(size: thumbnailSizes[index], index: index)
            if index == 1 {
                record.lastPosition = 30 // resume at 50%
            } else if index == 2 {
                record.played = true   // finished badge
                record.lastPosition = nil
            }
            library.upsert(record)
        }
    }

    /// Writes a real JPEG so the grid has something to lay out (a missing thumbnail would collapse
    /// the difference this fixture is meant to show).
    private static func writeThumbnail(size: CGSize, index: Int) -> String? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor(hue: CGFloat(index) * 0.22 + 0.55, saturation: 0.55, brightness: 0.75, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let label = "\(Int(size.width))×\(Int(size.height))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: min(size.width, size.height) * 0.16, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let textSize = label.size(withAttributes: attributes)
            label.draw(at: CGPoint(x: (size.width - textSize.width) / 2,
                                   y: (size.height - textSize.height) / 2),
                       withAttributes: attributes)
        }
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let name = "seed-thumb-\(index).jpg"
        do {
            try data.write(to: AppPaths.thumbnailURL(fileName: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }
}
#endif

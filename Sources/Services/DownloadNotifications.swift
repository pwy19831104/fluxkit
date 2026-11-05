import Foundation
import UIKit
import UserNotifications

/// Local "download finished" notifications. No server, no push.
enum DownloadNotifications {

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    @MainActor
    static func finished(title: String) {
        guard AppSettings.shared.notifyOnFinish else { return }
        post(
            title: L("Download finished", "下载完成"),
            body: title
        )
    }

    @MainActor
    static func failed(title: String, reason: String) {
        guard AppSettings.shared.notifyOnFinish else { return }
        post(
            title: L("Download failed", "下载失败"),
            body: "\(title) — \(reason)"
        )
    }

    @MainActor
    private static func post(title: String, body: String) {
        // In the foreground the UI already shows progress; don't double-notify.
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

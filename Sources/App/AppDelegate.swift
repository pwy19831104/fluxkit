import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Touch the manager so the background URLSession is created (and reconnected after
        // a relaunch triggered by the system) even before any UI is built.
        _ = DownloadManager.shared
        return true
    }

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == BackgroundSessionBridge.identifier else {
            completionHandler()
            return
        }
        BackgroundSessionBridge.store(completionHandler)
        _ = DownloadManager.shared
    }
}

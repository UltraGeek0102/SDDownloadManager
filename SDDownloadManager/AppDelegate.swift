import UIKit
import UserNotifications

// No @UIApplicationMain here — DownloadManagerApp.swift (@main) owns the entry point
// and connects this delegate via @UIApplicationDelegateAdaptor.
class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
        return true
    }

    // Required for background URLSession: called when a background download task
    // completes while the app is suspended. Must call completionHandler after
    // all session events are processed so iOS knows we're done.
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        SDDownloadManager.shared.backgroundCompletionHandler = completionHandler
    }
}

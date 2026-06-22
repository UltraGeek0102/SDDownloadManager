import UIKit
import SwiftUI
import UserNotifications

@main
struct DownloadManagerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Request notification permission (used for "download complete" local notification)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Request Live Activity permission (shown to user)
        if #available(iOS 16.2, *) {
            // No explicit request needed — iOS prompts when first activity is started
        }

        return true
    }

    /// Required for background URLSession: iOS calls this when a background
    /// download task completes and the app needs to process the result.
    /// Store the completion handler — SDDownloadManager calls it when done.
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        print("[AppDelegate] Background session event: \(identifier)")
        SDDownloadManager.shared.backgroundCompletionHandler = completionHandler
    }
}

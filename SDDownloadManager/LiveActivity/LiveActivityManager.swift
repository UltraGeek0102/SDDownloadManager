import ActivityKit
import Foundation
import WidgetKit

@available(iOS 16.2, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private var activities: [String: Activity<DownloadActivityAttributes>] = [:]
    private var filenames:  [String: String] = [:]
    private var lastBytes:  [String: Int64]  = [:]
    private var lastTime:   [String: Date]   = [:]
    private let lock = NSLock()

    // MARK: - Public API

    func start(id: String, filename: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        lock.lock(); filenames[id] = filename; lock.unlock()

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); let old = self.activities[id]; self.lock.unlock()
            if let old = old { await old.end(dismissalPolicy: .immediate) }

            let attrs = DownloadActivityAttributes(downloadId: id, filename: filename)
            let state = DownloadActivityAttributes.ContentState(
                progress: 0, downloadedBytes: 0, totalBytes: 0,
                speedBytesPerSec: 0, statusLabel: "Downloading"
            )
            do {
                let act = try Activity<DownloadActivityAttributes>.request(
                    attributes: attrs,
                    content: ActivityContent(state: state, staleDate: nil)
                )
                self.lock.lock(); self.activities[id] = act; self.lock.unlock()
                print("[LA] started \(filename)")
            } catch { print("[LA] start error: \(error)") }
        }
    }

    func update(id: String, progress: Double, downloaded: Int64, total: Int64) {
        lock.lock()
        let filename = filenames[id] ?? ""
        let now      = Date()
        let elapsed  = now.timeIntervalSince(lastTime[id] ?? now)
        let delta    = downloaded - (lastBytes[id] ?? 0)
        let speed    = elapsed > 0.1 ? Int64(Double(max(delta, 0)) / elapsed) : 0
        lastBytes[id] = downloaded
        lastTime[id]  = now
        let activity  = activities[id]
        lock.unlock()

        // ── Path 1: direct async update (works in foreground) ───────────────
        if let activity = activity {
            let state = DownloadActivityAttributes.ContentState(
                progress: min(max(progress, 0), 1),
                downloadedBytes: downloaded, totalBytes: total,
                speedBytesPerSec: speed, statusLabel: "Downloading"
            )
            Task.detached(priority: .userInitiated) {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }

        // ── Path 2: App Group → widget extension process (background reliable) ─
        // Write progress to shared UserDefaults so the widget extension can read it.
        // Then wake the extension by reloading timelines.
        // The widget extension runs in its OWN process — never suspended by iOS.
        // When getTimeline() is called, it reads this data and calls activity.update()
        // from a process that iOS has explicitly woken for this purpose.
        SharedProgressStore.shared.update(
            id: id, filename: filename, progress: progress,
            downloaded: downloaded, total: total, speed: speed
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "DownloadWidget")
    }

    func end(id: String, success: Bool, downloaded: Int64 = 0) {
        lock.lock()
        let activity = activities[id]
        let dl       = lastBytes[id] ?? downloaded
        activities.removeValue(forKey: id)
        filenames.removeValue(forKey: id)
        lastBytes.removeValue(forKey: id)
        lastTime.removeValue(forKey: id)
        lock.unlock()

        SharedProgressStore.shared.remove(id: id)
        WidgetCenter.shared.reloadTimelines(ofKind: "DownloadWidget")

        guard let activity = activity else { return }
        let state = DownloadActivityAttributes.ContentState(
            progress: success ? 1.0 : 0.0,
            downloadedBytes: dl, totalBytes: 0, speedBytesPerSec: 0,
            statusLabel: success ? "Done" : "Failed"
        )
        Task.detached {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(5))
            )
        }
    }
}

final class LiveActivityBridge {
    static let shared = LiveActivityBridge()
    private init() {}

    func start(id: String, filename: String) {
        if #available(iOS 16.2, *) { LiveActivityManager.shared.start(id: id, filename: filename) }
    }
    func update(id: String, progress: Double, downloaded: Int64, total: Int64) {
        if #available(iOS 16.2, *) {
            LiveActivityManager.shared.update(id: id, progress: progress,
                                              downloaded: downloaded, total: total)
        }
    }
    func end(id: String, success: Bool, downloaded: Int64 = 0) {
        if #available(iOS 16.2, *) {
            LiveActivityManager.shared.end(id: id, success: success, downloaded: downloaded)
        }
    }
}

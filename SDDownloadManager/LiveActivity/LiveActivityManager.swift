import ActivityKit
import Foundation

/// Manages one Live Activity per active download.
/// All methods are safe to call from any thread including URLSession delegate queues.
/// IMPORTANT: update() uses fire-and-forget Task.detached — it never blocks the caller.
@available(iOS 16.2, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private var activities: [String: Activity<DownloadActivityAttributes>] = [:]
    private var lastBytes:  [String: Int64] = [:]
    private var lastTime:   [String: Date]  = [:]
    private let lock = NSLock()

    // MARK: - Public API

    func start(id: String, filename: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LA] Live Activities not enabled")
            return
        }
        let attrs = DownloadActivityAttributes(downloadId: id, filename: filename)
        let state = DownloadActivityAttributes.ContentState(
            progress: 0, downloadedBytes: 0, totalBytes: 0,
            speedBytesPerSec: 0, statusLabel: "Downloading"
        )
        do {
            let activity = try Activity<DownloadActivityAttributes>.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil)
            )
            lock.lock()
            activities[id] = activity
            lock.unlock()
            print("[LA] started for \(filename)")
        } catch {
            print("[LA] start error: \(error)")
        }
    }

    /// Called directly from URLSessionDownloadDelegate.didWriteData.
    /// That delegate fires in a system-granted background execution context —
    /// the correct place for ActivityKit updates. Never blocks.
    func update(id: String, progress: Double, downloaded: Int64, total: Int64) {
        lock.lock()
        let activity = activities[id]
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTime[id] ?? now)
        let delta   = downloaded - (lastBytes[id] ?? 0)
        let speed   = elapsed > 0.1 ? Int64(Double(max(delta, 0)) / elapsed) : 0
        lastBytes[id] = downloaded
        lastTime[id]  = now
        lock.unlock()

        guard let activity = activity else { return }

        let state = DownloadActivityAttributes.ContentState(
            progress: min(max(progress, 0), 1),
            downloadedBytes: downloaded,
            totalBytes: total,
            speedBytesPerSec: speed,
            statusLabel: "Downloading"
        )
        // Fire-and-forget — never blocks the URLSession delegate queue
        Task.detached(priority: .userInitiated) {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end(id: String, success: Bool, downloaded: Int64 = 0) {
        lock.lock()
        let activity = activities[id]
        let dl = lastBytes[id] ?? downloaded
        activities.removeValue(forKey: id)
        lastBytes.removeValue(forKey: id)
        lastTime.removeValue(forKey: id)
        lock.unlock()

        guard let activity = activity else { return }
        let state = DownloadActivityAttributes.ContentState(
            progress: success ? 1.0 : 0.0,
            downloadedBytes: dl,
            totalBytes: 0,
            speedBytesPerSec: 0,
            statusLabel: success ? "Done" : "Failed"
        )
        Task.detached {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(4))
            )
        }
    }

    func hasActivity(id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return activities[id] != nil
    }
}

/// Wrapper so call sites don't need #available checks everywhere.
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

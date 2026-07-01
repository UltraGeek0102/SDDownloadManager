import ActivityKit
import Foundation
import WidgetKit

@available(iOS 16.2, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    // Use an actor-isolated store instead of NSLock so async contexts are safe
    private let store = ActivityStore()

    // MARK: - Public API

    func start(id: String, filename: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            await self.store.setFilename(id: id, filename: filename)

            // End any existing activity for this id
            if let old = await self.store.activity(id: id) {
                await old.end(
                    ActivityContent(
                        state: DownloadActivityAttributes.ContentState(
                            progress: 0, downloadedBytes: 0, totalBytes: 0,
                            speedBytesPerSec: 0, statusLabel: "Stopped"),
                        staleDate: nil),
                    dismissalPolicy: .immediate)
            }

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
                await self.store.setActivity(id: id, activity: act)
                print("[LA] started \(filename)")
            } catch {
                print("[LA] start error: \(error)")
            }
        }
    }

    /// Called from URLSession delegate (didWriteData) — synchronous, fast.
    /// Writes to App Group then wakes widget extension for the reliable background path.
    func update(id: String, progress: Double, downloaded: Int64, total: Int64) {
        // Snapshot state synchronously — this method is called from URLSession thread
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            let filename = await self.store.filename(id: id) ?? ""
            let speed    = await self.store.calculateSpeed(id: id, downloaded: downloaded)
            let activity = await self.store.activity(id: id)

            let state = DownloadActivityAttributes.ContentState(
                progress: min(max(progress, 0), 1),
                downloadedBytes: downloaded, totalBytes: total,
                speedBytesPerSec: speed, statusLabel: "Downloading"
            )
            let content = ActivityContent(state: state, staleDate: nil)

            // Path 1: direct update (works in foreground)
            if let activity = activity {
                await activity.update(content)
            }

            // Path 2: App Group → widget extension (works in background)
            SharedProgressStore.shared.update(
                id: id, filename: filename, progress: progress,
                downloaded: downloaded, total: total, speed: speed
            )
            WidgetCenter.shared.reloadTimelines(ofKind: "DownloadWidget")
        }
    }

    func end(id: String, success: Bool) {
        Task.detached { [weak self] in
            guard let self = self else { return }

            let dl       = await self.store.lastBytes(id: id) ?? 0
            let activity = await self.store.activity(id: id)
            await self.store.removeAll(id: id)

            SharedProgressStore.shared.remove(id: id)
            WidgetCenter.shared.reloadTimelines(ofKind: "DownloadWidget")

            guard let activity = activity else { return }
            let state = DownloadActivityAttributes.ContentState(
                progress: success ? 1.0 : 0.0,
                downloadedBytes: dl, totalBytes: 0, speedBytesPerSec: 0,
                statusLabel: success ? "Done" : "Failed"
            )
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(5))
            )
        }
    }
}

// MARK: - Actor-isolated state store (eliminates NSLock in async contexts)

@available(iOS 16.2, *)
private actor ActivityStore {
    private var activities: [String: Activity<DownloadActivityAttributes>] = [:]
    private var filenames:  [String: String] = [:]
    private var lastBytes:  [String: Int64]  = [:]
    private var lastTimes:  [String: Date]   = [:]

    func activity(id: String) -> Activity<DownloadActivityAttributes>? { activities[id] }
    func setActivity(id: String, activity: Activity<DownloadActivityAttributes>) { activities[id] = activity }
    func filename(id: String) -> String? { filenames[id] }
    func setFilename(id: String, filename: String) { filenames[id] = filename }
    func lastBytes(id: String) -> Int64? { lastBytes[id] }

    func calculateSpeed(id: String, downloaded: Int64) -> Int64 {
        let now     = Date()
        let elapsed = now.timeIntervalSince(lastTimes[id] ?? now)
        let delta   = downloaded - (lastBytes[id] ?? 0)
        let speed   = elapsed > 0.1 ? Int64(Double(max(delta, 0)) / elapsed) : 0
        lastBytes[id] = downloaded
        lastTimes[id]  = now
        return speed
    }

    func removeAll(id: String) {
        activities.removeValue(forKey: id)
        filenames.removeValue(forKey: id)
        lastBytes.removeValue(forKey: id)
        lastTimes.removeValue(forKey: id)
    }
}

// MARK: - Version-safe wrapper

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
    func end(id: String, success: Bool) {
        if #available(iOS 16.2, *) { LiveActivityManager.shared.end(id: id, success: success) }
    }
}

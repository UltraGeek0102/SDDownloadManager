import ActivityKit
import Foundation
import WidgetKit

@available(iOS 16.2, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private let store = ActivityStore()

    // MARK: - Public API

    func start(id: String, filename: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            await self.store.setFilename(id: id, filename: filename)
            if let old = await self.store.activity(id: id) {
                let stopped = DownloadActivityAttributes.ContentState(
                    progress: 0, downloadedBytes: 0, totalBytes: 0,
                    speedBytesPerSec: 0, statusLabel: "Stopped")
                await old.end(ActivityContent(state: stopped, staleDate: nil),
                              dismissalPolicy: .immediate)
            }
            let attrs = DownloadActivityAttributes(downloadId: id, filename: filename)
            let state = DownloadActivityAttributes.ContentState(
                progress: 0, downloadedBytes: 0, totalBytes: 0,
                speedBytesPerSec: 0, statusLabel: "Downloading")
            do {
                let act = try Activity<DownloadActivityAttributes>.request(
                    attributes: attrs,
                    content: ActivityContent(state: state, staleDate: nil))
                await self.store.setActivity(id: id, activity: act)
                print("[LA] started \(filename)")
            } catch { print("[LA] start error: \(error)") }
        }
    }

    /// Called from URLSession delegate thread (always running, never suspended).
    /// CRITICAL: SharedProgressStore.write and WidgetCenter.reloadTimelines are called
    /// SYNCHRONOUSLY here on the URLSession thread — before any async/await.
    /// This guarantees the App Group data is written and the widget is woken
    /// regardless of whether Swift's cooperative pool is suspended in background.
    func update(id: String, progress: Double, downloaded: Int64, total: Int64) {

        // ── Step 1: synchronous, on URLSession thread ─────────────────────────
        // Calculate speed using a simple thread-safe approach
        let speed = store.calculateSpeedSync(id: id, downloaded: downloaded)
        let filename = store.filenameSync(id: id)

        // Write to App Group — synchronous, always works regardless of app state
        SharedProgressStore.shared.update(
            id: id, filename: filename, progress: progress,
            downloaded: downloaded, total: total, speed: speed)

        // Wake widget extension — synchronous call, wakes extension process immediately
        WidgetCenter.shared.reloadTimelines(ofKind: "DownloadWidget")

        // ── Step 2: async direct update (works in foreground / brief bg window) ─
        // This may not execute in background due to cooperative pool suspension,
        // but the App Group path above already handled the background case.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self,
                  let activity = await self.store.activity(id: id) else { return }
            let state = DownloadActivityAttributes.ContentState(
                progress: min(max(progress, 0), 1),
                downloadedBytes: downloaded, totalBytes: total,
                speedBytesPerSec: speed, statusLabel: "Downloading")
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end(id: String, success: Bool) {
        SharedProgressStore.shared.remove(id: id)
        WidgetCenter.shared.reloadTimelines(ofKind: "DownloadWidget")

        Task.detached { [weak self] in
            guard let self = self else { return }
            let dl       = await self.store.lastBytes(id: id) ?? 0
            let activity = await self.store.activity(id: id)
            await self.store.removeAll(id: id)
            guard let activity = activity else { return }
            let state = DownloadActivityAttributes.ContentState(
                progress: success ? 1.0 : 0.0,
                downloadedBytes: dl, totalBytes: 0, speedBytesPerSec: 0,
                statusLabel: success ? "Done" : "Failed")
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(5)))
        }
    }
}

// MARK: - State store (actor-isolated for async contexts + sync accessors for URLSession thread)

@available(iOS 16.2, *)
final class ActivityStore {
    // Use separate NSLock-protected dictionaries for sync access from URLSession thread
    private let syncLock = NSLock()
    private var _filenames:  [String: String] = [:]
    private var _lastBytes:  [String: Int64]  = [:]
    private var _lastTimes:  [String: Date]   = [:]

    // Activities accessed only from async contexts via actor
    private let actorStore = _ActivityActor()

    // MARK: Sync accessors (safe to call from URLSession delegate thread)

    func filenameSync(id: String) -> String {
        syncLock.lock(); defer { syncLock.unlock() }
        return _filenames[id] ?? ""
    }

    func calculateSpeedSync(id: String, downloaded: Int64) -> Int64 {
        syncLock.lock(); defer { syncLock.unlock() }
        let now     = Date()
        let elapsed = now.timeIntervalSince(_lastTimes[id] ?? now)
        let delta   = downloaded - (_lastBytes[id] ?? 0)
        let speed   = elapsed > 0.1 ? Int64(Double(max(delta, 0)) / elapsed) : 0
        _lastBytes[id] = downloaded
        _lastTimes[id] = now
        return speed
    }

    // MARK: Async accessors (for Task.detached contexts)

    func activity(id: String) async -> Activity<DownloadActivityAttributes>? {
        await actorStore.activity(id: id)
    }
    func setActivity(id: String, activity: Activity<DownloadActivityAttributes>) async {
        await actorStore.setActivity(id: id, activity: activity)
    }
    func filename(id: String) async -> String? {
        syncLock.lock(); defer { syncLock.unlock() }
        return _filenames[id]
    }
    func setFilename(id: String, filename: String) async {
        syncLock.lock(); _filenames[id] = filename; syncLock.unlock()
    }
    func lastBytes(id: String) async -> Int64? {
        syncLock.lock(); defer { syncLock.unlock() }
        return _lastBytes[id]
    }
    func removeAll(id: String) async {
        syncLock.lock()
        _filenames.removeValue(forKey: id)
        _lastBytes.removeValue(forKey: id)
        _lastTimes.removeValue(forKey: id)
        syncLock.unlock()
        await actorStore.removeActivity(id: id)
    }
}

private actor _ActivityActor {
    private var activities: [String: Activity<DownloadActivityAttributes>] = [:]
    func activity(id: String) -> Activity<DownloadActivityAttributes>? { activities[id] }
    func setActivity(id: String, activity: Activity<DownloadActivityAttributes>) { activities[id] = activity }
    func removeActivity(id: String) { activities.removeValue(forKey: id) }
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

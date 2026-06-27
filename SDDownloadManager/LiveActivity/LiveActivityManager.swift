import ActivityKit
import Foundation

/// Updates Live Activities reliably from background by driving async calls
/// on a dedicated CFRunLoop thread — bypassing Swift's cooperative thread pool
/// which iOS suspends when the app is backgrounded.
///
/// How it works:
/// - A permanent OS thread runs CFRunLoopRun() — this thread is never suspended
/// - ActivityKit async calls are scheduled onto this thread's RunLoop via
///   CFRunLoopPerformBlock, which executes them regardless of app state
/// - URLSession delegate (didWriteData) calls update() from its own thread,
///   which posts to our RunLoop thread — no cooperative pool involved at all
@available(iOS 16.2, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() { startRunLoopThread() }

    private var activities: [String: Activity<DownloadActivityAttributes>] = [:]
    private var lastBytes:  [String: Int64] = [:]
    private var lastTime:   [String: Date]  = [:]
    private let lock = NSLock()

    // The dedicated RunLoop thread for ActivityKit calls
    private var activityRunLoop: CFRunLoop?
    private let runLoopReady = DispatchSemaphore(value: 0)

    // MARK: - RunLoop thread setup

    private func startRunLoopThread() {
        let t = Thread { [weak self] in
            guard let self = self else { return }
            self.activityRunLoop = CFRunLoopGetCurrent()

            // Add a dummy source so the RunLoop doesn't exit immediately
            var ctx = CFRunLoopSourceContext()
            let src = CFRunLoopSourceCreate(nil, 0, &ctx)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .defaultMode)

            self.runLoopReady.signal()
            CFRunLoopRun() // runs forever on this thread
        }
        t.name = "com.sddownloadmanager.activitykit"
        t.qualityOfService = .userInitiated
        t.start()
        runLoopReady.wait() // block until RunLoop is ready
    }

    /// Post a block onto the ActivityKit RunLoop thread.
    /// Returns immediately — does NOT block the caller.
    private func post(_ block: @escaping () -> Void) {
        guard let rl = activityRunLoop else { block(); return }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.defaultMode.rawValue as CFTypeRef, block)
        CFRunLoopWakeUp(rl)
    }

    // MARK: - Public API

    func start(id: String, filename: String) {
        post { [weak self] in
            guard let self = self,
                  ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            self.lock.lock()
            let existing = self.activities[id]
            self.lock.unlock()

            if let old = existing {
                // Run the async end on our RunLoop thread using a Task
                // The Task here executes on THIS thread's RunLoop — not the cooperative pool
                let sem = DispatchSemaphore(value: 0)
                Task { await old.end(dismissalPolicy: .immediate); sem.signal() }
                sem.wait(timeout: .now() + 2)
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
                self.lock.lock()
                self.activities[id] = activity
                self.lock.unlock()
                print("[LA] started \(id)")
            } catch {
                print("[LA] start error: \(error)")
            }
        }
    }

    func update(id: String, progress: Double, downloaded: Int64, total: Int64) {
        // Called from URLSession delegate thread — post to RunLoop thread immediately
        lock.lock()
        let now     = Date()
        let elapsed = now.timeIntervalSince(lastTime[id] ?? now)
        let delta   = downloaded - (lastBytes[id] ?? 0)
        let speed   = elapsed > 0.1 ? Int64(Double(max(delta, 0)) / elapsed) : 0
        lastBytes[id] = downloaded
        lastTime[id]  = now
        let activity = activities[id]
        lock.unlock()

        guard let activity = activity else { return }

        let state = DownloadActivityAttributes.ContentState(
            progress: min(max(progress, 0), 1),
            downloadedBytes: downloaded,
            totalBytes: total,
            speedBytesPerSec: speed,
            statusLabel: "Downloading"
        )
        let content = ActivityContent(state: state, staleDate: nil)

        // Post onto our dedicated RunLoop thread.
        // The Task created inside CFRunLoopPerformBlock executes on THAT thread's
        // RunLoop, not the cooperative pool — so it runs even when backgrounded.
        post {
            let sem = DispatchSemaphore(value: 0)
            Task {
                await activity.update(content)
                print("[LA] updated \(id) \(String(format:"%.1f",progress*100))%")
                sem.signal()
            }
            // Wait max 2s — keeps updates sequential so they don't pile up
            sem.wait(timeout: .now() + 2)
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
            downloadedBytes: dl, totalBytes: 0, speedBytesPerSec: 0,
            statusLabel: success ? "Done" : "Failed"
        )
        post {
            Task {
                await activity.end(
                    ActivityContent(state: state, staleDate: nil),
                    dismissalPolicy: .after(Date().addingTimeInterval(5))
                )
            }
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

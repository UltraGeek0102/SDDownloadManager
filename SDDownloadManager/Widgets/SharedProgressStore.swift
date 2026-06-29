import Foundation

/// Progress snapshot written by the main app and read by the widget extension.
struct SharedProgress: Codable {
    var id: String
    var filename: String
    var progress: Double        // 0.0–1.0
    var downloadedBytes: Int64
    var totalBytes: Int64
    var speedBytesPerSec: Int64
    var updatedAt: Date
}

/// Thread-safe App Group UserDefaults store.
/// Main app WRITES on every URLSession didWriteData tick.
/// Widget extension READS in getTimeline() and updates Live Activities from there.
final class SharedProgressStore {
    static let shared = SharedProgressStore()
    private init() {}

    private let appGroup = "group.com.ultrageek.downloadmanager"
    private let key      = "com.sddownloadmanager.progress"
    private let lock     = NSLock()

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    // MARK: - Write (main app)

    func update(id: String, filename: String, progress: Double,
                downloaded: Int64, total: Int64, speed: Int64) {
        lock.lock(); defer { lock.unlock() }
        var items = _read()
        let entry = SharedProgress(
            id: id, filename: filename, progress: progress,
            downloadedBytes: downloaded, totalBytes: total,
            speedBytesPerSec: speed, updatedAt: Date()
        )
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx] = entry
        } else {
            items.append(entry)
        }
        _write(items)
    }

    func remove(id: String) {
        lock.lock(); defer { lock.unlock() }
        var items = _read()
        items.removeAll { $0.id == id }
        _write(items)
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        _write([])
    }

    // MARK: - Read (widget extension)

    func read() -> [SharedProgress] {
        lock.lock(); defer { lock.unlock() }
        return _read()
    }

    // MARK: - Private (no locking — caller must hold lock)

    private func _write(_ items: [SharedProgress]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults?.set(data, forKey: key)
        // synchronize() is deprecated but ensures immediate flush to shared container
        // which is critical so the widget extension sees the latest data immediately
        defaults?.synchronize()
    }

    private func _read() -> [SharedProgress] {
        guard
            let data  = defaults?.data(forKey: key),
            let items = try? JSONDecoder().decode([SharedProgress].self, from: data)
        else { return [] }
        return items
    }
}

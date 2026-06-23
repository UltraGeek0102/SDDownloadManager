import Foundation
import Combine

/// Central store for all downloads. Singleton accessed as DownloadStore.shared.
/// ContentView observes this with @StateObject.
final class DownloadStore: ObservableObject {
    static let shared = DownloadStore()

    @Published var active:  [DownloadItem] = []   // queued + downloading + paused
    @Published var history: [DownloadItem] = []   // done + failed

    private let manager = SDDownloadManager.shared
    private let historyKey = "dl_history_v1"

    private init() {
        loadHistory()
        reattachInFlightTasks()
    }

    // MARK: - Add

    func addDownload(urlString: String, filename: String? = nil) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else { return }

        let name = filename?.nilIfEmpty
            ?? url.lastPathComponent.nilIfEmpty
            ?? url.host
            ?? "download"

        // Don't add duplicates that are already active
        if active.contains(where: { $0.id == url.absoluteString }) { return }

        let item = DownloadItem(url: url.absoluteString, filename: name)
        item.status = .queued
        DispatchQueue.main.async { self.active.append(item) }

        manager.downloadFile(
            withRequest: URLRequest(url: url),
            inDirectory: "Downloads",
            withName: name,
            shouldDownloadInBackground: true,
            onProgress: { [weak item] progress, downloaded, total in
                DispatchQueue.main.async {
                    item?.status           = .downloading
                    item?.progress         = Double(progress)
                    item?.downloadedBytes  = downloaded
                    item?.totalBytes       = total
                }
            },
            onCompletion: { [weak self, weak item] error, fileURL in
                guard let self = self, let item = item else { return }
                DispatchQueue.main.async {
                    if let error = error {
                        item.status       = .failed
                        item.errorMessage = error.localizedDescription
                        self.moveToHistory(item)
                    } else {
                        item.status    = .done
                        item.progress  = 1.0
                        item.savedAt   = Date()
                        item.localPath = fileURL?.path
                        self.moveToHistory(item)
                    }
                }
            }
        )
    }

    // MARK: - Controls

    func pause(item: DownloadItem) {
        manager.pauseDownload(forKey: item.id)
        DispatchQueue.main.async { item.status = .paused }
    }

    func resume(item: DownloadItem) {
        let resumed = manager.resumeDownload(
            withKey: item.id,
            inDirectory: "Downloads",
            withName: item.filename,
            onProgress: { [weak item] progress, downloaded, total in
                DispatchQueue.main.async {
                    item?.status          = .downloading
                    item?.progress        = Double(progress)
                    item?.downloadedBytes = downloaded
                    item?.totalBytes      = total
                }
            },
            onCompletion: { [weak self, weak item] error, fileURL in
                guard let self = self, let item = item else { return }
                DispatchQueue.main.async {
                    if let error = error {
                        item.status       = .failed
                        item.errorMessage = error.localizedDescription
                    } else {
                        item.status    = .done
                        item.progress  = 1.0
                        item.savedAt   = Date()
                        item.localPath = fileURL?.path
                    }
                    self.moveToHistory(item)
                }
            }
        )
        if resumed { DispatchQueue.main.async { item.status = .downloading } }
    }

    func cancel(item: DownloadItem) {
        manager.cancelDownload(forKey: item.id)
        DispatchQueue.main.async {
            self.active.removeAll { $0.id == item.id }
        }
    }

    func retry(item: DownloadItem) {
        DispatchQueue.main.async {
            self.history.removeAll { $0.id == item.id }
        }
        saveHistory()
        addDownload(urlString: item.url, filename: item.filename)
    }

    func deleteHistory(item: DownloadItem) {
        DispatchQueue.main.async {
            self.history.removeAll { $0.id == item.id }
        }
        saveHistory()
    }

    func clearHistory() {
        DispatchQueue.main.async { self.history.removeAll() }
        saveHistory()
    }

    // MARK: - Private

    private func moveToHistory(_ item: DownloadItem) {
        DispatchQueue.main.async {
            self.active.removeAll { $0.id == item.id }
            // Avoid duplicates (retry path)
            self.history.removeAll { $0.id == item.id }
            self.history.insert(item, at: 0)
            self.saveHistory()
        }
    }

    /// Re-attach progress/completion callbacks to tasks that survived an app kill.
    /// iOS continues background URLSession tasks even after the app is terminated.
    private func reattachInFlightTasks() {
        let keys = manager.currentDownloadKeys()
        for key in keys {
            guard let url = URL(string: key) else { continue }
            let name = url.lastPathComponent.nilIfEmpty ?? "Download"
            let item = DownloadItem(url: key, filename: name)
            item.status = .downloading
            if !active.contains(where: { $0.id == key }) {
                active.append(item)
            }
            manager.reattach(
                forKey: key,
                onProgress: { [weak item] p, dl, total in
                    DispatchQueue.main.async {
                        item?.status          = .downloading
                        item?.progress        = Double(p)
                        item?.downloadedBytes = dl
                        item?.totalBytes      = total
                    }
                },
                onCompletion: { [weak self, weak item] error, fileURL in
                    guard let self = self, let item = item else { return }
                    DispatchQueue.main.async {
                        if let error = error {
                            item.status = .failed; item.errorMessage = error.localizedDescription
                        } else {
                            item.status = .done; item.progress = 1.0
                            item.savedAt = Date(); item.localPath = fileURL?.path
                        }
                        self.moveToHistory(item)
                    }
                }
            )
        }
    }

    // MARK: - Persistence

    private func saveHistory() {
        let snapshots = history.map { $0.snapshot }
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        guard
            let data = UserDefaults.standard.data(forKey: historyKey),
            let snapshots = try? JSONDecoder().decode([DownloadItem.Snapshot].self, from: data)
        else { return }
        history = snapshots.map { DownloadItem.from($0) }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

import Foundation

/// Primary ViewModel — injected as @EnvironmentObject into all views.
/// Owns active downloads ([DownloadItem]) and history ([DownloadRecord]).
/// Bridges to SDDownloadManager for network operations and DownloadStore for persistence.
final class DownloadsViewModel: ObservableObject {

    static let shared = DownloadsViewModel()

    @Published var activeItems:  [DownloadItem]   = []
    @Published var historyItems: [DownloadRecord] = []

    private let manager = SDDownloadManager.shared
    private let store   = DownloadStore.shared

    private init() {
        loadHistory()
        reattachInFlight()
    }

    // MARK: - Start

    func startDownload(urlString: String, filename: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return }

        let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? url.lastPathComponent.nilIfEmpty
            ?? url.host
            ?? "download"

        let item = DownloadItem(url: trimmed, filename: name)
        item.status = .downloading
        store.add(item)
        DispatchQueue.main.async { self.activeItems.insert(item, at: 0) }

        manager.downloadFile(
            withRequest: URLRequest(url: url),
            inDirectory: "Downloads",
            withName: name,
            shouldDownloadInBackground: true,
            onProgress: { [weak item] progress, downloaded, total in
                DispatchQueue.main.async {
                    item?.status          = .downloading
                    item?.progress        = Double(progress)
                    item?.bytesDownloaded = downloaded
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
                        item.status      = .completed
                        item.progress    = 1.0
                        item.completedAt = Date()
                        item.savedFilePath = fileURL?.path
                    }
                    self.store.save()
                    self.moveToHistory(item)
                }
            }
        )
    }

    // MARK: - Controls

    func pause(item: DownloadItem) {
        manager.pauseDownload(forKey: item.id)
        DispatchQueue.main.async { item.status = .paused }
        store.save()
    }

    func resume(item: DownloadItem) {
        item.status = .downloading
        let resumed = manager.resumeDownload(
            withKey: item.id,
            inDirectory: "Downloads",
            withName: item.filename,
            onProgress: { [weak item] progress, downloaded, total in
                DispatchQueue.main.async {
                    item?.status          = .downloading
                    item?.progress        = Double(progress)
                    item?.bytesDownloaded = downloaded
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
                        item.status        = .completed
                        item.progress      = 1.0
                        item.completedAt   = Date()
                        item.savedFilePath = fileURL?.path
                    }
                    self.store.save()
                    self.moveToHistory(item)
                }
            }
        )
        if !resumed { item.status = .paused }
        store.save()
    }

    func cancel(item: DownloadItem) {
        manager.cancelDownload(forKey: item.id)
        store.remove(id: item.id)
        DispatchQueue.main.async {
            self.activeItems.removeAll { $0.id == item.id }
        }
    }

    func removeHistory(record: DownloadRecord) {
        store.remove(id: record.id)
        DispatchQueue.main.async {
            self.historyItems.removeAll { $0.id == record.id }
        }
    }

    func clearHistory() {
        historyItems.forEach { store.remove(id: $0.id) }
        DispatchQueue.main.async { self.historyItems.removeAll() }
    }

    // MARK: - Private

    private func moveToHistory(_ item: DownloadItem) {
        // Only move if terminal state
        guard item.status == .completed || item.status == .failed else { return }
        activeItems.removeAll { $0.id == item.id }
        let record = DownloadRecord(from: item)
        historyItems.insert(record, at: 0)
    }

    private func loadHistory() {
        historyItems = store.items
            .filter { $0.status == .completed || $0.status == .failed }
            .map { DownloadRecord(from: $0) }
    }

    /// Re-attach callbacks to URLSession tasks that survived an app restart.
    private func reattachInFlight() {
        let keys = manager.currentDownloadKeys()
        for key in keys {
            // Restore item from store or create a placeholder
            let existing = store.item(forId: key)
            let item: DownloadItem
            if let e = existing, e.status == .downloading || e.status == .paused {
                item = e
            } else {
                let name = URL(string: key)?.lastPathComponent.nilIfEmpty ?? "Download"
                item = DownloadItem(url: key, filename: name)
            }
            item.status = .downloading
            if !activeItems.contains(where: { $0.id == key }) {
                activeItems.append(item)
            }
            manager.reattach(
                forKey: key,
                onProgress: { [weak item] p, dl, total in
                    DispatchQueue.main.async {
                        item?.status          = .downloading
                        item?.progress        = Double(p)
                        item?.bytesDownloaded = dl
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
                            item.status        = .completed
                            item.progress      = 1.0
                            item.completedAt   = Date()
                            item.savedFilePath = fileURL?.path
                        }
                        self.store.save()
                        self.moveToHistory(item)
                    }
                }
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

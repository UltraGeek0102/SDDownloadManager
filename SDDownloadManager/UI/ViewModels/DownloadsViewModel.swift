import Foundation

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
                // All mutations on main thread — DownloadItem is ObservableObject
                DispatchQueue.main.async {
                    item?.status          = .downloading
                    item?.progress        = Double(progress)
                    item?.bytesDownloaded = downloaded
                    item?.totalBytes      = total
                    // Speed is computed inside SDDownloadManager but not passed here.
                    // We calculate it from successive progress calls instead.
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
                        item.speedBytesPerSec = 0
                        item.completedAt   = Date()
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
        manager.pauseDownload(forKey: item.url)
        DispatchQueue.main.async {
            item.status = .paused
            item.speedBytesPerSec = 0
        }
        store.save()
    }

    func resume(item: DownloadItem) {
        DispatchQueue.main.async { item.status = .downloading }
        let resumed = manager.resumeDownload(
            withKey: item.url,
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
                        item.speedBytesPerSec = 0
                        item.completedAt   = Date()
                        item.savedFilePath = fileURL?.path
                    }
                    self.store.save()
                    self.moveToHistory(item)
                }
            }
        )
        if !resumed {
            DispatchQueue.main.async { item.status = .paused }
        }
        store.save()
    }

    func cancel(item: DownloadItem) {
        manager.cancelDownload(forKey: item.url)
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
        guard item.status == .completed || item.status == .failed else { return }
        activeItems.removeAll { $0.id == item.id }
        historyItems.insert(DownloadRecord(from: item), at: 0)
    }

    private func loadHistory() {
        historyItems = store.items
            .filter { $0.status == .completed || $0.status == .failed }
            .map { DownloadRecord(from: $0) }
    }

    private func reattachInFlight() {
        let keys = manager.currentDownloadKeys()
        for key in keys {
            let item: DownloadItem
            if let e = store.item(forId: key), e.status == .downloading || e.status == .paused {
                item = e
            } else {
                item = DownloadItem(url: key,
                                   filename: URL(string: key)?.lastPathComponent.nilIfEmpty ?? "Download")
            }
            item.status = .downloading
            if !activeItems.contains(where: { $0.id == item.id }) {
                activeItems.append(item)
            }
            manager.reattach(
                forKey: key,
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
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

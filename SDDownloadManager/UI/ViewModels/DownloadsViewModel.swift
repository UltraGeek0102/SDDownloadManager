import Foundation
import Combine

final class DownloadsViewModel: ObservableObject {

    // MARK: - Published state

    @Published var activeDownloads:    [DownloadRecord] = []
    @Published var completedDownloads: [DownloadRecord] = []

    // MARK: - Private

    private let manager = SDDownloadManager.shared
    private let persistenceKey = "download_history"

    // MARK: - Init

    init() {
        loadHistory()
        restoreActiveDownloads()
    }

    // MARK: - Add download

    func addDownload(urlString: String, customName: String? = nil) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            return false
        }

        let filename = customName?.isEmpty == false
            ? customName!
            : url.lastPathComponent.isEmpty ? url.host ?? "download" : url.lastPathComponent

        var record = DownloadRecord(
            id: url.absoluteString,
            filename: filename,
            url: url.absoluteString,
            status: .downloading,
            progress: 0,
            downloadedBytes: 0,
            totalBytes: 0,
            speedBytesPerSec: 0,
            startedAt: Date(),
            completedAt: nil,
            localPath: nil
        )

        DispatchQueue.main.async { self.activeDownloads.append(record) }

        let request = URLRequest(url: url)
        manager.downloadFile(
            withRequest: request,
            inDirectory: "Downloads",
            withName: filename,
            shouldDownloadInBackground: true,
            onProgress: { [weak self] progress, downloaded, total in
                self?.updateRecord(id: url.absoluteString) {
                    $0.progress         = Double(progress)
                    $0.downloadedBytes  = downloaded
                    $0.totalBytes       = total
                    $0.speedBytesPerSec = 0 // reported by Live Activity; skip here
                    $0.status           = .downloading
                }
            },
            onCompletion: { [weak self] error, fileURL in
                guard let self = self else { return }
                if let error = error {
                    self.updateRecord(id: url.absoluteString) { $0.status = .failed }
                    print("[VM] download failed: \(error)")
                } else {
                    self.updateRecord(id: url.absoluteString) {
                        $0.status      = .completed
                        $0.progress    = 1.0
                        $0.completedAt = Date()
                        $0.localPath   = fileURL?.path
                    }
                    self.moveToHistory(id: url.absoluteString)
                }
            }
        )
        return true
    }

    // MARK: - Controls

    func pauseDownload(id: String) {
        manager.pauseDownload(forKey: id)
        updateRecord(id: id) { $0.status = .paused }
    }

    func resumeDownload(id: String) {
        guard let record = findRecord(id: id) else { return }
        let resumed = manager.resumeDownload(
            withKey: id,
            inDirectory: "Downloads",
            withName: record.filename,
            onProgress: { [weak self] progress, downloaded, total in
                self?.updateRecord(id: id) {
                    $0.progress        = Double(progress)
                    $0.downloadedBytes = downloaded
                    $0.totalBytes      = total
                    $0.status          = .downloading
                }
            },
            onCompletion: { [weak self] error, fileURL in
                guard let self = self else { return }
                if error != nil {
                    self.updateRecord(id: id) { $0.status = .failed }
                } else {
                    self.updateRecord(id: id) {
                        $0.status = .completed; $0.progress = 1.0
                        $0.completedAt = Date(); $0.localPath = fileURL?.path
                    }
                    self.moveToHistory(id: id)
                }
            }
        )
        if resumed { updateRecord(id: id) { $0.status = .downloading } }
    }

    func cancelDownload(id: String) {
        manager.cancelDownload(forKey: id)
        DispatchQueue.main.async {
            self.activeDownloads.removeAll { $0.id == id }
        }
    }

    func clearHistory() {
        DispatchQueue.main.async { self.completedDownloads.removeAll() }
        saveHistory()
    }

    func removeHistoryItem(id: String) {
        DispatchQueue.main.async {
            self.completedDownloads.removeAll { $0.id == id }
        }
        saveHistory()
    }

    // MARK: - Helpers

    private func updateRecord(id: String, mutations: (inout DownloadRecord) -> Void) {
        DispatchQueue.main.async {
            if let idx = self.activeDownloads.firstIndex(where: { $0.id == id }) {
                mutations(&self.activeDownloads[idx])
            } else if let idx = self.completedDownloads.firstIndex(where: { $0.id == id }) {
                mutations(&self.completedDownloads[idx])
                self.saveHistory()
            }
        }
    }

    private func findRecord(id: String) -> DownloadRecord? {
        activeDownloads.first(where: { $0.id == id })
            ?? completedDownloads.first(where: { $0.id == id })
    }

    private func moveToHistory(id: String) {
        DispatchQueue.main.async {
            if let record = self.activeDownloads.first(where: { $0.id == id }) {
                self.activeDownloads.removeAll { $0.id == id }
                self.completedDownloads.insert(record, at: 0)
                self.saveHistory()
            }
        }
    }

    private func restoreActiveDownloads() {
        // Re-attach callbacks to any background session tasks that survived
        // an app restart (iOS continues background downloads even after kill)
        let inFlight = manager.currentDownloadKeys()
        for key in inFlight {
            guard let url = URL(string: key) else { continue }
            let filename = url.lastPathComponent.isEmpty ? "Download" : url.lastPathComponent
            var record = DownloadRecord(
                id: key, filename: filename, url: key,
                status: .downloading, progress: 0,
                downloadedBytes: 0, totalBytes: 0, speedBytesPerSec: 0,
                startedAt: Date(), completedAt: nil, localPath: nil
            )
            if !activeDownloads.contains(where: { $0.id == key }) {
                activeDownloads.append(record)
            }
            manager.reattach(
                forKey: key,
                onProgress: { [weak self] progress, downloaded, total in
                    self?.updateRecord(id: key) {
                        $0.progress = Double(progress); $0.downloadedBytes = downloaded; $0.totalBytes = total
                    }
                },
                onCompletion: { [weak self] error, fileURL in
                    guard let self = self else { return }
                    if error != nil { self.updateRecord(id: key) { $0.status = .failed } }
                    else {
                        self.updateRecord(id: key) {
                            $0.status = .completed; $0.progress = 1.0
                            $0.completedAt = Date(); $0.localPath = fileURL?.path
                        }
                        self.moveToHistory(id: key)
                    }
                }
            )
        }
    }

    // MARK: - Persistence

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(completedDownloads) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let records = try? JSONDecoder().decode([DownloadRecord].self, from: data)
        else { return }
        completedDownloads = records
    }
}

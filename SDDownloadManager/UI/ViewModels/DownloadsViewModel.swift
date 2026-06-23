import Foundation
import Combine

class DownloadsViewModel: ObservableObject {
    static let shared = DownloadsViewModel()

    @Published var activeItems:  [DownloadItem] = []
    @Published var historyItems: [DownloadRecord] = []

    private var cancellables = Set<AnyCancellable>()

    private init() {
        reload()
        // Observe download events
        NotificationCenter.default
            .publisher(for: .downloadProgressUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadActive() }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: .downloadStateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    func reload() {
        reloadActive()
        reloadHistory()
    }

    private func reloadActive() {
        activeItems = DownloadStore.shared.items.filter {
            $0.status == .downloading || $0.status == .paused ||
            $0.status == .queued     || $0.status == .failed
        }
    }

    private func reloadHistory() {
        historyItems = DownloadStore.shared.items
            .filter { $0.status == .completed }
            .map { DownloadRecord(from: $0) }
    }

    // MARK: - Actions

    func startDownload(urlString: String, filename: String?) {
        SDDownloadManager.shared.downloadFile(
            urlString: urlString,
            filename: filename?.isEmpty == true ? nil : filename,
            inDirectory: "Downloads"
        ) { [weak self] _, _ in
            DispatchQueue.main.async { self?.reload() }
        }
        reload()
    }

    func pause(item: DownloadItem) {
        SDDownloadManager.shared.pause(id: item.id)
    }

    func resume(item: DownloadItem) {
        SDDownloadManager.shared.resume(id: item.id) { [weak self] _, _ in
            DispatchQueue.main.async { self?.reload() }
        }
    }

    func cancel(item: DownloadItem) {
        SDDownloadManager.shared.cancel(id: item.id)
        reload()
    }

    func clearHistory() {
        historyItems.forEach { DownloadStore.shared.remove(id: $0.id) }
        reload()
    }

    func removeHistory(record: DownloadRecord) {
        DownloadStore.shared.remove(id: record.id)
        reload()
    }
}

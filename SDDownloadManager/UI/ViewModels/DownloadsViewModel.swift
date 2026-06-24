import Foundation
import Combine

/// Bridges DownloadStore to the views that use DownloadsViewModel.
/// ActiveDownloadsView and AddDownloadView are typed against this class.
/// All real logic lives in DownloadStore — this is a thin facade.
final class DownloadsViewModel: ObservableObject {

    static let shared = DownloadsViewModel()

    /// Active downloads (queued + downloading + paused + failed).
    /// Sourced from DownloadStore.shared.active — kept in sync via Combine.
    @Published var activeDownloads: [DownloadRecord] = []

    private var cancellables = Set<AnyCancellable>()
    private let store = DownloadStore.shared

    private init() {
        // Mirror DownloadStore.active (which holds DownloadItem) as DownloadRecord
        // so ActiveDownloadsView's List(vm.activeDownloads) gets the right type.
        store.$active
            .map { items in items.map { DownloadRecord(item: $0) } }
            .receive(on: DispatchQueue.main)
            .assign(to: \.activeDownloads, on: self)
            .store(in: &cancellables)
    }

    // MARK: - API used by views

    /// Returns true if the download was started; false if the URL was invalid.
    @discardableResult
    func addDownload(urlString: String, customName: String? = nil) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            return false
        }
        store.addDownload(urlString: trimmed, filename: customName)
        return true
    }

    func pauseDownload(id: String) {
        guard let item = store.active.first(where: { $0.id == id }) else { return }
        store.pause(item: item)
    }

    func resumeDownload(id: String) {
        guard let item = store.active.first(where: { $0.id == id }) else { return }
        store.resume(item: item)
    }

    func cancelDownload(id: String) {
        guard let item = store.active.first(where: { $0.id == id }) else { return }
        store.cancel(item: item)
    }
}

// MARK: - DownloadRecord from DownloadItem

/// Converts a DownloadItem (ObservableObject) to a DownloadRecord (struct) for
/// the ActiveDownloadsView list. Updates whenever DownloadStore.active changes.
extension DownloadRecord {
    init(item: DownloadItem) {
        self.id               = item.id
        self.filename         = item.filename
        self.url              = item.url
        self.status           = DownloadStatus(itemStatus: item.status)
        self.progress         = item.progress
        self.downloadedBytes  = item.downloadedBytes
        self.totalBytes       = item.totalBytes
        self.speedBytesPerSec = item.speedBytesPerSec
        self.startedAt        = item.addedAt
        self.completedAt      = item.savedAt
        self.localPath        = item.localPath
    }
}

extension DownloadStatus {
    init(itemStatus: DownloadItemStatus) {
        switch itemStatus {
        case .queued:      self = .downloading  // treat queued as downloading in the record
        case .downloading: self = .downloading
        case .paused:      self = .paused
        case .done:        self = .completed
        case .failed:      self = .failed
        }
    }
}

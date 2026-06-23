import Foundation

enum DownloadItemStatus: String {
    case queued, downloading, paused, done, failed
}

/// Observable per-download model. Each instance is an @ObservedObject in the list rows,
/// so only the changed row re-renders rather than the whole list.
final class DownloadItem: ObservableObject, Identifiable {
    let id: String          // URL string — stable identity
    let url: String
    let addedAt: Date

    @Published var filename:         String
    @Published var status:           DownloadItemStatus
    @Published var progress:         Double  // 0.0 – 1.0
    @Published var downloadedBytes:  Int64
    @Published var totalBytes:       Int64
    @Published var speedBytesPerSec: Int64
    @Published var errorMessage:     String?
    @Published var savedAt:          Date?
    @Published var localPath:        String?

    var canResume: Bool {
        status == .paused &&
        UserDefaults.standard.data(forKey: "resume_\(id)") != nil
    }

    init(url: String, filename: String) {
        self.id       = url
        self.url      = url
        self.filename = filename
        self.addedAt  = Date()
        self.status   = .queued
        self.progress         = 0
        self.downloadedBytes  = 0
        self.totalBytes       = 0
        self.speedBytesPerSec = 0
    }

    // Codable persistence shim
    struct Snapshot: Codable {
        let id, url, filename: String
        let addedAt: Date
        let status: String
        let progress: Double
        let downloadedBytes, totalBytes: Int64
        let errorMessage: String?
        let savedAt: Date?
        let localPath: String?
    }

    var snapshot: Snapshot {
        Snapshot(id: id, url: url, filename: filename, addedAt: addedAt,
                 status: status.rawValue, progress: progress,
                 downloadedBytes: downloadedBytes, totalBytes: totalBytes,
                 errorMessage: errorMessage, savedAt: savedAt, localPath: localPath)
    }

    static func from(_ s: Snapshot) -> DownloadItem {
        let item          = DownloadItem(url: s.url, filename: s.filename)
        item.status       = DownloadItemStatus(rawValue: s.status) ?? .failed
        item.progress     = s.progress
        item.downloadedBytes  = s.downloadedBytes
        item.totalBytes       = s.totalBytes
        item.errorMessage     = s.errorMessage
        item.savedAt          = s.savedAt
        item.localPath        = s.localPath
        return item
    }
}

import Foundation

/// Immutable record of a completed or failed download, stored in history.
struct DownloadRecord: Identifiable, Codable {
    let id: String
    let url: String
    let filename: String
    let status: DownloadStatus
    let savedFilePath: String?
    let errorMessage: String?
    let totalBytes: Int64
    let completedAt: Date
    let createdAt: Date

    init(from item: DownloadItem) {
        self.id            = item.id
        self.url           = item.url
        self.filename      = item.filename
        self.status        = item.status
        self.savedFilePath = item.savedFilePath
        self.errorMessage  = item.errorMessage
        self.totalBytes    = item.totalBytes
        self.completedAt   = item.completedAt ?? Date()
        self.createdAt     = item.createdAt
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: completedAt)
    }
}

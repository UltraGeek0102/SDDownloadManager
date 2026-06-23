import Foundation

enum DownloadStatus: String, Codable {
    case queued, downloading, paused, completed, failed
}

class DownloadItem: Identifiable, Codable {
    let id: String
    let url: String
    var filename: String
    var status: DownloadStatus
    var progress: Double
    var bytesDownloaded: Int64
    var totalBytes: Int64
    var speedBytesPerSec: Int64
    var savedFilePath: String?
    var errorMessage: String?
    let createdAt: Date
    var completedAt: Date?

    init(url: String, filename: String) {
        self.id               = UUID().uuidString
        self.url              = url
        self.filename         = filename
        self.status           = .queued
        self.progress         = 0
        self.bytesDownloaded  = 0
        self.totalBytes       = 0
        self.speedBytesPerSec = 0
        self.createdAt        = Date()
    }

    var formattedProgress: String { String(format: "%.1f%%", progress * 100) }

    var formattedSize: String {
        if totalBytes <= 0 { return formatBytes(bytesDownloaded) }
        return "\(formatBytes(bytesDownloaded)) / \(formatBytes(totalBytes))"
    }

    var formattedSpeed: String {
        guard speedBytesPerSec > 0 else { return "" }
        return "\(formatBytes(speedBytesPerSec))/s"
    }

    private func formatBytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

import Foundation

enum DownloadStatus: String, Codable {
    case downloading, paused, completed, failed
}

struct DownloadRecord: Identifiable, Codable {
    let id: String           // URL string — unique key used throughout
    var filename: String
    var url: String
    var status: DownloadStatus
    var progress: Double     // 0.0 – 1.0
    var downloadedBytes: Int64
    var totalBytes: Int64
    var speedBytesPerSec: Int64
    var startedAt: Date
    var completedAt: Date?
    var localPath: String?   // absolute path after completion

    var displaySize: String {
        totalBytes > 0 ? ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) : "Unknown size"
    }

    var displaySpeed: String {
        guard speedBytesPerSec > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: speedBytesPerSec, countStyle: .file) + "/s"
    }

    var displayProgress: String {
        String(format: "%.1f%%", progress * 100)
    }

    var canResume: Bool {
        status == .paused && UserDefaults.standard.data(forKey: "resume_\(id)") != nil
    }
}

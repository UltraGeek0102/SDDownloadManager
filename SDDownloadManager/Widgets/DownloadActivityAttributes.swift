import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct DownloadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var progress: Double        // 0.0 – 1.0
        var downloadedBytes: Int64
        var totalBytes: Int64
        var speedBytesPerSec: Int64
        var statusLabel: String     // "Downloading" | "Done" | "Failed" | "Paused"
    }

    var downloadId: String
    var filename: String
}

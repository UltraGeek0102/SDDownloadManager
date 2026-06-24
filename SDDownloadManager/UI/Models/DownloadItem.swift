import Foundation

enum DownloadStatus: String, Codable {
    case queued, downloading, paused, completed, failed
}

/// ObservableObject so SwiftUI views re-render when any @Published property changes.
final class DownloadItem: ObservableObject, Identifiable, Codable {
    let id: String
    let url: String
    @Published var filename: String
    @Published var status: DownloadStatus
    @Published var progress: Double
    @Published var bytesDownloaded: Int64
    @Published var totalBytes: Int64
    @Published var speedBytesPerSec: Int64
    @Published var savedFilePath: String?
    @Published var errorMessage: String?
    let createdAt: Date
    @Published var completedAt: Date?

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

    // MARK: - Codable (manual because @Published + Codable need it)

    enum CodingKeys: String, CodingKey {
        case id, url, filename, status, progress, bytesDownloaded, totalBytes
        case speedBytesPerSec, savedFilePath, errorMessage, createdAt, completedAt
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(String.self,         forKey: .id)
        url              = try c.decode(String.self,         forKey: .url)
        filename         = try c.decode(String.self,         forKey: .filename)
        status           = try c.decode(DownloadStatus.self, forKey: .status)
        progress         = try c.decode(Double.self,         forKey: .progress)
        bytesDownloaded  = try c.decode(Int64.self,          forKey: .bytesDownloaded)
        totalBytes       = try c.decode(Int64.self,          forKey: .totalBytes)
        speedBytesPerSec = try c.decode(Int64.self,          forKey: .speedBytesPerSec)
        savedFilePath    = try c.decodeIfPresent(String.self, forKey: .savedFilePath)
        errorMessage     = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        createdAt        = try c.decode(Date.self,            forKey: .createdAt)
        completedAt      = try c.decodeIfPresent(Date.self,   forKey: .completedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,               forKey: .id)
        try c.encode(url,              forKey: .url)
        try c.encode(filename,         forKey: .filename)
        try c.encode(status,           forKey: .status)
        try c.encode(progress,         forKey: .progress)
        try c.encode(bytesDownloaded,  forKey: .bytesDownloaded)
        try c.encode(totalBytes,       forKey: .totalBytes)
        try c.encode(speedBytesPerSec, forKey: .speedBytesPerSec)
        try c.encodeIfPresent(savedFilePath, forKey: .savedFilePath)
        try c.encodeIfPresent(errorMessage,  forKey: .errorMessage)
        try c.encode(createdAt,        forKey: .createdAt)
        try c.encodeIfPresent(completedAt,   forKey: .completedAt)
    }
}

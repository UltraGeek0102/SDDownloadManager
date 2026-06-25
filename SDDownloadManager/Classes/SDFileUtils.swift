import UIKit

class SDFileUtils: NSObject {

    // MARK: - File saving

    /// Saves a downloaded file to the app's Documents/[directory]/ folder.
    /// Uses copy (not move) because sideloaded app sandbox restrictions can prevent
    /// moving temp files that background URLSession places in system-managed locations.
    static func saveFile(fromUrl url: URL,
                         toDirectory directory: String?,
                         withName name: String) -> (Bool, Error?, URL?)
    {
        // Resolve a safe, non-empty filename
        let finalName = resolvedFilename(from: name)

        // Ensure destination directory exists
        let destDir: URL
        if let dir = directory, !dir.isEmpty {
            let base = documentsDirectoryPath().appendingPathComponent(dir)
            do {
                try FileManager.default.createDirectory(
                    at: base, withIntermediateDirectories: true, attributes: nil)
                destDir = base
            } catch {
                return (false, error, nil)
            }
        } else {
            destDir = documentsDirectoryPath()
        }

        let destURL = destDir.appendingPathComponent(finalName)

        // Remove existing file with same name
        if FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.removeItem(at: destURL)
        }

        // Try move first, then copy as fallback.
        // Background URLSession temp files on sideloaded apps may only support copy.
        do {
            try FileManager.default.moveItem(at: url, to: destURL)
            return (true, nil, destURL)
        } catch {
            do {
                try FileManager.default.copyItem(at: url, to: destURL)
                return (true, nil, destURL)
            } catch let copyErr {
                // Return the copy error with context about source and dest
                let msg = "Save failed: \(copyErr.localizedDescription)\nSource: \(url.path)\nDest: \(destURL.path)"
                let err = NSError(domain: "SDFileUtils", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: msg])
                return (false, err, nil)
            }
        }
    }

    // MARK: - Backwards-compat alias used by existing call sites
    static func moveFile(fromUrl url: URL,
                         toDirectory directory: String?,
                         withName name: String) -> (Bool, Error?, URL?)
    {
        saveFile(fromUrl: url, toDirectory: directory, withName: name)
    }

    // MARK: - Helpers

    /// Documents directory — visible in Files app when UIFileSharingEnabled = YES
    static func documentsDirectoryPath() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func createDirectoryIfNotExists(withName name: String) -> (Bool, Error?) {
        guard !name.isEmpty else {
            return (false, NSError(domain: "SDFileUtils", code: 2,
                                   userInfo: [NSLocalizedDescriptionKey: "Directory name cannot be empty"]))
        }
        let url = documentsDirectoryPath().appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else { return (true, nil) }
        do {
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true, attributes: nil)
            return (true, nil)
        } catch {
            return (false, error)
        }
    }

    /// Returns a safe, non-empty filename.
    /// - Strips URL query string component
    /// - Removes filesystem-illegal characters
    /// - Falls back to a timestamp name if nothing usable remains
    static func resolvedFilename(from raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip query string (e.g. "file.mp4?token=abc" → "file.mp4")
        if let q = name.firstIndex(of: "?") { name = String(name[..<q]) }
        if let q = name.firstIndex(of: "#") { name = String(name[..<q]) }

        // Remove filesystem-illegal characters
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        name = name.components(separatedBy: illegal).joined(separator: "_")
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)

        return name.isEmpty ? "download_\(Int(Date().timeIntervalSince1970))" : name
    }
}

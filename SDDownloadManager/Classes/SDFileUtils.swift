import UIKit

class SDFileUtils: NSObject {

    // MARK: - Write from memory (preferred — no temp file dependency)

    /// Write file data directly to Documents/[directory]/[name].
    /// Called with data already loaded into memory, so there's no temp file
    /// path that can expire or be inaccessible due to sandbox restrictions.
    static func writeData(_ data: Data,
                          toDirectory directory: String?,
                          withName name: String) -> (Bool, Error?, URL?)
    {
        let finalName = resolvedFilename(from: name)
        let destDir   = resolvedDirectory(directory)

        guard let destDir = destDir.0 else {
            return (false, destDir.1, nil)
        }

        let destURL = destDir.appendingPathComponent(finalName)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.removeItem(at: destURL)
        }

        do {
            try data.write(to: destURL, options: .atomic)
            print("[FileUtils] wrote \(data.count) bytes → \(destURL.path)")
            return (true, nil, destURL)
        } catch {
            print("[FileUtils] write failed: \(error)")
            return (false, error, nil)
        }
    }

    // MARK: - Move/copy from temp URL (fallback)

    static func saveFile(fromUrl url: URL,
                         toDirectory directory: String?,
                         withName name: String) -> (Bool, Error?, URL?)
    {
        // If we can read the file into memory, use writeData for reliability
        if let data = try? Data(contentsOf: url) {
            return writeData(data, toDirectory: directory, withName: name)
        }

        // Last resort: try move then copy
        let finalName = resolvedFilename(from: name)
        let destDir   = resolvedDirectory(directory)
        guard let dir = destDir.0 else { return (false, destDir.1, nil) }
        let destURL = dir.appendingPathComponent(finalName)

        if FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.removeItem(at: destURL)
        }

        do {
            try FileManager.default.moveItem(at: url, to: destURL)
            return (true, nil, destURL)
        } catch {
            do {
                try FileManager.default.copyItem(at: url, to: destURL)
                return (true, nil, destURL)
            } catch let e {
                return (false, e, nil)
            }
        }
    }

    // backwards-compat alias
    static func moveFile(fromUrl url: URL,
                         toDirectory directory: String?,
                         withName name: String) -> (Bool, Error?, URL?)
    {
        saveFile(fromUrl: url, toDirectory: directory, withName: name)
    }

    // MARK: - Helpers

    static func documentsDirectoryPath() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func createDirectoryIfNotExists(withName name: String) -> (Bool, Error?) {
        let url = documentsDirectoryPath().appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else { return (true, nil) }
        do {
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true, attributes: nil)
            return (true, nil)
        } catch { return (false, error) }
    }

    /// Strips query strings and illegal filesystem characters from a filename.
    static func resolvedFilename(from raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let q = name.firstIndex(of: "?") { name = String(name[..<q]) }
        if let q = name.firstIndex(of: "#") { name = String(name[..<q]) }
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        name = name.components(separatedBy: illegal).joined(separator: "_")
                   .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "download_\(Int(Date().timeIntervalSince1970))" : name
    }

    // MARK: - Private

    private static func resolvedDirectory(_ directory: String?) -> (URL?, Error?) {
        let base = documentsDirectoryPath()
        guard let dir = directory, !dir.isEmpty else { return (base, nil) }
        let url = base.appendingPathComponent(dir)
        do {
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true, attributes: nil)
            return (url, nil)
        } catch {
            return (nil, error)
        }
    }
}

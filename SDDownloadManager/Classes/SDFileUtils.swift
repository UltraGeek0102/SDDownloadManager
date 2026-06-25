import UIKit

class SDFileUtils: NSObject {

    // MARK: - File moving

    static func moveFile(fromUrl url: URL,
                         toDirectory directory: String?,
                         withName name: String) -> (Bool, Error?, URL?)
    {
        guard !name.isEmpty else {
            return (false, makeError("File name cannot be empty"), nil)
        }

        // Sanitise filename — remove characters that are illegal on iOS filesystem
        let safeName = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:"))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = safeName.isEmpty ? "download_\(Int(Date().timeIntervalSince1970))" : safeName

        let destinationDir: URL
        if let directory = directory, !directory.isEmpty {
            let result = createDirectoryIfNotExists(withName: directory)
            guard result.0 else { return (false, result.1, nil) }
            destinationDir = documentsDirectoryPath().appendingPathComponent(directory)
        } else {
            destinationDir = documentsDirectoryPath()
        }

        let newUrl = destinationDir.appendingPathComponent(finalName)

        do {
            if FileManager.default.fileExists(atPath: newUrl.path) {
                try FileManager.default.removeItem(at: newUrl)
            }
            try FileManager.default.moveItem(at: url, to: newUrl)
            return (true, nil, newUrl)
        } catch {
            // Move failed — try copying as fallback (background session temp files
            // can sometimes only be copied, not moved)
            do {
                try FileManager.default.copyItem(at: url, to: newUrl)
                return (true, nil, newUrl)
            } catch let copyError {
                return (false, copyError, nil)
            }
        }
    }

    // MARK: - Directory helpers

    /// Documents directory — visible in Files app under "On My iPhone > AppName"
    /// when UIFileSharingEnabled = YES and LSSupportsOpeningDocumentsInPlace = YES
    /// are set in Info.plist (added by this fix).
    static func documentsDirectoryPath() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func createDirectoryIfNotExists(withName name: String) -> (Bool, Error?) {
        guard !name.isEmpty else {
            return (false, makeError("Directory name cannot be empty"))
        }
        let url = documentsDirectoryPath().appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else { return (true, nil) }
        do {
            try FileManager.default.createDirectory(at: url,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
            return (true, nil)
        } catch {
            return (false, error)
        }
    }

    private static func makeError(_ msg: String) -> NSError {
        NSError(domain: "SDFileUtils", code: 1,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }
}

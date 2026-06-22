import UIKit
import UserNotifications

public final class SDDownloadManager: NSObject {

    // MARK: - Types

    public typealias DownloadCompletionBlock    = (_ error: Error?, _ fileUrl: URL?) -> Void
    public typealias DownloadProgressBlock      = (_ progress: CGFloat, _ downloaded: Int64, _ total: Int64) -> Void
    public typealias BackgroundDownloadCompletionHandler = () -> Void

    // MARK: - Singleton

    public static let shared = SDDownloadManager()

    // MARK: - Properties

    private let downloadQueue = DispatchQueue(label: "com.sddownloadmanager.queue", attributes: .concurrent)
    private var _ongoingDownloads: [String: SDDownloadObject] = [:]
    private var ongoingDownloads: [String: SDDownloadObject] {
        get    { downloadQueue.sync { _ongoingDownloads } }
        set    { downloadQueue.async(flags: .barrier) { self._ongoingDownloads = newValue } }
    }

    private var session:           URLSession!
    private var backgroundSession: URLSession!

    public var backgroundCompletionHandler: BackgroundDownloadCompletionHandler?
    public var showLocalNotificationOnBackgroundDownloadDone = true
    public var localNotificationText: String?

    // MARK: - Init

    override private init() {
        super.init()
        let defaultConfig = URLSessionConfiguration.default
        session = URLSession(configuration: defaultConfig, delegate: self, delegateQueue: nil)

        let bgConfig = URLSessionConfiguration.background(withIdentifier: Bundle.main.bundleIdentifier! + ".download")
        bgConfig.isDiscretionary = false
        bgConfig.sessionSendsLaunchEvents = true
        backgroundSession = URLSession(configuration: bgConfig, delegate: self, delegateQueue: nil)
    }

    // MARK: - Public API

    /// Start a download.
    /// - Parameters:
    ///   - request: The URLRequest to download.
    ///   - directory: Subdirectory within Caches to save the file.
    ///   - fileName: Override filename; defaults to suggested filename from response.
    ///   - shouldDownloadInBackground: Use background URLSession (survives app suspension).
    ///   - progressBlock: Called with (fraction 0-1, bytesDownloaded, totalBytes).
    ///   - completionBlock: Called on completion with error or final file URL.
    /// - Returns: A unique key identifying this download, or nil if already in progress.
    @discardableResult
    public func downloadFile(withRequest request: URLRequest,
                             inDirectory directory: String? = nil,
                             withName fileName: String? = nil,
                             shouldDownloadInBackground: Bool = true,
                             onProgress progressBlock: DownloadProgressBlock? = nil,
                             onCompletion completionBlock: @escaping DownloadCompletionBlock) -> String?
    {
        guard let url = request.url else {
            completionBlock(NSError(domain: "SDDownloadManager", code: 0,
                                   userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]), nil)
            return nil
        }

        let key = url.absoluteString
        if isDownloadInProgress(forKey: key) {
            completionBlock(NSError(domain: "SDDownloadManager", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: "Already in progress"]), nil)
            return nil
        }

        let task = shouldDownloadInBackground
            ? backgroundSession.downloadTask(with: request)
            : session.downloadTask(with: request)

        let obj = SDDownloadObject(downloadTask: task,
                                   progressBlock: progressBlock,
                                   completionBlock: completionBlock,
                                   fileName: fileName,
                                   directoryName: directory)
        downloadQueue.async(flags: .barrier) { self._ongoingDownloads[key] = obj }

        // Start Live Activity
        let name = fileName ?? url.lastPathComponent.isEmpty ? url.host ?? "Download" : url.lastPathComponent
        LiveActivityBridge.shared.start(id: key, filename: name)

        task.resume()
        return key
    }

    /// Resume a previously paused download using stored resume data.
    @discardableResult
    public func resumeDownload(withKey key: String,
                                inDirectory directory: String? = nil,
                                withName fileName: String? = nil,
                                onProgress progressBlock: DownloadProgressBlock? = nil,
                                onCompletion completionBlock: @escaping DownloadCompletionBlock) -> Bool
    {
        guard let resumeData = UserDefaults.standard.data(forKey: "resume_\(key)") else {
            return false
        }
        UserDefaults.standard.removeObject(forKey: "resume_\(key)")

        let task = backgroundSession.downloadTask(withResumeData: resumeData)
        let obj = SDDownloadObject(downloadTask: task,
                                   progressBlock: progressBlock,
                                   completionBlock: completionBlock,
                                   fileName: fileName,
                                   directoryName: directory)
        downloadQueue.async(flags: .barrier) { self._ongoingDownloads[key] = obj }

        let name = fileName ?? URL(string: key)?.lastPathComponent ?? "Download"
        LiveActivityBridge.shared.start(id: key, filename: name)
        task.resume()
        return true
    }

    public func pauseDownload(forKey key: String) {
        downloadQueue.async {
            guard let obj = self._ongoingDownloads[key] else { return }
            obj.downloadTask.cancel(byProducingResumeData: { data in
                if let data = data {
                    UserDefaults.standard.set(data, forKey: "resume_\(key)")
                }
                self.downloadQueue.async(flags: .barrier) {
                    self._ongoingDownloads.removeValue(forKey: key)
                }
                LiveActivityBridge.shared.end(id: key, success: false)
            })
        }
    }

    public func cancelDownload(forKey key: String) {
        downloadQueue.async(flags: .barrier) {
            self._ongoingDownloads[key]?.downloadTask.cancel()
            self._ongoingDownloads.removeValue(forKey: key)
            UserDefaults.standard.removeObject(forKey: "resume_\(key)")
        }
        LiveActivityBridge.shared.end(id: key, success: false)
    }

    public func cancelAllDownloads() {
        downloadQueue.sync { _ongoingDownloads.keys }.forEach { cancelDownload(forKey: $0) }
    }

    public func isDownloadInProgress(forKey key: String) -> Bool {
        downloadQueue.sync { _ongoingDownloads[key] != nil }
    }

    public func hasResumeData(forKey key: String) -> Bool {
        UserDefaults.standard.data(forKey: "resume_\(key)") != nil
    }

    public func currentDownloadKeys() -> [String] {
        downloadQueue.sync { Array(_ongoingDownloads.keys) }
    }

    /// Re-attach callbacks to an in-flight download (e.g. after app foregrounds).
    public func reattach(forKey key: String,
                         onProgress progressBlock: DownloadProgressBlock?,
                         onCompletion completionBlock: @escaping DownloadCompletionBlock)
    {
        downloadQueue.async(flags: .barrier) {
            if let obj = self._ongoingDownloads[key] {
                obj.progressBlock   = progressBlock
                obj.completionBlock = completionBlock
            }
        }
    }
}

// MARK: - URLSession delegates

extension SDDownloadManager: URLSessionDelegate, URLSessionDownloadDelegate {

    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didWriteData _: Int64,
                           totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64)
    {
        guard totalBytesExpectedToWrite > 0,
              let key      = downloadTask.originalRequest?.url?.absoluteString,
              let download = downloadQueue.sync(execute: { _ongoingDownloads[key] }),
              let progress = Optional(CGFloat(totalBytesWritten) / CGFloat(totalBytesExpectedToWrite))
        else { return }

        // Update Live Activity — didWriteData fires in a system-granted background
        // execution context, so await activity.update() works correctly here.
        LiveActivityBridge.shared.update(id: key,
                                         progress: Double(progress),
                                         downloaded: totalBytesWritten,
                                         total: totalBytesExpectedToWrite)

        if let block = download.progressBlock {
            DispatchQueue.main.async {
                block(progress, totalBytesWritten, totalBytesExpectedToWrite)
            }
        }
    }

    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didFinishDownloadingTo location: URL)
    {
        guard let key      = downloadTask.originalRequest?.url?.absoluteString,
              let download = downloadQueue.sync(execute: { _ongoingDownloads[key] })
        else { return }

        if let response = downloadTask.response as? HTTPURLResponse, response.statusCode >= 400 {
            let err = NSError(domain: "HttpError", code: response.statusCode,
                              userInfo: [NSLocalizedDescriptionKey:
                                HTTPURLResponse.localizedString(forStatusCode: response.statusCode)])
            DispatchQueue.main.async { download.completionBlock(err, nil) }
            LiveActivityBridge.shared.end(id: key, success: false)
        } else {
            let name = download.fileName
                ?? downloadTask.response?.suggestedFilename
                ?? downloadTask.originalRequest?.url?.lastPathComponent
                ?? "download"

            let result = SDFileUtils.moveFile(fromUrl: location,
                                              toDirectory: download.directoryName,
                                              withName: name)
            DispatchQueue.main.async {
                result.0
                    ? download.completionBlock(nil, result.2)
                    : download.completionBlock(result.1, nil)
            }
            LiveActivityBridge.shared.end(id: key, success: result.0)
        }

        downloadQueue.async(flags: .barrier) { self._ongoingDownloads.removeValue(forKey: key) }
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didCompleteWithError error: Error?)
    {
        guard let error = error,
              let key    = task.originalRequest?.url?.absoluteString,
              let dl     = downloadQueue.sync(execute: { _ongoingDownloads[key] })
        else { return }

        // Check for resume data in the error (user info)
        if let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            UserDefaults.standard.set(resumeData, forKey: "resume_\(key)")
        }

        DispatchQueue.main.async { dl.completionBlock(error, nil) }
        LiveActivityBridge.shared.end(id: key, success: false)
        downloadQueue.async(flags: .barrier) { self._ongoingDownloads.removeValue(forKey: key) }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        session.getTasksWithCompletionHandler { _, _, downloadTasks in
            if downloadTasks.isEmpty {
                DispatchQueue.main.async {
                    self.backgroundCompletionHandler?()
                    if self.showLocalNotificationOnBackgroundDownloadDone {
                        self.showLocalNotification(
                            withText: self.localNotificationText ?? "Downloads complete")
                    }
                    self.backgroundCompletionHandler = nil
                }
            }
        }
    }

    private func showLocalNotification(withText text: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = text
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: "SDDownload-\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            )
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        }
    }
}

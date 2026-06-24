import UIKit
import UserNotifications

public final class SDDownloadManager: NSObject {

    // MARK: - Types

    public typealias DownloadCompletionBlock         = (_ error: Error?, _ fileUrl: URL?) -> Void
    public typealias DownloadProgressBlock           = (_ progress: CGFloat, _ downloaded: Int64, _ total: Int64) -> Void
    public typealias BackgroundDownloadCompletionHandler = () -> Void

    // MARK: - Singleton

    public static let shared = SDDownloadManager()

    // MARK: - Properties

    private let downloadQueue = DispatchQueue(label: "com.sddownloadmanager.queue", attributes: .concurrent)
    private var _ongoingDownloads: [String: SDDownloadObject] = [:]
    private var ongoingDownloads: [String: SDDownloadObject] {
        get { downloadQueue.sync { _ongoingDownloads } }
        set { downloadQueue.async(flags: .barrier) { self._ongoingDownloads = newValue } }
    }

    // Speed calculation state
    private var lastBytesMap: [String: Int64] = [:]
    private var lastTimeMap:  [String: Date]  = [:]

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

        let bgConfig = URLSessionConfiguration.background(
            withIdentifier: Bundle.main.bundleIdentifier! + ".download")
        bgConfig.isDiscretionary = false
        bgConfig.sessionSendsLaunchEvents = true
        backgroundSession = URLSession(configuration: bgConfig, delegate: self, delegateQueue: nil)
    }

    // MARK: - Public API

    @discardableResult
    public func downloadFile(withRequest request: URLRequest,
                             inDirectory directory: String? = nil,
                             withName fileName: String? = nil,
                             shouldDownloadInBackground: Bool = true,
                             onProgress progressBlock: DownloadProgressBlock? = nil,
                             onCompletion completionBlock: @escaping DownloadCompletionBlock) -> String?
    {
        guard let url = request.url else {
            completionBlock(makeError("Invalid URL"), nil)
            return nil
        }

        let key = url.absoluteString
        if isDownloadInProgress(forKey: key) {
            completionBlock(makeError("Already in progress"), nil)
            return nil
        }

        let task = shouldDownloadInBackground
            ? backgroundSession.downloadTask(with: request)
            : session.downloadTask(with: request)

        // Store the key in taskDescription so we can retrieve it even if
        // originalRequest is nil (which can happen with background URLSession).
        task.taskDescription = key

        let obj = SDDownloadObject(downloadTask: task,
                                   progressBlock: progressBlock,
                                   completionBlock: completionBlock,
                                   fileName: fileName,
                                   directoryName: directory)
        downloadQueue.async(flags: .barrier) { self._ongoingDownloads[key] = obj }

        let name = fileName ?? (url.lastPathComponent.isEmpty ? (url.host ?? "Download") : url.lastPathComponent)
        LiveActivityBridge.shared.start(id: key, filename: name)

        task.resume()
        return key
    }

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
        task.taskDescription = key   // store key here too

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
        lastBytesMap.removeValue(forKey: key)
        lastTimeMap.removeValue(forKey: key)
        LiveActivityBridge.shared.end(id: key, success: false)
    }

    public func cancelAllDownloads() {
        downloadQueue.sync { Array(_ongoingDownloads.keys) }.forEach { cancelDownload(forKey: $0) }
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

    public func reattach(forKey key: String,
                         onProgress progressBlock: DownloadProgressBlock?,
                         onCompletion completionBlock: @escaping DownloadCompletionBlock) {
        downloadQueue.async(flags: .barrier) {
            if let obj = self._ongoingDownloads[key] {
                obj.progressBlock   = progressBlock
                obj.completionBlock = completionBlock
            }
        }
    }

    // MARK: - Private helpers

    private func makeError(_ msg: String) -> NSError {
        NSError(domain: "SDDownloadManager", code: 0,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }

    /// Resolve the download key from a URLSessionTask.
    /// Prefers taskDescription (set by us) over originalRequest URL
    /// because background URLSession can nil out originalRequest.
    private func key(for task: URLSessionTask) -> String? {
        if let desc = task.taskDescription, !desc.isEmpty { return desc }
        return task.originalRequest?.url?.absoluteString
    }

    private func calculateSpeed(key: String, totalBytesWritten: Int64) -> Int64 {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTimeMap[key] ?? now)
        let delta = totalBytesWritten - (lastBytesMap[key] ?? 0)
        let speed = elapsed > 0.3 ? Int64(Double(max(delta, 0)) / elapsed) : 0
        lastBytesMap[key] = totalBytesWritten
        lastTimeMap[key]  = now
        return speed
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
        guard let key = key(for: downloadTask),
              let download = downloadQueue.sync(execute: { _ongoingDownloads[key] })
        else { return }

        let progress = totalBytesExpectedToWrite > 0
            ? CGFloat(totalBytesWritten) / CGFloat(totalBytesExpectedToWrite)
            : 0
        let speed = calculateSpeed(key: key, totalBytesWritten: totalBytesWritten)

        // Update Live Activity directly from URLSession delegate —
        // this IS a system-granted execution context where await works.
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
        guard let key = key(for: downloadTask),
              let download = downloadQueue.sync(execute: { _ongoingDownloads[key] })
        else {
            // Key lookup failed — still try to move the file using suggested filename
            let name = downloadTask.response?.suggestedFilename
                ?? downloadTask.originalRequest?.url?.lastPathComponent
                ?? "download_\(Int(Date().timeIntervalSince1970))"
            let result = SDFileUtils.moveFile(fromUrl: location, toDirectory: "Downloads", withName: name)
            print("[SDDownloadManager] orphan task completed — moved to: \(result.2?.path ?? "failed")")
            return
        }

        let name = download.fileName
            ?? downloadTask.response?.suggestedFilename
            ?? downloadTask.originalRequest?.url?.lastPathComponent
            ?? URL(string: key)?.lastPathComponent
            ?? "download_\(Int(Date().timeIntervalSince1970))"

        // Guard against empty name (causes "cannot create file")
        let safeName = name.isEmpty ? "download_\(Int(Date().timeIntervalSince1970))" : name

        if let response = downloadTask.response as? HTTPURLResponse, response.statusCode >= 400 {
            let err = makeError(HTTPURLResponse.localizedString(forStatusCode: response.statusCode))
            DispatchQueue.main.async { download.completionBlock(err, nil) }
            LiveActivityBridge.shared.end(id: key, success: false)
        } else {
            let result = SDFileUtils.moveFile(fromUrl: location,
                                              toDirectory: download.directoryName,
                                              withName: safeName)
            DispatchQueue.main.async {
                result.0
                    ? download.completionBlock(nil, result.2)
                    : download.completionBlock(result.1, nil)
            }
            LiveActivityBridge.shared.end(id: key, success: result.0)
        }

        lastBytesMap.removeValue(forKey: key)
        lastTimeMap.removeValue(forKey: key)
        downloadQueue.async(flags: .barrier) { self._ongoingDownloads.removeValue(forKey: key) }
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didCompleteWithError error: Error?)
    {
        guard let error = error,
              let key = key(for: task),
              let dl  = downloadQueue.sync(execute: { _ongoingDownloads[key] })
        else { return }

        // Stash resume data if present
        if let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            UserDefaults.standard.set(resumeData, forKey: "resume_\(key)")
        }

        DispatchQueue.main.async { dl.completionBlock(error, nil) }
        LiveActivityBridge.shared.end(id: key, success: false)
        lastBytesMap.removeValue(forKey: key)
        lastTimeMap.removeValue(forKey: key)
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

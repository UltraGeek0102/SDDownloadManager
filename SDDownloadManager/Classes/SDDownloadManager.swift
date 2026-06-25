import UIKit
import UserNotifications

public final class SDDownloadManager: NSObject {

    // MARK: - Types
    public typealias DownloadCompletionBlock         = (_ error: Error?, _ fileUrl: URL?) -> Void
    public typealias DownloadProgressBlock           = (_ progress: CGFloat, _ downloaded: Int64, _ total: Int64) -> Void
    public typealias BackgroundDownloadCompletionHandler = () -> Void

    // MARK: - Singleton
    public static let shared = SDDownloadManager()

    // MARK: - State
    private let lock = NSLock()
    private var _tasks: [String: SDDownloadObject] = [:]

    private var lastBytesMap: [String: Int64] = [:]
    private var lastTimeMap:  [String: Date]  = [:]

    // Background URLSession — iOS manages transfers even when app is suspended
    private var bgSession: URLSession!

    public var backgroundCompletionHandler: BackgroundDownloadCompletionHandler?
    public var showLocalNotificationOnBackgroundDownloadDone = true
    public var localNotificationText: String?

    // MARK: - Init
    override private init() {
        super.init()
        let cfg = URLSessionConfiguration.background(
            withIdentifier: Bundle.main.bundleIdentifier! + ".download")
        cfg.isDiscretionary = false
        cfg.sessionSendsLaunchEvents = true
        bgSession = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
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
        guard !isDownloadInProgress(forKey: key) else {
            completionBlock(makeError("Already in progress"), nil)
            return nil
        }

        let task = bgSession.downloadTask(with: request)
        task.taskDescription = key   // always use this — originalRequest can be nil on bg tasks

        let name = fileName ?? SDFileUtils.resolvedFilename(from: url.lastPathComponent)
        let obj  = SDDownloadObject(downloadTask: task,
                                    progressBlock: progressBlock,
                                    completionBlock: completionBlock,
                                    fileName: name,
                                    directoryName: directory ?? "Downloads")
        lock.lock(); _tasks[key] = obj; lock.unlock()

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
        guard let resumeData = UserDefaults.standard.data(forKey: resumeKey(key)) else {
            return false
        }
        UserDefaults.standard.removeObject(forKey: resumeKey(key))

        let task = bgSession.downloadTask(withResumeData: resumeData)
        task.taskDescription = key

        let name = fileName ?? SDFileUtils.resolvedFilename(
            from: URL(string: key)?.lastPathComponent ?? "download")
        let obj  = SDDownloadObject(downloadTask: task,
                                    progressBlock: progressBlock,
                                    completionBlock: completionBlock,
                                    fileName: name,
                                    directoryName: directory ?? "Downloads")
        lock.lock(); _tasks[key] = obj; lock.unlock()

        LiveActivityBridge.shared.start(id: key, filename: name)
        task.resume()
        return true
    }

    public func pauseDownload(forKey key: String) {
        lock.lock(); let obj = _tasks[key]; lock.unlock()
        obj?.downloadTask.cancel(byProducingResumeData: { [weak self] data in
            if let data = data {
                UserDefaults.standard.set(data, forKey: self?.resumeKey(key) ?? "resume_\(key)")
            }
            self?.lock.lock(); self?._tasks.removeValue(forKey: key); self?.lock.unlock()
            LiveActivityBridge.shared.end(id: key, success: false)
        })
    }

    public func cancelDownload(forKey key: String) {
        lock.lock(); let obj = _tasks[key]; _tasks.removeValue(forKey: key); lock.unlock()
        obj?.downloadTask.cancel()
        UserDefaults.standard.removeObject(forKey: resumeKey(key))
        lastBytesMap.removeValue(forKey: key)
        lastTimeMap.removeValue(forKey: key)
        LiveActivityBridge.shared.end(id: key, success: false)
    }

    public func cancelAllDownloads() {
        lock.lock(); let keys = Array(_tasks.keys); lock.unlock()
        keys.forEach { cancelDownload(forKey: $0) }
    }

    public func isDownloadInProgress(forKey key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _tasks[key] != nil
    }

    public func hasResumeData(forKey key: String) -> Bool {
        UserDefaults.standard.data(forKey: resumeKey(key)) != nil
    }

    public func currentDownloadKeys() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(_tasks.keys)
    }

    public func reattach(forKey key: String,
                         onProgress: DownloadProgressBlock?,
                         onCompletion: @escaping DownloadCompletionBlock) {
        lock.lock()
        if let obj = _tasks[key] {
            obj.progressBlock   = onProgress
            obj.completionBlock = onCompletion
        }
        lock.unlock()
    }

    // MARK: - Private

    private func resumeKey(_ key: String) -> String { "resume_\(key)" }

    private func makeError(_ msg: String) -> NSError {
        NSError(domain: "SDDownloadManager", code: 0,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }

    private func taskKey(for task: URLSessionTask) -> String? {
        // taskDescription is set by us and survives background suspension
        if let d = task.taskDescription, !d.isEmpty { return d }
        return task.originalRequest?.url?.absoluteString
    }

    private func calculateSpeed(key: String, bytesWritten: Int64) -> Int64 {
        let now  = Date()
        let elapsed = now.timeIntervalSince(lastTimeMap[key] ?? now)
        let delta   = bytesWritten - (lastBytesMap[key] ?? 0)
        let speed   = elapsed > 0.3 ? Int64(Double(max(delta, 0)) / elapsed) : 0
        lastBytesMap[key] = bytesWritten
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
        guard let key = taskKey(for: downloadTask) else { return }
        lock.lock(); let obj = _tasks[key]; lock.unlock()

        let progress = totalBytesExpectedToWrite > 0
            ? CGFloat(totalBytesWritten) / CGFloat(totalBytesExpectedToWrite) : 0
        let _ = calculateSpeed(key: key, bytesWritten: totalBytesWritten)

        LiveActivityBridge.shared.update(id: key, progress: Double(progress),
                                         downloaded: totalBytesWritten,
                                         total: totalBytesExpectedToWrite)
        if let block = obj?.progressBlock {
            DispatchQueue.main.async {
                block(progress, totalBytesWritten, totalBytesExpectedToWrite)
            }
        }
    }

    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didFinishDownloadingTo location: URL)
    {
        // Resolve key and download object
        guard let key = taskKey(for: downloadTask) else {
            print("[DL] no key for task — dropping file at \(location.path)")
            return
        }
        lock.lock(); let obj = _tasks[key]; lock.unlock()

        let directory = obj?.directoryName ?? "Downloads"
        let rawName   = obj?.fileName
            ?? downloadTask.response?.suggestedFilename
            ?? downloadTask.originalRequest?.url?.lastPathComponent
            ?? URL(string: key)?.lastPathComponent
            ?? "download"
        let safeName = SDFileUtils.resolvedFilename(from: rawName)

        // Read the temp file into memory IMMEDIATELY before it can be cleaned up.
        // This is the most reliable approach for sideloaded apps where the sandbox
        // may place temp files in a path we can't move from later.
        let fileData: Data
        do {
            fileData = try Data(contentsOf: location)
        } catch {
            print("[DL] failed to read temp file: \(error)")
            DispatchQueue.main.async {
                obj?.completionBlock(error, nil)
            }
            LiveActivityBridge.shared.end(id: key, success: false)
            lock.lock(); _tasks.removeValue(forKey: key); lock.unlock()
            return
        }

        // Write to Documents from memory — no temp file path dependency
        let saveResult = SDFileUtils.writeData(fileData,
                                               toDirectory: directory,
                                               withName: safeName)
        print("[DL] wrote \(safeName) ok=\(saveResult.0) err=\(saveResult.1?.localizedDescription ?? "-")")

        if let resp = downloadTask.response as? HTTPURLResponse, resp.statusCode >= 400 {
            let err = makeError(HTTPURLResponse.localizedString(forStatusCode: resp.statusCode))
            DispatchQueue.main.async { obj?.completionBlock(err, nil) }
            LiveActivityBridge.shared.end(id: key, success: false)
        } else {
            DispatchQueue.main.async {
                saveResult.0
                    ? obj?.completionBlock(nil, saveResult.2)
                    : obj?.completionBlock(saveResult.1, nil)
            }
            LiveActivityBridge.shared.end(id: key, success: saveResult.0)
        }

        lastBytesMap.removeValue(forKey: key)
        lastTimeMap.removeValue(forKey: key)
        lock.lock(); _tasks.removeValue(forKey: key); lock.unlock()
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didCompleteWithError error: Error?)
    {
        guard let error = error else { return }

        // Ignore cancellation (pause stores resume data separately)
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled { return }

        guard let key = taskKey(for: task) else { return }
        lock.lock(); let obj = _tasks[key]; lock.unlock()
        guard let obj = obj else { return }

        // Stash resume data if present in error userInfo
        if let resumeData = nsErr.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            UserDefaults.standard.set(resumeData, forKey: resumeKey(key))
        }

        DispatchQueue.main.async { obj.completionBlock(error, nil) }
        LiveActivityBridge.shared.end(id: key, success: false)
        lastBytesMap.removeValue(forKey: key)
        lastTimeMap.removeValue(forKey: key)
        lock.lock(); _tasks.removeValue(forKey: key); lock.unlock()
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
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false))
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        }
    }
}

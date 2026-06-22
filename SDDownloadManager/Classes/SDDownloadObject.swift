import UIKit

final class SDDownloadObject: NSObject {
    var completionBlock: SDDownloadManager.DownloadCompletionBlock
    var progressBlock:   SDDownloadManager.DownloadProgressBlock?
    let downloadTask:    URLSessionDownloadTask
    let directoryName:   String?
    let fileName:        String?

    // Resume data stored when the user pauses
    var resumeData:      Data?
    // When this download started (for history record)
    let startDate:       Date

    init(downloadTask:   URLSessionDownloadTask,
         progressBlock:  SDDownloadManager.DownloadProgressBlock?,
         completionBlock:@escaping SDDownloadManager.DownloadCompletionBlock,
         fileName:       String?,
         directoryName:  String?)
    {
        self.downloadTask   = downloadTask
        self.completionBlock = completionBlock
        self.progressBlock  = progressBlock
        self.fileName       = fileName
        self.directoryName  = directoryName
        self.startDate      = Date()
    }
}

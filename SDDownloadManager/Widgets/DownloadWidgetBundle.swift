import WidgetKit
import SwiftUI

@main
struct DownloadWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.2, *) {
            DownloadWidget()            // TimelineProvider — drives LA updates
            DownloadLiveActivityWidget() // Live Activity UI configuration
        }
    }
}

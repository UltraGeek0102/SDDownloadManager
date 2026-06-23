import WidgetKit
import SwiftUI

@main
struct DownloadWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.2, *) {
            DownloadWidget()
        }
    }
}

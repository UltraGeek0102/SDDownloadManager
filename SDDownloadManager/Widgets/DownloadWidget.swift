import WidgetKit
import SwiftUI
import ActivityKit

private func formatBytes(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}
private func formatSpeed(_ bps: Int64) -> String {
    guard bps > 0 else { return "–" }
    return "\(formatBytes(bps))/s"
}

// MARK: - Lock Screen / StandBy view

@available(iOS 16.2, *)
struct DownloadLockScreenView: View {
    let context: ActivityViewContext<DownloadActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.title3)
                Text(context.attributes.filename)
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(String(format: "%.0f%%", context.state.progress * 100))
                    .font(.headline).monospacedDigit()
                    .foregroundColor(iconColor)
            }

            ProgressView(value: context.state.progress)
                .progressViewStyle(.linear)
                .tint(iconColor)
                .scaleEffect(x: 1, y: 1.5)

            HStack {
                if context.state.totalBytes > 0 {
                    Text("\(formatBytes(context.state.downloadedBytes)) / \(formatBytes(context.state.totalBytes))")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text(formatBytes(context.state.downloadedBytes))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(formatSpeed(context.state.speedBytesPerSec))
                    .font(.caption).foregroundColor(.secondary).monospacedDigit()
            }
        }
        .padding()
        .activityBackgroundTint(Color(.systemBackground).opacity(0.9))
    }

    private var isDone:   Bool { context.state.statusLabel == "Done" }
    private var isFailed: Bool { context.state.statusLabel == "Stopped" || context.state.statusLabel == "Failed" }

    private var iconName: String {
        isDone   ? "checkmark.circle.fill" :
        isFailed ? "xmark.circle.fill" :
                   "arrow.down.circle.fill"
    }
    private var iconColor: Color {
        isDone   ? .green :
        isFailed ? .red   : .blue
    }
}

// MARK: - Widget configuration

@available(iOS 16.2, *)
struct DownloadWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            DownloadLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue).font(.title3).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(String(format: "%.0f%%", context.state.progress * 100))
                        .bold().monospacedDigit().padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        HStack {
                            Text(context.attributes.filename)
                                .font(.caption).lineLimit(1).truncationMode(.middle)
                            Spacer()
                        }
                        ProgressView(value: context.state.progress)
                            .progressViewStyle(.linear).tint(.blue)
                        HStack {
                            Text(formatBytes(context.state.downloadedBytes))
                                .font(.caption2).foregroundColor(.secondary)
                            Spacer()
                            Text(formatSpeed(context.state.speedBytesPerSec))
                                .font(.caption2).foregroundColor(.secondary).monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 6)
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill").foregroundColor(.blue)
            } compactTrailing: {
                Text(String(format: "%.0f%%", context.state.progress * 100))
                    .monospacedDigit().font(.caption2).bold()
            } minimal: {
                Image(systemName: "arrow.down.circle.fill").foregroundColor(.blue)
            }
            .widgetURL(URL(string: "sddownloadmanager://open"))
            .keylineTint(.blue)
        }
    }
}

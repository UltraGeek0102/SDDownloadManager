import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - Helpers

private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private func formatSpeed(_ bps: Int64) -> String {
    guard bps > 0 else { return "" }
    return formatBytes(bps) + "/s"
}

// MARK: - Lock Screen / StandBy view

@available(iOS 16.2, *)
struct DownloadLockScreenView: View {
    let context: ActivityViewContext<DownloadActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                Text(context.attributes.filename)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(String(format: "%.0f%%", context.state.progress * 100))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(iconColor)
            }

            // Progress bar
            ProgressView(value: context.state.progress)
                .progressViewStyle(.linear)
                .tint(iconColor)
                .scaleEffect(x: 1, y: 1.5)

            // Footer
            HStack {
                if context.state.totalBytes > 0 {
                    Text("\(formatBytes(context.state.downloadedBytes)) of \(formatBytes(context.state.totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(formatBytes(context.state.downloadedBytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                let speed = formatSpeed(context.state.speedBytesPerSec)
                if !speed.isEmpty {
                    Text(speed)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text(context.state.statusLabel)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(iconColor)
            }
        }
        .padding()
        .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
    }

    private var icon: String {
        switch context.state.statusLabel {
        case "Done":   return "checkmark.circle.fill"
        case "Failed": return "exclamationmark.circle.fill"
        case "Paused": return "pause.circle.fill"
        default:       return "arrow.down.circle.fill"
        }
    }

    private var iconColor: Color {
        switch context.state.statusLabel {
        case "Done":   return .green
        case "Failed": return .red
        case "Paused": return .orange
        default:       return .blue
        }
    }
}

// MARK: - Dynamic Island compact leading

@available(iOS 16.2, *)
struct DI_CompactLeading: View {
    let context: ActivityViewContext<DownloadActivityAttributes>
    var body: some View {
        Image(systemName: context.state.statusLabel == "Done"   ? "checkmark.circle.fill" :
                          context.state.statusLabel == "Failed" ? "exclamationmark.circle.fill" :
                          context.state.statusLabel == "Paused" ? "pause.circle.fill" :
                                                                  "arrow.down.circle.fill")
            .foregroundStyle(context.state.statusLabel == "Done"   ? .green :
                             context.state.statusLabel == "Failed" ? .red :
                             context.state.statusLabel == "Paused" ? .orange : .blue)
            .font(.body)
    }
}

// MARK: - Dynamic Island compact trailing

@available(iOS 16.2, *)
struct DI_CompactTrailing: View {
    let context: ActivityViewContext<DownloadActivityAttributes>
    var body: some View {
        Text(String(format: "%.0f%%", context.state.progress * 100))
            .monospacedDigit()
            .font(.caption2.bold())
    }
}

// MARK: - Dynamic Island expanded

@available(iOS 16.2, *)
struct DI_Expanded: View {
    let context: ActivityViewContext<DownloadActivityAttributes>
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Text(context.attributes.filename)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(String(format: "%.0f%%", context.state.progress * 100))
                    .font(.caption.bold())
                    .monospacedDigit()
            }
            ProgressView(value: context.state.progress)
                .progressViewStyle(.linear)
                .tint(.blue)
            HStack {
                if context.state.totalBytes > 0 {
                    Text("\(formatBytes(context.state.downloadedBytes)) / \(formatBytes(context.state.totalBytes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                let speed = formatSpeed(context.state.speedBytesPerSec)
                if !speed.isEmpty {
                    Text(speed)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - Widget configuration

@available(iOS 16.2, *)
struct DownloadLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            DownloadLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title2)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(String(format: "%.0f%%", context.state.progress * 100))
                        .font(.title3.bold())
                        .monospacedDigit()
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DI_Expanded(context: context)
                }
            } compactLeading: {
                DI_CompactLeading(context: context)
            } compactTrailing: {
                DI_CompactTrailing(context: context)
            } minimal: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            }
            .widgetURL(URL(string: "godepdl://open"))
            .keylineTint(.blue)
        }
    }
}

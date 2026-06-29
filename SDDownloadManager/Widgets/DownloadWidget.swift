import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Helpers

private func formatBytes(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}
private func formatSpeed(_ bps: Int64) -> String {
    guard bps > 0 else { return "–" }
    return "\(formatBytes(bps))/s"
}

// MARK: - TimelineProvider widget
// This widget has no visible home screen UI — its only job is to give WidgetKit
// a reason to wake the extension process so we can update Live Activities from here.
// When the main app calls WidgetCenter.reloadTimelines(ofKind:"DownloadWidget"),
// iOS wakes this extension, getTimeline() runs, and we update all active Live Activities
// from THIS process — which is never suspended — solving the background freeze issue.

struct DownloadEntry: TimelineEntry {
    let date: Date
    let items: [SharedProgress]
}

struct DownloadTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DownloadEntry {
        DownloadEntry(date: Date(), items: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (DownloadEntry) -> Void) {
        completion(DownloadEntry(date: Date(), items: SharedProgressStore.shared.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DownloadEntry>) -> Void) {
        let items = SharedProgressStore.shared.read()

        // Update all active Live Activities from the widget extension process.
        // This is the key: activity.update() called here runs in a SEPARATE PROCESS
        // that iOS never suspends, so it always executes regardless of main app state.
        if #available(iOS 16.2, *) {
            updateLiveActivities(from: items)
        }

        let entry = DownloadEntry(date: Date(), items: items)

        // If there are active downloads, request a refresh in 1 second.
        // WidgetKit may throttle this but will try to honour it.
        let nextRefresh = Date().addingTimeInterval(items.isEmpty ? 60 : 1)
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }

    @available(iOS 16.2, *)
    private func updateLiveActivities(from items: [SharedProgress]) {
        // Get all currently active Live Activities for our type
        let activeActivities = Activity<DownloadActivityAttributes>.activities

        for item in items {
            // Find the matching activity by its downloadId attribute
            guard let activity = activeActivities.first(where: {
                $0.attributes.downloadId == item.id
            }) else { continue }

            let state = DownloadActivityAttributes.ContentState(
                progress: item.progress,
                downloadedBytes: item.downloadedBytes,
                totalBytes: item.totalBytes,
                speedBytesPerSec: item.speedBytesPerSec,
                statusLabel: "Downloading"
            )
            // Task here runs in the widget extension process — never suspended
            Task {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }
    }
}

// Minimal home screen widget view — not visible to user (accessory or no placement)
struct DownloadWidgetView: View {
    let entry: DownloadEntry
    var body: some View {
        if entry.items.isEmpty {
            Image(systemName: "arrow.down.circle")
                .foregroundColor(.secondary)
        } else {
            VStack(spacing: 2) {
                ForEach(entry.items.prefix(2), id: \.id) { item in
                    ProgressView(value: item.progress)
                        .tint(.blue)
                }
            }
            .padding(4)
        }
    }
}

@available(iOS 16.2, *)
struct DownloadWidget: Widget {
    static let kind = "DownloadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: DownloadTimelineProvider()) { entry in
            DownloadWidgetView(entry: entry)
        }
        .configurationDisplayName("Downloads")
        .description("Tracks active download progress")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

// MARK: - Live Activity widget (Dynamic Island + Lock Screen UI)

@available(iOS 16.2, *)
struct DownloadLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            // Lock Screen / StandBy view
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: statusIcon(context.state))
                        .foregroundColor(statusColor(context.state))
                        .font(.title3)
                    Text(context.attributes.filename)
                        .font(.headline).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(String(format: "%.0f%%", context.state.progress * 100))
                        .font(.headline).monospacedDigit()
                        .foregroundColor(statusColor(context.state))
                }
                ProgressView(value: context.state.progress)
                    .progressViewStyle(.linear)
                    .tint(statusColor(context.state))
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

    private func statusIcon(_ state: DownloadActivityAttributes.ContentState) -> String {
        switch state.statusLabel {
        case "Done":   return "checkmark.circle.fill"
        case "Failed": return "xmark.circle.fill"
        default:       return "arrow.down.circle.fill"
        }
    }

    private func statusColor(_ state: DownloadActivityAttributes.ContentState) -> Color {
        switch state.statusLabel {
        case "Done":   return .green
        case "Failed": return .red
        default:       return .blue
        }
    }
}

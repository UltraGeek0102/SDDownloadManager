import SwiftUI

struct HistoryView: View {
    @StateObject private var store = DownloadStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if store.history.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.history) { item in
                            HistoryRowView(item: item)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        store.deleteHistory(item: item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    if item.status == .failed {
                                        Button {
                                            store.retry(item: item)
                                        } label: {
                                            Label("Retry", systemImage: "arrow.clockwise")
                                        }
                                        .tint(.orange)
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !store.history.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear", role: .destructive) {
                            store.clearHistory()
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)
            Text("No Download History")
                .font(.title2).bold()
            Text("Completed and failed downloads appear here")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HistoryRowView: View {
    @ObservedObject var item: DownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.filename)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                statusBadge
            }

            if item.status == .done {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(item.localPath != nil ? "Saved to Files" : "Complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let date = item.savedAt {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if item.status == .failed {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(item.errorMessage ?? "Download failed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if item.totalBytes > 0 {
                Text(ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: item.status == .done ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption)
            Text(item.status == .done ? "Done" : "Failed")
                .font(.caption2).bold()
        }
        .foregroundStyle(item.status == .done ? Color.green : Color.red)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((item.status == .done ? Color.green : Color.red).opacity(0.12))
        .clipShape(Capsule())
    }
}

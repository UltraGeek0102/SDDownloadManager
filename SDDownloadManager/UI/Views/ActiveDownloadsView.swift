import SwiftUI

struct ActiveDownloadsView: View {
    @ObservedObject var vm: DownloadsViewModel
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.activeDownloads.isEmpty {
                    emptyState
                } else {
                    List(vm.activeDownloads) { record in
                        DownloadRowView(record: record, vm: vm)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddDownloadView(vm: vm)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)
            Text("No Active Downloads")
                .font(.title2).bold()
            Text("Tap + to start a new download")
                .foregroundStyle(.secondary)
            Button {
                showAddSheet = true
            } label: {
                Label("Add Download", systemImage: "plus")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Download row

struct DownloadRowView: View {
    let record: DownloadRecord
    @ObservedObject var vm: DownloadsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.filename)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                statusBadge
            }

            ProgressView(value: record.progress)
                .tint(tintColor)

            HStack {
                Text(sizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !record.displaySpeed.isEmpty {
                    Text(record.displaySpeed)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(record.displayProgress)
                    .font(.caption)
                    .bold()
                    .monospacedDigit()
            }

            // Action buttons
            HStack(spacing: 12) {
                Spacer()
                if record.status == .downloading {
                    Button {
                        vm.pauseDownload(id: record.id)
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                } else if record.status == .paused {
                    if record.canResume {
                        Button {
                            vm.resumeDownload(id: record.id)
                        } label: {
                            Label("Resume", systemImage: "play.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    }
                }
                Button(role: .destructive) {
                    vm.cancelDownload(id: record.id)
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Text(record.status.rawValue.capitalized)
            .font(.caption2)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch record.status {
        case .downloading: return .blue
        case .paused:      return .orange
        case .completed:   return .green
        case .failed:      return .red
        }
    }

    private var tintColor: Color {
        switch record.status {
        case .downloading: return .blue
        case .paused:      return .orange
        case .failed:      return .red
        case .completed:   return .green
        }
    }

    private var sizeText: String {
        if record.totalBytes > 0 {
            let dl    = ByteCountFormatter.string(fromByteCount: record.downloadedBytes, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: record.totalBytes, countStyle: .file)
            return "\(dl) / \(total)"
        }
        return ByteCountFormatter.string(fromByteCount: record.downloadedBytes, countStyle: .file)
    }
}

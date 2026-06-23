import SwiftUI

struct ActiveDownloadsView: View {
    @EnvironmentObject var vm: DownloadsViewModel
    @State private var showAddSheet = false

    var body: some View {
        NavigationView {
            Group {
                if vm.activeItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.circle.dotted")
                            .font(.system(size: 56))
                            .foregroundColor(.secondary)
                        Text("No active downloads")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap + to add a URL")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(vm.activeItems) { item in
                            DownloadRowView(item: item)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        vm.cancel(item: item)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    if item.status == .downloading {
                                        Button {
                                            vm.pause(item: item)
                                        } label: {
                                            Label("Pause", systemImage: "pause.circle")
                                        }
                                        .tint(.orange)
                                    } else if item.status == .paused || item.status == .failed {
                                        Button {
                                            vm.resume(item: item)
                                        } label: {
                                            Label("Resume", systemImage: "play.circle")
                                        }
                                        .tint(.green)
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddDownloadView(isPresented: $showAddSheet)
                    .environmentObject(vm)
            }
        }
    }
}

// MARK: - Download Row

struct DownloadRowView: View {
    let item: DownloadItem
    // Timer to refresh progress display while downloading
    @State private var tick = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.filename)
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                statusBadge
            }

            if item.status == .downloading || item.status == .paused {
                ProgressView(value: item.progress)
                    .tint(item.status == .paused ? .orange : .blue)

                HStack {
                    Text(item.formattedSize)
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    if item.status == .downloading && item.speedBytesPerSec > 0 {
                        Text(item.formattedSpeed)
                            .font(.caption).foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            } else if item.status == .failed {
                Text(item.errorMessage ?? "Unknown error")
                    .font(.caption).foregroundColor(.red)
                    .lineLimit(2)
            } else if item.status == .completed {
                Text(item.savedFilePath ?? "")
                    .font(.caption).foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.vertical, 4)
        .onReceive(
            Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        ) { _ in
            if item.status == .downloading { tick.toggle() }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .downloading:
            Label(item.formattedProgress, systemImage: "arrow.down.circle.fill")
                .font(.caption).foregroundColor(.blue)
        case .paused:
            Label("Paused", systemImage: "pause.circle.fill")
                .font(.caption).foregroundColor(.orange)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.circle.fill")
                .font(.caption).foregroundColor(.red)
        case .queued:
            Label("Queued", systemImage: "clock.fill")
                .font(.caption).foregroundColor(.secondary)
        case .completed:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundColor(.green)
        }
    }
}

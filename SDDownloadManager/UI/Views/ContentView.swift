import SwiftUI

struct ContentView: View {

    @StateObject private var store = DownloadStore.shared
    @State private var showAddSheet = false
    @State private var selectedTab  = 0

    var body: some View {
        TabView(selection: $selectedTab) {

            // ── Active downloads ────────────────────────────────────────────
            NavigationView {
                Group {
                    if store.active.isEmpty {
                        emptyActiveView
                    } else {
                        List {
                            ForEach(store.active) { item in
                                DownloadRowView(item: item)
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
                .navigationTitle("Downloads")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                    }
                }
            }
            .tabItem {
                Label("Downloads", systemImage: "arrow.down.circle")
            }
            .tag(0)

            // ── History ─────────────────────────────────────────────────────
            NavigationView {
                Group {
                    if store.history.isEmpty {
                        emptyHistoryView
                    } else {
                        List {
                            ForEach(store.history) { item in
                                HistoryRowView(item: item)
                            }
                            .onDelete { indexSet in
                                indexSet.map { store.history[$0] }.forEach {
                                    store.deleteHistory(item: $0)
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
                .navigationTitle("History")
                .toolbar {
                    if !store.history.isEmpty {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Clear", role: .destructive) {
                                store.clearHistory()
                            }
                        }
                    }
                }
            }
            .tabItem {
                Label("History", systemImage: "clock")
            }
            .tag(1)
        }
        .sheet(isPresented: $showAddSheet) {
            AddDownloadView(isPresented: $showAddSheet)
        }
    }

    private var emptyActiveView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.dotted")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Active Downloads")
                .font(.title2.bold())
            Text("Tap + to add a download URL")
                .foregroundColor(.secondary)
            Button {
                showAddSheet = true
            } label: {
                Label("Add Download", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
    }

    private var emptyHistoryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Download History")
                .font(.title2.bold())
            Text("Completed downloads will appear here")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Add Download Sheet

struct AddDownloadView: View {

    @Binding var isPresented: Bool
    @State private var urlText = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("https://example.com/file.zip", text: $urlText)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focused)
                } header: {
                    Text("Download URL")
                } footer: {
                    Text("Downloads run in the background even when the app is closed. Progress is shown on the Dynamic Island and Lock Screen.")
                }

                Section {
                    Button {
                        startDownload()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Start Download", systemImage: "arrow.down.circle.fill")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("New Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func startDownload() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        DownloadStore.shared.addDownload(urlString: trimmed)
        isPresented = false
    }
}

// MARK: - Active download row

struct DownloadRowView: View {

    @ObservedObject var item: DownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                Text(item.filename)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(progressText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            if item.status == .downloading || item.status == .paused {
                ProgressView(value: item.progress)
                    .tint(item.status == .paused ? .orange : .accentColor)

                HStack {
                    Text(bytesText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if item.status == .downloading && item.speedBytesPerSec > 0 {
                        Text(speedText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            if let error = item.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Spacer()
                actionButtons
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch item.status {
        case .downloading:
            Button {
                DownloadStore.shared.pause(item: item)
            } label: {
                Label("Pause", systemImage: "pause.circle")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .tint(.orange)

            Button(role: .destructive) {
                DownloadStore.shared.cancel(item: item)
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)

        case .paused:
            Button {
                DownloadStore.shared.resume(item: item)
            } label: {
                Label("Resume", systemImage: "play.circle")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .tint(.green)

            Button(role: .destructive) {
                DownloadStore.shared.cancel(item: item)
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)

        case .queued:
            Text("Queued")
                .font(.caption)
                .foregroundColor(.secondary)

        default:
            EmptyView()
        }
    }

    private var statusIcon: String {
        switch item.status {
        case .queued:      return "clock"
        case .downloading: return "arrow.down.circle.fill"
        case .paused:      return "pause.circle.fill"
        case .done:        return "checkmark.circle.fill"
        case .failed:      return "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .queued:      return .secondary
        case .downloading: return .accentColor
        case .paused:      return .orange
        case .done:        return .green
        case .failed:      return .red
        }
    }

    private var progressText: String {
        item.status == .downloading || item.status == .paused
            ? String(format: "%.0f%%", item.progress * 100)
            : ""
    }

    private var bytesText: String {
        if item.totalBytes > 0 {
            return "\(formatBytes(item.downloadedBytes)) / \(formatBytes(item.totalBytes))"
        }
        return formatBytes(item.downloadedBytes)
    }

    private var speedText: String { "\(formatBytes(item.speedBytesPerSec))/s" }

    private func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

// MARK: - History row

struct HistoryRowView: View {

    @ObservedObject var item: DownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: item.status == .done ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(item.status == .done ? .green : .red)
                Text(item.filename)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }

            if item.status == .done, let total = item.totalBytes > 0 ? item.totalBytes : nil {
                Text(formatBytes(total))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let date = item.savedAt ?? item.addedAt as Date? {
                Text(date, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let error = item.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            if item.status == .failed {
                Button {
                    DownloadStore.shared.retry(item: item)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var vm: DownloadsViewModel
    @State private var showClearConfirm = false

    var body: some View {
        NavigationView {
            Group {
                if vm.historyItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 56))
                            .foregroundColor(.secondary)
                        Text("No completed downloads")
                            .font(.headline).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(vm.historyItems) { record in
                            HistoryRowView(record: record)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        vm.removeHistory(record: record)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !vm.historyItems.isEmpty {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Text("Clear All")
                        }
                    }
                }
            }
            .confirmationDialog("Clear all history?", isPresented: $showClearConfirm,
                                titleVisibility: .visible) {
                Button("Clear All", role: .destructive) { vm.clearHistory() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct HistoryRowView: View {
    let record: DownloadRecord
    @State private var showShareSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: record.status == .completed
                      ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(record.status == .completed ? .green : .red)
                Text(record.filename)
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if record.status == .completed {
                if record.totalBytes > 0 {
                    Text(record.formattedSize)
                        .font(.caption).foregroundColor(.secondary)
                }
                Text(record.formattedDate)
                    .font(.caption).foregroundColor(.secondary)

                if let path = record.savedFilePath {
                    Text(path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            } else {
                Text(record.errorMessage ?? "Failed")
                    .font(.caption).foregroundColor(.red)
                Text(record.formattedDate)
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if record.savedFilePath != nil { showShareSheet = true }
        }
        .sheet(isPresented: $showShareSheet) {
            if let path = record.savedFilePath {
                ShareSheet(url: URL(fileURLWithPath: path))
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

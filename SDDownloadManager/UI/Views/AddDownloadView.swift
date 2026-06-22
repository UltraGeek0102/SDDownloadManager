import SwiftUI

struct AddDownloadView: View {
    @ObservedObject var vm: DownloadsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var urlText      = ""
    @State private var customName   = ""
    @State private var showError    = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Download URL") {
                    TextField("https://example.com/file.zip", text: $urlText)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("File Name (optional)") {
                    TextField("Leave blank to use URL filename", text: $customName)
                        .autocorrectionDisabled()
                }

                Section {
                    Button(action: startDownload) {
                        HStack {
                            Spacer()
                            Label("Start Download", systemImage: "arrow.down.circle.fill")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .foregroundStyle(.white)
                    .listRowBackground(Color.blue)
                }
            }
            .navigationTitle("New Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Invalid URL", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func startDownload() {
        let success = vm.addDownload(urlString: urlText,
                                     customName: customName.isEmpty ? nil : customName)
        if success {
            dismiss()
        } else {
            errorMessage = "Please enter a valid HTTP or HTTPS URL."
            showError = true
        }
    }
}

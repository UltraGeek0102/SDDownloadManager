import SwiftUI

struct AddDownloadView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var vm: DownloadsViewModel

    @State private var urlString = ""
    @State private var filename  = ""
    @State private var showError = false
    @State private var errorMsg  = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("https://example.com/file.zip", text: $urlString)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("URL")
                } footer: {
                    Text("Paste a direct download link")
                }

                Section {
                    TextField("Optional — uses URL filename by default", text: $filename)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Filename (optional)")
                }

                Section {
                    Button {
                        startDownload()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Start Download", systemImage: "arrow.down.circle.fill")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Add Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
            .alert("Invalid URL", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMsg)
            }
        }
    }

    private func startDownload() {
        let url = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, URL(string: url) != nil else {
            errorMsg  = "Please enter a valid URL starting with https://"
            showError = true
            return
        }
        vm.startDownload(
            urlString: url,
            filename: filename.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        isPresented = false
    }
}

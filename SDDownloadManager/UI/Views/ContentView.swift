import SwiftUI

struct ContentView: View {
    @StateObject private var vm = DownloadsViewModel.shared

    var body: some View {
        TabView {
            ActiveDownloadsView()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                .environmentObject(vm)

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .environmentObject(vm)
        }
    }
}

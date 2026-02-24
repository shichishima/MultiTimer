#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct iOSRootView: View {
    @Environment(TimerStore.self) private var store
    @State private var selectedTab: Tab = .timer

    enum Tab { case timer, share }

    var body: some View {
        TabView(selection: $selectedTab) {
            Group {
                if store.dataFolderURL == nil {
                    Text("共有フォルダーを設定してください")
                        .font(.title2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentView()
                }
            }
            .tabItem { Label("タイマー", systemImage: "timer") }
            .tag(Tab.timer)

            ShareFolderView()
                .tabItem { Label("共有", systemImage: "folder") }
                .tag(Tab.share)
        }
        .onAppear {
            selectedTab = store.dataFolderURL == nil ? .share : .timer
        }
        .onChange(of: store.dataFolderURL) { _, newURL in
            if newURL != nil { selectedTab = .timer }
        }
    }
}

struct ShareFolderView: View {
    @Environment(TimerStore.self) private var store
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 24) {
            if let url = store.dataFolderURL {
                Text("設定済み: \(url.lastPathComponent)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button("フォルダを指定してください") { isImporting = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder]) { result in
            if let url = try? result.get() {
                store.setDataFolder(url)
            }
        }
    }
}
#endif

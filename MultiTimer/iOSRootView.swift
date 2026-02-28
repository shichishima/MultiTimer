#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct iOSRootView: View {
    @Environment(TimerStore.self) private var store
    @State private var selectedTab: AppTab = .timer

    enum AppTab { case timer, share }

    var body: some View {
        VStack(spacing: 0) {
            contentView
            customTabBar
        }
        .onAppear {
            selectedTab = store.dataFileURL == nil ? .share : .timer
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .timer:
            if store.dataFileURL == nil {
                Text("データファイルを設定してください")
                    .font(.title2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentView()
            }
        case .share:
            ShareFolderView()
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabButton(tab: .timer, systemImage: "timer", label: "タイマー")
            tabButton(tab: .share, systemImage: "folder", label: "共有")
        }
        .frame(height: 49)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func tabButton(tab: AppTab, systemImage: String, label: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ShareFolderView: View {
    @Environment(TimerStore.self) private var store
    @State private var isImporting = false
    @State private var fileTypeError = false

    var body: some View {
        VStack(spacing: 16) {
            if let url = store.dataFileURL {
                Text("設定済み: \(url.lastPathComponent)")
                    .font(.subheadline).foregroundStyle(.secondary)

                // 読み込み内容の診断表示
                VStack(alignment: .leading, spacing: 4) {
                    Text("--- 読み込み内容 ---")
                        .font(.caption.bold())
                    Text("利用者数: \(store.data.users.count)  スロット数: \(store.data.timerSlots.count)")
                        .font(.caption.monospaced())
                    Text("利用者名: \(store.data.users.map(\.name).joined(separator: ", "))")
                        .font(.caption.monospaced())
                        .lineLimit(2)
                    Text("lastModified: \(store.data.lastModified.formatted())")
                        .font(.caption.monospaced())
                    Text("ファイルパス:")
                        .font(.caption.bold())
                    Text(url.path)
                        .font(.caption.monospaced())
                        .lineLimit(4)
                        .truncationMode(.middle)
                    Text("YAML先頭:")
                        .font(.caption.bold())
                    Text(store.debugYAML.isEmpty ? "(空)" : store.debugYAML)
                        .font(.caption.monospaced())
                        .lineLimit(6)
                    if let err = store.saveErrorMessage {
                        Text("エラー: \(err)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                            .lineLimit(5)
                    } else {
                        Text("エラーなし")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
            }
            if fileTypeError {
                Text(".yml または .yaml ファイルを選択してください")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("データファイルを指定してください") { isImporting = true }
                .buttonStyle(.borderedProminent)
            if store.dataFileURL != nil {
                Button("データ再読み込み") { store.reloadFromFile() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { result in
            fileTypeError = false
            guard let url = try? result.get() else { return }
            let ext = url.pathExtension.lowercased()
            guard ext == "yml" || ext == "yaml" else {
                fileTypeError = true
                return
            }
            store.setDataFile(url)
        }
    }
}
#endif

import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)

struct SettingsView: View {
    @Environment(TimerStore.self) private var store
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            UsersSettingsView()
                .tabItem { Label("利用者", systemImage: "person.3") }
                .tag(0)
                .disabled(store.dataFileURL == nil)

            LinksSettingsView()
                .tabItem { Label("連携", systemImage: "link") }
                .tag(1)
                .disabled(store.dataFileURL == nil)

            SharingSettingsView()
                .tabItem { Label("共有", systemImage: "folder") }
                .tag(2)

            PreferencesSettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(3)
        }
        .frame(minWidth: 560, minHeight: 380)
        .padding()
        .onAppear {
            if store.dataFileURL == nil { selectedTab = 2 }
        }
    }
}

// MARK: - Sharing Settings

private struct SharingSettingsView: View {
    @Environment(TimerStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("データファイルの設定")
                .font(.headline)

            HStack(alignment: .top, spacing: 8) {
                Text("データファイル:")
                    .foregroundStyle(.secondary)
                Text(store.dataFileURL?.path ?? "未設定")
                    .foregroundStyle(store.dataFileURL == nil ? .secondary : .primary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button("データファイルを指定...") {
                    selectFile()
                }
                .buttonStyle(.bordered)

                Button("新規にデータファイルを作成する...") {
                    createFile()
                }
                .buttonStyle(.bordered)
            }

            if store.dataFileURL == nil {
                Text("データファイルを指定すると、「利用者」「連携」タブが利用できるようになります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "yml"), UTType(filenameExtension: "yaml")].compactMap { $0 }
        panel.message = "MultiTimer.yml を選択してください"
        panel.prompt = "選択"
        if panel.runModal() == .OK, let url = panel.url {
            store.setDataFile(url)
        }
    }

    private func createFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "yml")].compactMap { $0 }
        panel.nameFieldStringValue = "MultiTimer.yml"
        panel.message = "データファイルの保存場所を選択してください"
        panel.prompt = "作成"
        if panel.runModal() == .OK, let url = panel.url {
            store.setDataFile(url)
        }
    }
}

// MARK: - Users Settings

private struct UsersSettingsView: View {
    @Environment(TimerStore.self) private var store
    @State private var editedUsers: [AppUser] = []

    private var visibleCount: Int { editedUsers.filter(\.isVisible).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("利用者の設定 (最大6人を表示)")
                .font(.headline)

            List {
                ForEach(editedUsers.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        // 表示トグル
                        Toggle("", isOn: $editedUsers[i].isVisible)
                            .labelsHidden()
                            .disabled(!editedUsers[i].isVisible && visibleCount >= 6)

                        // 名前フィールド (常に編集可)
                        TextField("名前", text: $editedUsers[i].name)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { source, dest in
                    editedUsers.move(fromOffsets: source, toOffset: dest)
                    for i in editedUsers.indices {
                        editedUsers[i].displayOrder = i
                    }
                }
            }
            .listStyle(.inset)

            HStack {
                Button("利用者を追加") {
                    let newUser = AppUser(
                        name: "利用者\(editedUsers.count + 1)",
                        isVisible: false,
                        displayOrder: editedUsers.count
                    )
                    editedUsers.append(newUser)
                }
                .buttonStyle(.bordered)

                Spacer()
                Button("適用") { applyChanges() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            editedUsers = store.data.users.sorted { $0.displayOrder < $1.displayOrder }
        }
    }

    private func applyChanges() {
        var updated = store.data

        // 新たに非表示になる利用者の非連携タイマーをリセット
        for newUser in editedUsers {
            if let old = store.data.users.first(where: { $0.id == newUser.id }),
               old.isVisible, !newUser.isVisible {
                let soloId = "solo-\(newUser.id)"
                if let idx = updated.slotIndex(id: soloId) {
                    updated.timerSlots[idx].endDate = nil
                }
            }
        }

        updated.users = editedUsers
        updated.ensureSlots()
        store.applySettings(updated)
    }
}

// MARK: - Links Settings

private struct LinksSettingsView: View {
    @Environment(TimerStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("利用者間の連携設定")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: true) {
                linksGrid
            }
        }
    }

    private var linksGrid: some View {
        let allUsers = store.data.users.sorted { $0.displayOrder < $1.displayOrder }
        return VStack(alignment: .leading, spacing: 0) {
            // ヘッダー行
            HStack(spacing: 0) {
                ForEach(allUsers) { user in
                    Text(user.name)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 108, height: 36)
                        .background(Color.primary.opacity(0.06))
                        .border(Color.gray.opacity(0.3))
                }
            }

            // 連携スロット 3行
            ForEach(0..<3, id: \.self) { slotIndex in
                HStack(spacing: 0) {
                    ForEach(allUsers) { user in
                        LinkSlotCell(
                            user: user,
                            slotIndex: slotIndex,
                            allUsers: allUsers
                        )
                    }
                }
            }
        }
    }
}

// MARK: - LinkSlotCell

private struct LinkSlotCell: View {
    let user: AppUser
    let slotIndex: Int
    let allUsers: [AppUser]

    @Environment(TimerStore.self) private var store
    @State private var showColorPicker = false

    private var userLinks: [TimerLink] {
        store.data.links(for: user.id)
    }

    private var link: TimerLink? {
        slotIndex < userLinks.count ? userLinks[slotIndex] : nil
    }

    /// このユーザーが選択できる連携相手 (自分以外 & まだ3連携未満)
    private var availablePartners: [AppUser] {
        let alreadyLinkedIds = Set(userLinks.compactMap { lnk in
            lnk.partner(of: user.id)
        })
        return allUsers.filter { candidate in
            guard candidate.id != user.id else { return false }
            guard !alreadyLinkedIds.contains(candidate.id) else { return false }
            // 相手側が3連携済みかチェック
            if store.data.linkCount(for: candidate.id) >= 3 { return false }
            return true
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let lnk = link {
                // 既存連携
                let partnerName = store.data.userName(id: lnk.partner(of: user.id) ?? "")
                let linkColor = Color(hex: lnk.colorHex) ?? .blue

                ColorPicker("", selection: Binding(
                    get: { linkColor },
                    set: { newColor in
                        updateLinkColor(linkId: lnk.id, color: newColor)
                    }
                ))
                .labelsHidden()
                .frame(width: 28)

                Text(partnerName)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    removeLink(lnk)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)

            } else if slotIndex == userLinks.count && userLinks.count < 3 {
                // 新規追加スロット
                Menu {
                    ForEach(availablePartners) { partner in
                        Button(partner.name) {
                            addLink(partner: partner)
                        }
                    }
                    if availablePartners.isEmpty {
                        Text("追加できる連携相手がいません")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Label("追加", systemImage: "plus.circle")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .menuStyle(.borderlessButton)

            } else {
                // 空スロット (上のスロットが埋まっていない)
                Spacer()
            }
        }
        .padding(.horizontal, 6)
        .frame(width: 108, height: 44)
        .border(Color.gray.opacity(0.25))
    }

    private func addLink(partner: AppUser) {
        var updated = store.data
        let newLink = TimerLink(
            userAId: user.id,
            userBId: partner.id,
            colorHex: "#4A90D9"
        )
        updated.links.append(newLink)
        updated.ensureSlots()
        let slotId = "link-\(newLink.id)"
        updated.checkStates["\(slotId):\(user.id)"] = true
        updated.checkStates["\(slotId):\(partner.id)"] = true
        store.applySettings(updated)
    }

    private func removeLink(_ lnk: TimerLink) {
        var updated = store.data
        // 連携タイマーをリセット
        let slotId = "link-\(lnk.id)"
        if let idx = updated.slotIndex(id: slotId) {
            updated.timerSlots[idx].endDate = nil
            updated.timerSlots[idx].originalDuration = nil
        }
        updated.links.removeAll { $0.id == lnk.id }
        updated.ensureSlots()
        store.applySettings(updated)
    }

    private func updateLinkColor(linkId: String, color: Color) {
        guard let idx = store.data.links.firstIndex(where: { $0.id == linkId }) else { return }
        var updated = store.data
        updated.links[idx].colorHex = color.hexString
        store.applySettings(updated)
    }
}

// MARK: - Preferences Settings

private struct PreferencesSettingsView: View {
    @AppStorage("macNotificationsEnabled") private var notificationsEnabled = true
    @AppStorage("macSoundEnabled") private var soundEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("アプリの動作設定")
                .font(.headline)

            Form {
                Toggle("通知", isOn: $notificationsEnabled)
                Toggle("サウンド", isOn: $soundEnabled)
            }
            .formStyle(.grouped)

            Spacer()
        }
        .padding()
    }
}

#Preview {
    SettingsView()
        .environment(TimerStore())
}

#endif

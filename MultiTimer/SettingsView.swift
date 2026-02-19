import SwiftUI

#if os(macOS)

struct SettingsView: View {
    @Environment(TimerStore.self) private var store
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            UsersSettingsView()
                .tabItem { Label("利用者", systemImage: "person.3") }
                .tag(0)

            LinksSettingsView()
                .tabItem { Label("連携", systemImage: "link") }
                .tag(1)
        }
        .frame(minWidth: 560, minHeight: 380)
        .padding()
    }
}

// MARK: - Users Settings

private struct UsersSettingsView: View {
    @Environment(TimerStore.self) private var store
    @State private var editedUsers: [AppUser] = []

    private var visibleCount: Int { editedUsers.filter(\.isVisible).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("利用者の設定 (最大5人を表示)")
                .font(.headline)

            List {
                ForEach(editedUsers.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        // 表示トグル
                        Toggle("", isOn: $editedUsers[i].isVisible)
                            .labelsHidden()
                            .disabled(!editedUsers[i].isVisible && visibleCount >= 5)

                        // 名前フィールド (表示ONの時のみ編集可)
                        TextField("名前", text: $editedUsers[i].name)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                            .disabled(!editedUsers[i].isVisible)

                        // グレーアウト表示
                        if !editedUsers[i].isVisible && visibleCount >= 5 {
                            Text("上限")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .opacity((!editedUsers[i].isVisible && visibleCount >= 5) ? 0.5 : 1.0)
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
                        .frame(width: 180, height: 36)
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
        .frame(width: 180, height: 44)
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

#Preview {
    SettingsView()
        .environment(TimerStore())
}

#endif

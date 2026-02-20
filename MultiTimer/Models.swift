import Foundation
import SwiftUI

// MARK: - AppUser

struct AppUser: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var isVisible: Bool
    var displayOrder: Int
}

// MARK: - TimerLink

/// 双方向連携。userAId <-> userBId のペアが1つのTimerSlotを共有する
struct TimerLink: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var userAId: String
    var userBId: String
    var colorHex: String = "#4A90D9"

    func involves(_ userId: String) -> Bool {
        userAId == userId || userBId == userId
    }

    func partner(of userId: String) -> String? {
        if userAId == userId { return userBId }
        if userBId == userId { return userAId }
        return nil
    }
}

// MARK: - TimerSlot

/// カウントダウンタイマー1つ分の状態
/// id = "solo-{userId}" (非連携) or "link-{linkId}" (連携・2ユーザー共有)
struct TimerSlot: Codable, Identifiable, Equatable {
    var id: String
    /// カウントダウン完了予定日時。nil = 停止中(手動リセット or 未設定)
    var endDate: Date?
    /// 元のタイマー時間(秒)。nil = 一度も設定されていない
    var originalDuration: TimeInterval?

    var remainingSeconds: TimeInterval {
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSinceNow)
    }

    var isRunning: Bool {
        guard let endDate else { return false }
        return endDate.timeIntervalSinceNow > 0
    }

    /// endDateが設定されており(=動作していた)かつ満了済み → 自然終了(赤表示)
    var isCompletedNaturally: Bool {
        guard let endDate, originalDuration != nil else { return false }
        return endDate.timeIntervalSinceNow <= 0
    }
}

// MARK: - AppData

struct AppData: Codable {
    var users: [AppUser]
    var links: [TimerLink]
    var timerSlots: [TimerSlot]
    var lastModified: Date
    var checkStates: [String: Bool] = [:]

    init() {
        let names = ["利用者A", "利用者B", "利用者C", "利用者D", "利用者E", "利用者F"]
        users = names.enumerated().map { i, name in
            AppUser(name: name, isVisible: i == 0, displayOrder: i)
        }
        links = []
        timerSlots = []
        lastModified = .now
        ensureSlots()
    }

    /// 必要なスロットを追加し、不要なスロットを削除する
    mutating func ensureSlots() {
        for user in users {
            let slotId = "solo-\(user.id)"
            if !timerSlots.contains(where: { $0.id == slotId }) {
                timerSlots.append(TimerSlot(id: slotId))
            }
        }
        for link in links {
            let slotId = "link-\(link.id)"
            if !timerSlots.contains(where: { $0.id == slotId }) {
                timerSlots.append(TimerSlot(id: slotId))
            }
        }
        let validIds = Set(users.map { "solo-\($0.id)" })
            .union(Set(links.map { "link-\($0.id)" }))
        timerSlots.removeAll { !validIds.contains($0.id) }
    }

    // MARK: Slot helpers

    func slot(id: String) -> TimerSlot? {
        timerSlots.first { $0.id == id }
    }

    func slotIndex(id: String) -> Int? {
        timerSlots.firstIndex { $0.id == id }
    }

    /// ユーザーが持つスロットID一覧を残り時間昇順で返す
    func slotIds(for userId: String) -> [String] {
        var ids = ["solo-\(userId)"]
        for link in links where link.involves(userId) {
            ids.append("link-\(link.id)")
        }
        return ids.sorted {
            (slot(id: $0)?.remainingSeconds ?? 0) < (slot(id: $1)?.remainingSeconds ?? 0)
        }
    }

    // MARK: User helpers

    var visibleUsers: [AppUser] {
        users
            .filter { $0.isVisible }
            .sorted { $0.displayOrder < $1.displayOrder }
            .prefix(5)
            .map { $0 }
    }

    func userName(id: String) -> String {
        users.first { $0.id == id }?.name ?? id
    }

    // MARK: Link helpers

    func link(id: String) -> TimerLink? {
        links.first { $0.id == id }
    }

    func linkForSlot(id slotId: String) -> TimerLink? {
        guard slotId.hasPrefix("link-") else { return nil }
        return link(id: String(slotId.dropFirst(5)))
    }

    func partnerName(slotId: String, viewingAs userId: String) -> String? {
        guard let lnk = linkForSlot(id: slotId),
              let partnerId = lnk.partner(of: userId) else { return nil }
        return userName(id: partnerId)
    }

    func linkColor(slotId: String) -> Color? {
        guard let lnk = linkForSlot(id: slotId) else { return nil }
        return Color(hex: lnk.colorHex)
    }

    func links(for userId: String) -> [TimerLink] {
        links.filter { $0.involves(userId) }
    }

    func linkCount(for userId: String) -> Int {
        links.filter { $0.involves(userId) }.count
    }
}

// MARK: - Color Hex Extension

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        #if canImport(AppKit)
        let c = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Timer Duration Options

struct TimerDuration {
    let label: String
    let seconds: TimeInterval
}

let timerDurations: [TimerDuration] = [
    TimerDuration(label: "12時間", seconds: 43200),
    TimerDuration(label: "8時間",  seconds: 28800),
    TimerDuration(label: "6時間",  seconds: 21600),
    TimerDuration(label: "4時間",  seconds: 14400),
    TimerDuration(label: "3時間",  seconds: 10800),
    TimerDuration(label: "2時間",  seconds:  7200),
    TimerDuration(label: "90分",   seconds:  5400),
    TimerDuration(label: "1時間",  seconds:  3600),
    TimerDuration(label: "45分",   seconds:  2700),
    TimerDuration(label: "30分",   seconds:  1800),
    TimerDuration(label: "20分",   seconds:  1200),
    TimerDuration(label: "15分",   seconds:   900),
    TimerDuration(label: "10分",   seconds:   600),
    TimerDuration(label: "5分",    seconds:   300),
    TimerDuration(label: "3分",    seconds:   180),
    TimerDuration(label: "1分",    seconds:    60),
]

// MARK: - Time Format

func formatTime(_ seconds: TimeInterval) -> String {
    let s = Int(max(0, seconds))
    if s >= 3600 {
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    } else {
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
#else
import UIKit
import AudioToolbox
import UserNotifications
#endif

@Observable
final class TimerStore {
    var data: AppData = AppData()
    var saveErrorMessage: String? = nil
    var dataFolderURL: URL? = nil
    var isLoading: Bool = false
    /// 毎秒インクリメント → これを購読するビューが1秒ごとに再描画される
    var tick: Int = 0

    /// 動作中タイマーの満了検知用
    private var previouslyRunningIds: Set<String> = []
    private var tickTimer: Timer?

    init() {
        #if os(macOS)
        if let url = resolveBookmark() {
            _ = url.startAccessingSecurityScopedResource()
            dataFolderURL = url
            loadFromDisk()
        } else {
            data = AppData()
        }
        #else
        data = AppData()
        #endif
        checkExpiredOnLaunch()
        startTickTimer()
    }

    // MARK: - Timer Operations

    func startTimer(slotId: String, duration: TimeInterval) {
        guard let idx = data.slotIndex(id: slotId) else { return }
        let endDate = Date().addingTimeInterval(duration)
        data.timerSlots[idx].endDate = endDate
        data.timerSlots[idx].originalDuration = duration
        data.lastModified = .now
        saveToDisk()
        previouslyRunningIds.insert(slotId)

        #if os(iOS)
        scheduleNotification(slotId: slotId, endDate: endDate)
        #endif
    }

    /// タイマーを手動停止(0:00リセット)。endDate = nil, originalDuration は保持
    func stopTimer(slotId: String) {
        guard let idx = data.slotIndex(id: slotId) else { return }
        data.timerSlots[idx].endDate = nil
        data.lastModified = .now
        saveToDisk()
        previouslyRunningIds.remove(slotId)

        #if os(iOS)
        cancelNotification(slotId: slotId)
        #endif
    }

    // MARK: - Settings Update

    func applySettings(_ newData: AppData) {
        var updated = newData
        updated.ensureSlots()
        updated.lastModified = .now
        data = updated
        saveToDisk()
    }

    // MARK: - Folder Management

    func setDataFolder(_ url: URL) {
        #if os(macOS)
        dataFolderURL?.stopAccessingSecurityScopedResource()
        saveBookmark(url: url)
        _ = url.startAccessingSecurityScopedResource()
        #endif
        dataFolderURL = url
        let fileURL = url.appendingPathComponent("MultiTimer.yml")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            loadFromDisk()
        } else {
            saveToDisk()
        }
    }

    func reloadFromFile() {
        guard let folder = dataFolderURL else { return }
        isLoading = true
        Task {
            do {
                let fileURL = folder.appendingPathComponent("MultiTimer.yml")
                let yaml = try await Task.detached {
                    try String(contentsOf: fileURL, encoding: .utf8)
                }.value
                let newData = try decodeAppDataYAML(yaml)
                self.data = newData
                self.saveErrorMessage = nil
            } catch {
                self.saveErrorMessage = "読み込み失敗: \(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }

    // MARK: - Check State

    func toggleCheckState(slotId: String, userId: String) {
        let key = "\(slotId):\(userId)"
        data.checkStates[key] = !(data.checkStates[key] ?? false)
        saveToDisk()
    }

    // MARK: - Local File I/O

    private func loadFromDisk() {
        guard let url = dataFolderURL else {
            data = AppData()
            return
        }
        do {
            data = try loadAppData(from: url)
        } catch {
            data = AppData()
        }
    }

    private func saveToDisk() {
        guard let url = dataFolderURL else { return }
        do {
            try saveAppData(data, to: url)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - Expired Timer Check

    /// アプリ起動時: バックグラウンド中に満了したタイマーがあれば音を1回鳴らす
    private func checkExpiredOnLaunch() {
        let hasExpired = data.timerSlots.contains { $0.isCompletedNaturally }
        if hasExpired { playSound() }
    }

    /// 1秒ごとに満了を検知して音を鳴らす
    private func startTickTimer() {
        for slot in data.timerSlots where slot.isRunning {
            previouslyRunningIds.insert(slot.id)
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForNewlyExpired()
        }
    }

    private func checkForNewlyExpired() {
        tick += 1  // 毎秒インクリメントしてビューの再描画をトリガー
        var soundNeeded = false
        for slot in data.timerSlots {
            if previouslyRunningIds.contains(slot.id) && !slot.isRunning {
                soundNeeded = true
                previouslyRunningIds.remove(slot.id)
                // 満了時にファイル保存(endDate は既に過去になっている)
                saveToDisk()
            } else if slot.isRunning {
                previouslyRunningIds.insert(slot.id)
            }
        }
        if soundNeeded { playSound() }
    }

    // MARK: - Sound

    private func playSound() {
        #if canImport(AppKit)
        if let sound = NSSound(named: "Pop") {
            sound.play()
        } else {
            NSSound.beep()
        }
        #else
        AudioServicesPlaySystemSound(1057)
        #endif
    }

    // MARK: - iOS Local Notifications

    #if os(iOS)
    private func scheduleNotification(slotId: String, endDate: Date) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.sound, .alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "タイマー終了"
            content.body = "カウントダウンが完了しました"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, endDate.timeIntervalSinceNow),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: slotId, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }

    private func cancelNotification(slotId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [slotId])
    }
    #endif
}

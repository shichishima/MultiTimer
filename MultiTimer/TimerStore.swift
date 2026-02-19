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
    /// 毎秒インクリメント → これを購読するビューが1秒ごとに再描画される
    var tick: Int = 0

    /// 動作中タイマーの満了検知用
    private var previouslyRunningIds: Set<String> = []
    private var tickTimer: Timer?

    init() {
        loadFromDisk()
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

    // MARK: - Local File I/O

    private func loadFromDisk() {
        do {
            data = try loadAppData()
        } catch {
            // ファイルが存在しない場合はデフォルト値のまま
            data = AppData()
        }
    }

    private func saveToDisk() {
        do {
            try saveAppData(data)
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

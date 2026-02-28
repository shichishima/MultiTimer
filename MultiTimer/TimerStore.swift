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
    var dataFileURL: URL? = nil
    var isLoading: Bool = false
    /// 毎秒インクリメント → これを購読するビューが1秒ごとに再描画される
    var tick: Int = 0
    /// デバッグ用：最後に読んだYAMLの先頭200文字（後で削除）
    var debugYAML: String = ""

    /// 動作中タイマーの満了検知用
    private var previouslyRunningIds: Set<String> = []
    private var tickTimer: Timer?

    /// ファイル変更監視
    private var fileChangePresenter: FileChangePresenter?
    private var reloadDebounceTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?

    #if os(iOS)
    private let notificationDelegate = NotificationDelegate()
    #endif

    init() {
        if let url = resolveBookmark() {
            _ = url.startAccessingSecurityScopedResource()
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if !isDir.boolValue {
                // ファイル or クラウドファイル（未キャッシュで存在確認できない場合も含む）
                dataFileURL = url
            } else {
                // 旧フォルダURLブックマーク → サイレント破棄
                url.stopAccessingSecurityScopedResource()
            }
        }
        checkExpiredOnLaunch()
        startTickTimer()
        #if os(iOS)
        UNUserNotificationCenter.current().delegate = notificationDelegate
        subscribeToLifecycleNotifications()
        #endif
        reloadFromFile()  // 非同期読み込み（クラウドファイル対応）
        startFilePresenting()
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

    // MARK: - File Management

    func setDataFile(_ url: URL) {
        stopFilePresenting()
        dataFileURL?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        saveBookmark(url: url)
        dataFileURL = url
        do {
            let yaml = try coordinatedRead(from: url)
            debugYAML = String(yaml.prefix(200))
            data = try decodeAppDataYAML(yaml)
            saveErrorMessage = nil
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
            // ファイルが存在しない（新規作成）→ 書き出して作成
            debugYAML = "(file not found → created)"
            saveToDisk()
        } catch {
            data = AppData()
            debugYAML = "(error: \(error))"
            saveErrorMessage = "読み込み失敗: \(error)"
        }
        startFilePresenting()
    }

    func reloadFromFile(showLoading: Bool = true, checkExpired: Bool = true) {
        guard let fileURL = dataFileURL else { return }
        // 自動再読み込みは進行中タスクがあればスキップ（NSFileCoordinator blocking によるスレッドプール枯渇を防ぐ）
        if !showLoading, reloadTask != nil { return }
        reloadTask?.cancel()
        if showLoading { isLoading = true }
        reloadTask = Task {
            do {
                let yaml = try await Task.detached {
                    try self.coordinatedRead(from: fileURL)
                }.value
                let newData = try decodeAppDataYAML(yaml)
                self.data = newData
                self.saveErrorMessage = nil
            } catch is CancellationError {
                return  // 後続タスクに引き継ぎ: reloadTask/isLoading はそのまま
            } catch {
                self.saveErrorMessage = "読み込み失敗: \(error.localizedDescription)"
            }
            self.isLoading = false
            self.reloadTask = nil
            if checkExpired { self.checkExpiredOnLaunch() }
            #if os(iOS)
            self.refreshNotifications()
            #endif
        }
    }

    // MARK: - Check State

    func toggleCheckState(slotId: String, userId: String) {
        let key = "\(slotId):\(userId)"
        data.checkStates[key] = !(data.checkStates[key] ?? false)
        saveToDisk()
    }

    // MARK: - File Change Monitoring

    private func startFilePresenting() {
        stopFilePresenting()
        guard let url = dataFileURL else { return }
        let presenter = FileChangePresenter()
        presenter.presentedItemURL = url
        presenter.onChange = { [weak self] in
            self?.scheduleAutoReload()
        }
        NSFileCoordinator.addFilePresenter(presenter)
        fileChangePresenter = presenter
    }

    private func stopFilePresenting() {
        reloadDebounceTask?.cancel()
        reloadDebounceTask = nil
        reloadTask?.cancel()
        reloadTask = nil
        if let presenter = fileChangePresenter {
            NSFileCoordinator.removeFilePresenter(presenter)
            fileChangePresenter = nil
        }
    }

    private func scheduleAutoReload() {
        reloadDebounceTask?.cancel()
        reloadDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1秒デバウンス
            guard let self, !Task.isCancelled, !self.isLoading else { return }
            self.reloadFromFile(showLoading: false, checkExpired: false)
        }
    }

    // MARK: - Local File I/O

    /// NSFileCoordinator 経由でファイルを読む（ファイルプロバイダーに最新版を要求する）
    nonisolated private func coordinatedRead(from url: URL) throws -> String {
        var coordinatorError: NSError?
        var readResult: Result<String, Error> = .failure(
            CocoaError(.fileReadUnknown)
        )
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordURL in
            do {
                readResult = .success(try String(contentsOf: coordURL, encoding: .utf8))
            } catch {
                readResult = .failure(error)
            }
        }
        if let err = coordinatorError { throw err }
        return try readResult.get()
    }

    private func saveToDisk() {
        guard let url = dataFileURL else { return }
        let snapshot = data
        Task.detached { [weak self] in
            do {
                try saveAppData(snapshot, to: url)
                await MainActor.run { self?.saveErrorMessage = nil }
            } catch {
                let msg = "保存に失敗しました: \(error.localizedDescription)"
                await MainActor.run { self?.saveErrorMessage = msg }
            }
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
        if let sound = NSSound(named: "Sosumi") {
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
    private func subscribeToLifecycleNotifications() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, let url = self.dataFileURL else { return }
            _ = url.startAccessingSecurityScopedResource()
            self.startFilePresenting()
            self.reloadFromFile(showLoading: false, checkExpired: true)
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.stopFilePresenting()
            self?.dataFileURL?.stopAccessingSecurityScopedResource()
        }
    }

    /// 動作中タイマーの通知をすべて再同期する（ファイル経由で外部からタイマーが変化した時に呼ぶ）
    private func refreshNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        for slot in data.timerSlots {
            guard slot.isRunning, let endDate = slot.endDate else { continue }
            scheduleNotification(slotId: slot.id, endDate: endDate)
        }
    }

    private func scheduleNotification(slotId: String, endDate: Date) {
        // チェックONのユーザー名を収集
        var userIds: [String] = []
        if slotId.hasPrefix("solo-") {
            userIds = [String(slotId.dropFirst(5))]
        } else if let link = data.linkForSlot(id: slotId) {
            userIds = [link.userAId, link.userBId]
        }
        let checkedNames = userIds.compactMap { userId -> String? in
            guard data.checkStates["\(slotId):\(userId)"] == true else { return nil }
            return data.userName(id: userId)
        }
        guard !checkedNames.isEmpty else { return }  // チェックONなし → 通知しない

        let notificationTitle = checkedNames.joined(separator: ", ") + " - カウントダウン終了"
        UNUserNotificationCenter.current().requestAuthorization(options: [.sound, .alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = notificationTitle
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

// MARK: - FileChangePresenter

private final class FileChangePresenter: NSObject, NSFilePresenter {
    var presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = .main
    var onChange: (() -> Void)?

    func presentedItemDidChange() {
        onChange?()
    }
}

// MARK: - NotificationDelegate (iOS)

#if os(iOS)
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// フォアグラウンド中でも通知バナーとサウンドを表示する
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
#endif

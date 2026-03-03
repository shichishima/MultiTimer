import SwiftUI

struct TimerCellView: View {
    let slotId: String
    let userId: String
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let showOverlay: Bool
    let isPartnerHighlighted: Bool
    let onHoverChanged: (Bool) -> Void

    @Environment(TimerStore.self) private var store
    @State private var showDurationPicker = false

    private var slot: TimerSlot? { store.data.slot(id: slotId) }
    private var linkColor: Color? { store.data.linkColor(slotId: slotId) }
    private var partnerName: String? { store.data.partnerName(slotId: slotId, viewingAs: userId) }
    private var linkedDisplay: String? {
        guard let partner = partnerName else { return nil }
        let myName = store.data.userName(id: userId)
        return "\(myName)・\(partner)"
    }

    private var isRunning: Bool { slot?.isRunning ?? false }
    private var isCompleted: Bool { slot?.isCompletedNaturally ?? false }
    private var hasOriginal: Bool { slot?.originalDuration != nil }
    private var isChecked: Bool { store.data.checkStates["\(slotId):\(userId)"] ?? false }

    private var timerTextColor: Color {
        if isCompleted {
            // 停止中（自然完了）: 連携+OFFなら薄赤、それ以外は赤
            if linkColor != nil && !isChecked { return Color.red.opacity(0.4) }
            return .red
        }
        // 動作中: 連携+OFFなら70%グレー、それ以外は黒
        if isRunning && linkColor != nil && !isChecked { return Color(white: 0.7) }
        return .primary
    }

    // フォントサイズをセルサイズから算出
    private var timeFontSize: CGFloat { min(cellHeight * 0.30, (cellWidth - colorBarWidth - 8) / 5.0) }
    private var subFontSize: CGFloat { cellHeight * 0.12 }
    private var colorBarWidth: CGFloat { cellWidth * 0.055 }

    var body: some View {
        // store.tick を読むことで毎秒再描画される
        let _ = store.tick
        return ZStack {
            // ベースセル
            HStack(spacing: 0) {
                // 色バー (連携タイマーのみ)
                if let color = linkColor {
                    color
                        .frame(width: colorBarWidth)
                } else {
                    Color.clear
                        .frame(width: colorBarWidth)
                }

                // コンテンツ: VStack をセルにセンタリング
                VStack(alignment: .center, spacing: 2) {
                    // 連携表示「連携元名〜連携先名」
                    if let display = linkedDisplay {
                        Text(display)
                            #if os(iOS)
                            .font(.system(size: timeFontSize * 0.64, weight: .medium))
                            #else
                            .font(.system(size: subFontSize * 1.3, weight: .medium))
                            #endif
                            .foregroundStyle(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    } else {
                        Text(" ")
                            #if os(iOS)
                            .font(.system(size: timeFontSize * 0.64))
                            #else
                            .font(.system(size: subFontSize * 1.3))
                            #endif
                    }

                    // 残り時間:
                    //   ZStack の幅 = 最大値"12:00:00"の非表示テキストで確定
                    //   → この枠がVStack内でセンタリングされる
                    //   実際の時間テキストは枠の中で右揃え
                    let timeFont = Font.system(size: timeFontSize, weight: .bold).monospacedDigit()
                    ZStack(alignment: .trailing) {
                        Text("12:00:00")          // 最大幅の基準 (非表示)
                            .font(timeFont)
                            .hidden()
                        Text(formatTime(isCompleted ? (slot?.originalDuration ?? 0) : (slot?.remainingSeconds ?? 0)))
                            .font(timeFont)
                            .foregroundStyle(timerTextColor)
                    }

                    // 元の時間 (設定済みの場合のみ、時:分のみ表示)
                    if let original = slot?.originalDuration {
                        let h = Int(original) / 3600
                        let m = (Int(original) % 3600) / 60
                        Text(String(format: "%d:%02d", h, m))
                            .font(.system(size: timeFontSize * 0.8).monospacedDigit())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
            }
            .frame(width: cellWidth, height: cellHeight)
            .background(Color.primary.opacity(0.03))
            .border(Color.gray.opacity(0.2))
            .contentShape(Rectangle())

            // パートナーハイライトオーバーレイ
            if isPartnerHighlighted {
                Color.black.opacity(0.45)
                    .allowsHitTesting(false)
            }

            // チェックボックス (連携タイマーのみ)
            if linkColor != nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            store.toggleCheckState(slotId: slotId, userId: userId)
                        } label: {
                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: subFontSize * 2.0))
                                .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                    }
                }
            }

            // オーバーレイ
            if showOverlay {
                overlayView
                    .frame(width: cellWidth, height: cellHeight)
            }
        }
        .frame(width: cellWidth, height: cellHeight)
        #if os(macOS)
        .onHover { hover in onHoverChanged(hover) }
        #else
        .onTapGesture { onHoverChanged(true) }
        #endif
        .popover(isPresented: $showDurationPicker) {
            DurationPickerView { duration in
                store.startTimer(slotId: slotId, duration: duration)
                showDurationPicker = false
                onHoverChanged(false)
            }
        }
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlayView: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture {
                    onHoverChanged(false)
                }

            if isRunning {
                // 動作中: × ボタン
                Button {
                    store.stopTimer(slotId: slotId)
                    onHoverChanged(false)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: timeFontSize * 1.35))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else {
                // 停止中: リプレイ + 新規
                HStack(spacing: cellWidth * 0.12) {
                    // リプレイ (元の時間がある場合のみ)
                    if hasOriginal {
                        Button {
                            if let dur = slot?.originalDuration {
                                store.startTimer(slotId: slotId, duration: dur)
                            }
                            onHoverChanged(false)
                        } label: {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: timeFontSize * 1.275))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }

                    // 新規タイマー
                    Button {
                        showDurationPicker = true
                    } label: {
                        Image(systemName: "timer")
                            .font(.system(size: timeFontSize * 1.275))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - DurationPickerView

struct DurationPickerView: View {
    let onSelect: (TimeInterval) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showCustom = false
    @State private var customHours = ""
    @State private var customMinutes = ""

    private var customDuration: TimeInterval {
        let h = TimeInterval(Int(customHours) ?? 0)
        let m = TimeInterval(Int(customMinutes) ?? 0)
        return h * 3600 + m * 60
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            Text("タイマー時間を選択")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(timerDurations, id: \.seconds) { d in
                        Button {
                            onSelect(d.seconds)
                        } label: {
                            Text(d.label)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showCustom.toggle() }
                    } label: {
                        HStack {
                            Text("カスタム").frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: showCustom ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showCustom {
                        Divider()
                        VStack(spacing: 8) {
                            HStack(spacing: 4) {
                                numericField(text: $customHours, placeholder: "")
                                Text("時間").font(.system(size: 12)).foregroundStyle(.secondary)
                                numericField(text: $customMinutes, placeholder: "")
                                Text("分").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            if customDuration > 0 {
                                Text(formatTime(customDuration))
                                    .font(.system(size: 16, design: .monospaced).bold())
                                    .foregroundStyle(.secondary)
                            }
                            Button("開始") {
                                let dur = customDuration
                                if dur > 0 { onSelect(dur) }
                            }
                            .disabled(customDuration <= 0)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .keyboardShortcut(.return, modifiers: [])
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .frame(width: 200)
        .frame(maxHeight: 500)
        #else
        VStack(spacing: 0) {
            // 最上段: キャンセルボタン右上
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                    .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            // 一段下: タイトル
            Text("タイマー時間を選択")
                .font(.system(size: 20, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            Divider()

            // 選択エリア（残り全て使用）
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(timerDurations, id: \.seconds) { d in
                        Button {
                            onSelect(d.seconds)
                        } label: {
                            Text(d.label)
                                .font(.system(size: 20))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showCustom.toggle() }
                    } label: {
                        ZStack {
                            Text("カスタム")
                                .font(.system(size: 20))
                                .frame(maxWidth: .infinity, alignment: .center)
                            HStack {
                                Spacer()
                                Image(systemName: showCustom ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showCustom {
                        Divider()
                        VStack(spacing: 10) {
                            HStack(spacing: 4) {
                                numericField(text: $customHours, placeholder: "")
                                Text("時間").font(.system(size: 14)).foregroundStyle(.secondary)
                                numericField(text: $customMinutes, placeholder: "")
                                Text("分").font(.system(size: 14)).foregroundStyle(.secondary)
                            }
                            if customDuration > 0 {
                                Text(formatTime(customDuration))
                                    .font(.system(size: 20, design: .monospaced).bold())
                                    .foregroundStyle(.secondary)
                            }
                            Button("開始") {
                                let dur = customDuration
                                if dur > 0 { onSelect(dur) }
                            }
                            .disabled(customDuration <= 0)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .keyboardShortcut(.return, modifiers: [])
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    private func numericField(text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 40)
            .multilineTextAlignment(.center)
            .onChange(of: text.wrappedValue) { _, newValue in
                let filtered = newValue.filter { $0.isNumber }
                if filtered != newValue { text.wrappedValue = filtered }
            }
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
    }
}

#Preview {
    let store = TimerStore()
    let userId = store.data.users[0].id
    let slotId = "solo-\(userId)"
    return TimerCellView(slotId: slotId, userId: userId, cellWidth: 150, cellHeight: 100,
                         showOverlay: false, isPartnerHighlighted: false, onHoverChanged: { _ in })
        .environment(store)
}

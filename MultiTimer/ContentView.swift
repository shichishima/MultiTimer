import SwiftUI

struct ContentView: View {
    @Environment(TimerStore.self) private var store

    @State private var activeCell: (slotId: String, userId: String)? = nil
    #if os(iOS)
    @State private var scale: CGFloat = 0.6
    @State private var lastScale: CGFloat = 0.6
    #endif

    var body: some View {
        let _ = store.tick  // 毎秒再描画トリガー
        Group {
            #if os(macOS)
            if store.dataFileURL == nil {
                setupRequiredView
            } else {
                GeometryReader { geo in
                    let cols = max(1, store.data.visibleUsers.count)
                    let cW = geo.size.width / CGFloat(cols)
                    let hH = geo.size.height / 5.0 * 0.7
                    let tH = (geo.size.height - hH) / 4.0
                    timerGridContent(cellW: cW, timerCellH: tH, headerH: hH)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            #else
            // iOS: GeometryReader で画面いっぱい + 横スクロール + pinch
            GeometryReader { geo in
                let topPad: CGFloat = 10
                let bottomPad: CGFloat = 130
                let availH = geo.size.height - topPad - bottomPad
                let cols = max(1, store.data.visibleUsers.count)
                let hH = availH / 5.0 * 0.7
                let tH = (availH - hH) / 4.0
                let cW = max(min(tH * 1.5 * scale, 200), 150)
                let totalW = CGFloat(cols) * cW
                VStack(spacing: 0) {
                    Spacer().frame(height: topPad)
                    ScrollView(.horizontal, showsIndicators: false) {
                        timerGridContent(cellW: cW, timerCellH: tH, headerH: hH)
                            .frame(width: totalW, height: availH + bottomPad, alignment: .top)
                    }
                    .frame(width: geo.size.width, height: availH + bottomPad)
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { v in scale = max(0.5, min(1.2, lastScale * v)) }
                            .onEnded { _ in lastScale = scale }
                    )
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            #endif
        }
        .overlay(alignment: .top) {
            if let msg = store.saveErrorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(4)
                    .padding(.top, 4)
            }
        }
        .overlay {
            if store.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
            }
        }
    }

    private var setupRequiredView: some View {
        Text("設定画面から共有データを指定してください")
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func timerGridContent(cellW: CGFloat, timerCellH: CGFloat, headerH: CGFloat) -> some View {
        let columns = store.data.visibleUsers
        VStack(spacing: 0) {
            // ヘッダー行
            HStack(spacing: 0) {
                ForEach(columns) { user in
                    HeaderCellView(name: user.name, width: cellW, height: headerH)
                        .onTapGesture(count: 2) { store.reloadFromFile() }
                }
            }
            // タイマー行
            ForEach(0..<4, id: \.self) { rowIndex in
                HStack(spacing: 0) {
                    ForEach(columns) { user in
                        let slotIds = store.data.slotIds(for: user.id)
                        if rowIndex < slotIds.count {
                            let slotId = slotIds[rowIndex]
                            TimerCellView(
                                slotId: slotId,
                                userId: user.id,
                                cellWidth: cellW,
                                cellHeight: timerCellH,
                                showOverlay: activeCell?.slotId == slotId && activeCell?.userId == user.id,
                                isPartnerHighlighted: activeCell?.slotId == slotId && activeCell?.userId != user.id,
                                onHoverChanged: { isHovering in
                                    if isHovering {
                                        if activeCell?.slotId == slotId && activeCell?.userId == user.id {
                                            activeCell = nil  // 同セル再タップ: 解除
                                        } else {
                                            activeCell = (slotId: slotId, userId: user.id)
                                        }
                                    } else {
                                        if activeCell?.slotId == slotId && activeCell?.userId == user.id {
                                            activeCell = nil
                                        }
                                    }
                                }
                            )
                        } else {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: cellW, height: timerCellH)
                                .border(Color.gray.opacity(0.15))
                                .contentShape(Rectangle())
                                .onTapGesture { activeCell = nil }  // 空白タップ: 全解除
                        }
                    }
                }
            }
        }
    }
}

// MARK: - HeaderCellView

private struct HeaderCellView: View {
    let name: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Text(name)
            .font(.system(size: height * 0.45, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: width, height: height)
            .background(Color.primary.opacity(0.06))
            .border(Color.gray.opacity(0.2))
    }
}

#Preview {
    ContentView()
        .environment(TimerStore())
        .frame(width: 600, height: 400)
}

import SwiftUI

struct ContentView: View {
    @Environment(TimerStore.self) private var store

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif

    var body: some View {
        Group {
            #if os(iOS)
            if hSizeClass == .compact {
                // 縦画面: 横スクロール
                ScrollView(.horizontal, showsIndicators: false) {
                    timerGrid
                        .frame(minWidth: CGFloat(store.data.visibleUsers.count) * 120)
                }
            } else {
                // 横画面: 全表示
                GeometryReader { geo in
                    timerGrid
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            #else
            GeometryReader { geo in
                timerGrid
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
    }

    private var timerGrid: some View {
        TimelineView(.periodic(from: Date(), by: 1.0)) { _ in
            GeometryReader { geo in
                let columns = store.data.visibleUsers
                let colCount = max(1, columns.count)
                let cellW = geo.size.width / CGFloat(colCount)
                // 5行 (1見出し + 4タイマー)
                let cellH = geo.size.height / 5.0

                VStack(spacing: 0) {
                    // ヘッダー行
                    HStack(spacing: 0) {
                        ForEach(columns) { user in
                            HeaderCellView(name: user.name, width: cellW, height: cellH)
                        }
                    }
                    // タイマー行 (最大4行)
                    ForEach(0..<4, id: \.self) { rowIndex in
                        HStack(spacing: 0) {
                            ForEach(columns) { user in
                                let slotIds = store.data.slotIds(for: user.id)
                                if rowIndex < slotIds.count {
                                    let slotId = slotIds[rowIndex]
                                    TimerCellView(slotId: slotId, userId: user.id,
                                                  cellWidth: cellW, cellHeight: cellH)
                                } else {
                                    // 空セル
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(width: cellW, height: cellH)
                                        .border(Color.gray.opacity(0.15))
                                }
                            }
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
            .font(.system(size: height * 0.35, weight: .semibold))
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

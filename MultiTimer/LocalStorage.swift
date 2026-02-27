import Foundation

// MARK: - Security Scoped Bookmark (macOS)

#if os(macOS)
private let bookmarkKey = "dataFolderBookmark"

func saveBookmark(url: URL) {
    do {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    } catch {}
}

func resolveBookmark() -> URL? {
    guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
    var isStale = false
    do {
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale { saveBookmark(url: url) }
        return url
    } catch {
        return nil
    }
}
#elseif os(iOS)
private let bookmarkKey = "dataFolderBookmark"

func saveBookmark(url: URL) {
    if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }
}

func resolveBookmark() -> URL? {
    guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
    var isStale = false
    guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
    if isStale { saveBookmark(url: url) }
    return url
}
#endif

// MARK: - Save / Load

nonisolated func saveAppData(_ data: AppData, to fileURL: URL) throws {
    let yaml = encodeAppDataYAML(data)
    var coordinatorError: NSError?
    var writeError: Error?
    let coordinator = NSFileCoordinator()
    coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinatorError) { coordURL in
        do {
            try yaml.write(to: coordURL, atomically: false, encoding: .utf8)
        } catch {
            writeError = error
        }
    }
    if let err = coordinatorError { throw err }
    if let err = writeError { throw err }
}

func loadAppData(from fileURL: URL) throws -> AppData {
    let yaml = try String(contentsOf: fileURL, encoding: .utf8)
    return try decodeAppDataYAML(yaml)
}

// MARK: - YAML Encoder

nonisolated private func encodeAppDataYAML(_ data: AppData) -> String {
    let iso = ISO8601DateFormatter()
    var lines: [String] = []

    lines.append("lastModified: \(ys(iso.string(from: data.lastModified)))")

    if data.users.isEmpty {
        lines.append("users: []")
    } else {
        lines.append("users:")
        for u in data.users {
            lines.append("  - id: \(ys(u.id))")
            lines.append("    name: \(ys(u.name))")
            lines.append("    isVisible: \(u.isVisible)")
            lines.append("    displayOrder: \(u.displayOrder)")
        }
    }

    if data.links.isEmpty {
        lines.append("links: []")
    } else {
        lines.append("links:")
        for l in data.links {
            lines.append("  - id: \(ys(l.id))")
            lines.append("    userAId: \(ys(l.userAId))")
            lines.append("    userBId: \(ys(l.userBId))")
            lines.append("    colorHex: \(ys(l.colorHex))")
        }
    }

    if data.timerSlots.isEmpty {
        lines.append("timerSlots: []")
    } else {
        lines.append("timerSlots:")
        for s in data.timerSlots {
            lines.append("  - id: \(ys(s.id))")
            if let d = s.endDate {
                lines.append("    endDate: \(ys(iso.string(from: d)))")
            } else {
                lines.append("    endDate: ~")
            }
            if let dur = s.originalDuration {
                lines.append("    originalDuration: \(dur)")
            } else {
                lines.append("    originalDuration: ~")
            }
        }
    }

    let sortedCheckStates = data.checkStates.sorted { $0.key < $1.key }
    if sortedCheckStates.isEmpty {
        lines.append("checkStates: []")
    } else {
        lines.append("checkStates:")
        for (key, value) in sortedCheckStates {
            lines.append("  - key: \(ys(key))")
            lines.append("    value: \(ys(value ? "true" : "false"))")
        }
    }

    return lines.joined(separator: "\n") + "\n"
}

/// YAML 文字列リテラル（ダブルクォート）
private func ys(_ s: String) -> String {
    let escaped = s
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

// MARK: - YAML Decoder

private enum YAMLDecodeError: Error {
    case malformed(String)
}

func decodeAppDataYAML(_ yaml: String) throws -> AppData {
    let iso = ISO8601DateFormatter()

    var lastModified = Date()
    var users: [AppUser] = []
    var links: [TimerLink] = []
    var timerSlots: [TimerSlot] = []
    var checkStates: [String: Bool] = [:]

    enum Section { case none, users, links, timerSlots, checkStates }
    var section = Section.none
    var item: [String: String] = [:]

    func flushItem() {
        guard !item.isEmpty else { return }
        switch section {
        case .users:
            if let u = parseUser(item) { users.append(u) }
        case .links:
            if let l = parseLink(item) { links.append(l) }
        case .timerSlots:
            if let s = parseSlot(item, iso: iso) { timerSlots.append(s) }
        case .checkStates:
            if let key = item["key"], !key.isEmpty,
               let valueStr = item["value"] {
                checkStates[key] = (valueStr == "true")
            }
        case .none:
            break
        }
        item = [:]
    }

    for line in yaml.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

        // トップレベルのセクションヘッダー
        if trimmed.hasPrefix("lastModified:") {
            let v = extractScalar(trimmed, key: "lastModified")
            if let d = iso.date(from: v) { lastModified = d }

        } else if trimmed == "users:" {
            flushItem(); section = .users; users = []
        } else if trimmed == "links:" {
            flushItem(); section = .links; links = []
        } else if trimmed == "timerSlots:" {
            flushItem(); section = .timerSlots; timerSlots = []
        } else if trimmed == "checkStates:" {
            flushItem(); section = .checkStates; checkStates = [:]

        } else if trimmed == "users: []" {
            flushItem(); section = .none; users = []
        } else if trimmed == "links: []" {
            flushItem(); section = .none; links = []
        } else if trimmed == "timerSlots: []" {
            flushItem(); section = .none; timerSlots = []
        } else if trimmed == "checkStates: []" {
            flushItem(); section = .none; checkStates = [:]

        } else if line.hasPrefix("  - ") {
            // 新しいリスト項目の開始
            flushItem()
            let rest = String(line.dropFirst(4))
            if let kv = parseKV(rest) { item[kv.0] = kv.1 }

        } else if line.hasPrefix("    ") {
            // リスト項目の続きのキー値
            let rest = String(line.dropFirst(4))
            if let kv = parseKV(rest) { item[kv.0] = kv.1 }
        }
    }
    flushItem()

    var result = AppData()
    result.users = users.isEmpty ? result.users : users
    result.links = links
    result.timerSlots = timerSlots
    result.lastModified = lastModified
    result.checkStates = checkStates
    result.ensureSlots()
    return result
}

// MARK: - Parse Helpers

/// "key: value" → ("key", "value")
private func parseKV(_ line: String) -> (String, String)? {
    guard let colonRange = line.range(of: ": ") else {
        // "key: ~" や "key:" のケース
        if line.hasSuffix(":") {
            let key = String(line.dropLast())
            return (key, "")
        }
        return nil
    }
    let key = String(line[line.startIndex..<colonRange.lowerBound])
    let value = String(line[colonRange.upperBound...])
    return (key, unquote(value))
}

/// "key: value" からvalueを取り出す（トップレベル用）
private func extractScalar(_ line: String, key: String) -> String {
    let prefix = "\(key): "
    guard line.hasPrefix(prefix) else { return "" }
    return unquote(String(line.dropFirst(prefix.count)))
}

/// "value" → value, ~ → ""
private func unquote(_ s: String) -> String {
    let t = s.trimmingCharacters(in: .whitespaces)
    if t == "~" || t == "null" { return "" }
    if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 {
        let inner = String(t.dropFirst().dropLast())
        return inner
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
    return t
}

// MARK: - Struct Parsers

private func parseUser(_ d: [String: String]) -> AppUser? {
    guard let id = d["id"], !id.isEmpty,
          let name = d["name"],
          let isVisible = d["isVisible"],
          let displayOrder = d["displayOrder"].flatMap(Int.init) else { return nil }
    return AppUser(id: id, name: name,
                   isVisible: isVisible == "true",
                   displayOrder: displayOrder)
}

private func parseLink(_ d: [String: String]) -> TimerLink? {
    guard let id = d["id"], !id.isEmpty,
          let userAId = d["userAId"], !userAId.isEmpty,
          let userBId = d["userBId"], !userBId.isEmpty,
          let colorHex = d["colorHex"] else { return nil }
    return TimerLink(id: id, userAId: userAId, userBId: userBId,
                     colorHex: colorHex.isEmpty ? "#4A90D9" : colorHex)
}

private func parseSlot(_ d: [String: String], iso: ISO8601DateFormatter) -> TimerSlot? {
    guard let id = d["id"], !id.isEmpty else { return nil }
    let endDate = d["endDate"].flatMap { iso.date(from: $0) }
    let originalDuration = d["originalDuration"].flatMap(Double.init)
    return TimerSlot(id: id, endDate: endDate, originalDuration: originalDuration)
}

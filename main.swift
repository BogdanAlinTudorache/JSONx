import SwiftUI
import AppKit

// MARK: - App Identity

let appName    = "JSONx"
let appVersion = "2.0.0"
let appTagline = "Format, minify, validate, and compare JSON — right from your menu bar."
let githubRepo = "BogdanAlinTudorache/JSONx"

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var n: UInt64 = 0; Scanner(string: s).scanHexInt64(&n)
        self.init(
            red:   Double((n >> 16) & 0xFF) / 255,
            green: Double((n >> 8)  & 0xFF) / 255,
            blue:  Double( n        & 0xFF) / 255
        )
    }
}

// MARK: - Cursor Extension

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Models

enum ViewMode: String, CaseIterable {
    case format   = "Format"
    case compare  = "Compare"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .format:   return "doc.text"
        case .compare:  return "arrow.left.arrow.right"
        case .settings: return "gearshape"
        }
    }
}

enum IndentStyle: String, CaseIterable {
    case two  = "2 Spaces"
    case four = "4 Spaces"
    case tab  = "Tab"

    var indent: String {
        switch self {
        case .two:  return "  "
        case .four: return "    "
        case .tab:  return "\t"
        }
    }

    // Stored key — kept short for @AppStorage
    var value: String {
        switch self {
        case .two:  return "2"
        case .four: return "4"
        case .tab:  return "tab"
        }
    }

    static func from(stored: String) -> IndentStyle {
        allCases.first { $0.value == stored } ?? .two
    }
}

enum AppTheme: String, CaseIterable {
    case system = "System"
    case light  = "Light"
    case dark   = "Dark"
}

enum ColorPreset: String, CaseIterable {
    case `default`  = "Default"
    case tokyoNight = "Tokyo Night"
}

// MARK: - Diff Models

enum DiffState: Equatable {
    case idle
    case identical
    case differences
    case error(String)
}

enum DiffType: String {
    case added   = "Added"
    case removed = "Removed"
    case changed = "Changed"

    var icon: String {
        switch self {
        case .added:   return "plus.circle.fill"
        case .removed: return "minus.circle.fill"
        case .changed: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .added:   return .green
        case .removed: return .red
        case .changed: return .orange
        }
    }

    var label: String {
        switch self {
        case .added:   return "RIGHT only"
        case .removed: return "LEFT only"
        case .changed: return "Changed"
        }
    }
}

struct DiffEntry: Identifiable {
    let id = UUID()
    let type: DiffType
    let path: String
    let leftValue: String?
    let rightValue: String?
}

// MARK: - ViewModel

final class JSONMonitor: ObservableObject {
    @Published var inputText:       String  = ""
    @Published var outputText:      String  = ""
    @Published var errorMessage:    String? = nil
    @Published var currentView:     ViewMode = .format
    @Published var justCopied:      Bool    = false

    @Published var compareLeft:     String  = ""
    @Published var compareRight:    String  = ""
    @Published var compareResult:   String  = ""
    @Published var diffEntries:     [DiffEntry] = []
    @Published var diffState:       DiffState = .idle

    @Published var updateStatus:    String  = ""
    @Published var isCheckingUpdate: Bool   = false

    @AppStorage("indentStyle")  var indentStyle:  String = "2"
    @AppStorage("sortKeys")     var sortKeys:     Bool   = false
    @AppStorage("appTheme")     var appTheme:     String = "system"
    @AppStorage("colorPreset")  var colorPreset:  String = "default"

    // MARK: JSONC comment stripper

    private func stripComments(from json: String) -> String {
        var result = ""
        var inString = false
        var escaped  = false
        var i = json.startIndex

        while i < json.endIndex {
            let char = json[i]

            if escaped {
                result.append(char); escaped = false
                i = json.index(after: i); continue
            }
            if char == "\\" && inString {
                result.append(char); escaped = true
                i = json.index(after: i); continue
            }
            if char == "\"" {
                inString.toggle(); result.append(char)
                i = json.index(after: i); continue
            }
            if !inString && char == "/" {
                let next = json.index(after: i)
                if next < json.endIndex {
                    if json[next] == "/" {
                        while i < json.endIndex && json[i] != "\n" { i = json.index(after: i) }
                        if i < json.endIndex { result.append("\n"); i = json.index(after: i) }
                        continue
                    }
                    if json[next] == "*" {
                        i = json.index(after: next)
                        while i < json.endIndex {
                            if json[i] == "*" {
                                let afterStar = json.index(after: i)
                                if afterStar < json.endIndex && json[afterStar] == "/" {
                                    i = json.index(after: afterStar); break
                                }
                            }
                            i = json.index(after: i)
                        }
                        continue
                    }
                }
            }
            result.append(char)
            i = json.index(after: i)
        }
        return result
    }

    // MARK: JSON operations

    func formatJSON() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Input is empty"; return
        }
        let cleaned = stripComments(from: inputText)
        guard let data = cleaned.data(using: .utf8) else { errorMessage = "Invalid encoding"; return }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            var opts: JSONSerialization.WritingOptions = [.prettyPrinted]
            if sortKeys { opts.insert(.sortedKeys) }
            let pretty = try JSONSerialization.data(withJSONObject: obj, options: opts)
            guard var str = String(data: pretty, encoding: .utf8) else { return }

            let style = IndentStyle.from(stored: indentStyle)
            if style != .two {
                str = str.components(separatedBy: "\n").map { line in
                    let spaces = line.prefix(while: { $0 == " " }).count
                    return String(repeating: style.indent, count: spaces / 2) + line.dropFirst(spaces)
                }.joined(separator: "\n")
            }
            outputText = str; errorMessage = nil
        } catch {
            errorMessage = "Parse error: \(error.localizedDescription)"
        }
    }

    func minifyJSON() {
        let cleaned = stripComments(from: inputText)
        guard let data = cleaned.data(using: .utf8) else { errorMessage = "Invalid encoding"; return }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            let compact = try JSONSerialization.data(withJSONObject: obj, options: [])
            outputText = String(data: compact, encoding: .utf8) ?? ""; errorMessage = nil
        } catch {
            errorMessage = "Parse error: \(error.localizedDescription)"
        }
    }

    func compareJSONs() {
        guard !compareLeft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !compareRight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            diffState = .error("Both JSON inputs are required"); diffEntries = []; compareResult = ""; return
        }
        let cleanedLeft  = stripComments(from: compareLeft)
        let cleanedRight = stripComments(from: compareRight)
        guard let leftData  = cleanedLeft.data(using: .utf8),
              let rightData = cleanedRight.data(using: .utf8) else {
            diffState = .error("Invalid encoding"); diffEntries = []; compareResult = ""; return
        }
        do {
            let leftObj  = try JSONSerialization.jsonObject(with: leftData)
            let rightObj = try JSONSerialization.jsonObject(with: rightData)
            if formatForComparison(leftObj) == formatForComparison(rightObj) {
                diffState = .identical; diffEntries = []; compareResult = ""
            } else {
                var entries: [DiffEntry] = []
                collectDiffEntries(leftObj, rightObj, path: "$", entries: &entries)
                diffEntries = entries
                diffState = .differences
                compareResult = entries.map { e in
                    switch e.type {
                    case .added:   return "+ \(e.path): \(e.rightValue ?? "")"
                    case .removed: return "- \(e.path): \(e.leftValue ?? "")"
                    case .changed: return "~ \(e.path): \(e.leftValue ?? "") → \(e.rightValue ?? "")"
                    }
                }.joined(separator: "\n")
            }
        } catch {
            diffState = .error("Invalid JSON — check syntax in both panels"); diffEntries = []; compareResult = ""
        }
    }

    func swapCompareInputs() {
        let tmp = compareLeft; compareLeft = compareRight; compareRight = tmp
        if diffState != .idle { compareJSONs() }
    }

    func clearCompare() {
        compareLeft = ""; compareRight = ""; compareResult = ""; diffEntries = []; diffState = .idle
    }

    func copyCompareResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(compareResult, forType: .string)
    }

    private func formatForComparison(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    private func collectDiffEntries(_ left: Any, _ right: Any, path: String, entries: inout [DiffEntry]) {
        if let leftDict = left as? [String: Any], let rightDict = right as? [String: Any] {
            for key in Set(leftDict.keys).union(rightDict.keys).sorted() {
                let p = "\(path).\(key)"
                if leftDict[key] == nil {
                    entries.append(DiffEntry(type: .added, path: p, leftValue: nil, rightValue: stringify(rightDict[key]!)))
                } else if rightDict[key] == nil {
                    entries.append(DiffEntry(type: .removed, path: p, leftValue: stringify(leftDict[key]!), rightValue: nil))
                } else {
                    let l = leftDict[key]!, r = rightDict[key]!
                    if !valuesEqual(l, r) {
                        if l is [String: Any] && r is [String: Any] {
                            collectDiffEntries(l, r, path: p, entries: &entries)
                        } else if l is [Any] && r is [Any] {
                            collectDiffEntries(l, r, path: p, entries: &entries)
                        } else {
                            entries.append(DiffEntry(type: .changed, path: p, leftValue: stringify(l), rightValue: stringify(r)))
                        }
                    }
                }
            }
        } else if let leftArr = left as? [Any], let rightArr = right as? [Any] {
            if leftArr.count != rightArr.count {
                entries.append(DiffEntry(type: .changed, path: "\(path).length", leftValue: "\(leftArr.count)", rightValue: "\(rightArr.count)"))
            }
            for idx in 0..<max(leftArr.count, rightArr.count) {
                let p = "\(path)[\(idx)]"
                if idx >= leftArr.count {
                    entries.append(DiffEntry(type: .added, path: p, leftValue: nil, rightValue: stringify(rightArr[idx])))
                } else if idx >= rightArr.count {
                    entries.append(DiffEntry(type: .removed, path: p, leftValue: stringify(leftArr[idx]), rightValue: nil))
                } else if !valuesEqual(leftArr[idx], rightArr[idx]) {
                    if leftArr[idx] is [String: Any] && rightArr[idx] is [String: Any] {
                        collectDiffEntries(leftArr[idx], rightArr[idx], path: p, entries: &entries)
                    } else if leftArr[idx] is [Any] && rightArr[idx] is [Any] {
                        collectDiffEntries(leftArr[idx], rightArr[idx], path: p, entries: &entries)
                    } else {
                        entries.append(DiffEntry(type: .changed, path: p, leftValue: stringify(leftArr[idx]), rightValue: stringify(rightArr[idx])))
                    }
                }
            }
        } else {
            entries.append(DiffEntry(type: .changed, path: path, leftValue: stringify(left), rightValue: stringify(right)))
        }
    }

    private func stringify(_ value: Any) -> String {
        if let s = value as? String  { return "\"\(s)\"" }
        if let n = value as? NSNumber { return "\(n)" }
        if value is NSNull            { return "null" }
        if value is [String: Any]     { return "{...}" }
        if value is [Any]             { return "[...]" }
        return "\(value)"
    }

    private func valuesEqual(_ a: Any?, _ b: Any?) -> Bool {
        if a is NSNull && b is NSNull { return true }
        if let aStr = a as? String, let bStr = b as? String { return aStr == bStr }
        if let aBool = a as? Bool, let bBool = b as? Bool { return aBool == bBool }
        if let aNum = a as? NSNumber, let bNum = b as? NSNumber { return aNum.isEqual(to: bNum) }
        if let aDict = a as? [String: Any], let bDict = b as? [String: Any] {
            return NSDictionary(dictionary: aDict).isEqual(to: bDict)
        }
        if let aArr = a as? [Any], let bArr = b as? [Any] {
            return NSArray(array: aArr).isEqual(to: bArr)
        }
        return false
    }

    // MARK: Clipboard

    func pasteFromClipboard() {
        if let str = NSPasteboard.general.string(forType: .string) { inputText = str }
    }

    func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
        justCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.justCopied = false }
    }

    var stats: String {
        guard !outputText.isEmpty, let data = outputText.data(using: .utf8) else { return "" }
        return "\(outputText.components(separatedBy: "\n").count) lines, \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
    }

    // MARK: Updates

    func checkForUpdates() {
        isCheckingUpdate = true; updateStatus = ""
        guard let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest") else {
            isCheckingUpdate = false; updateStatus = "Invalid URL"; return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                self.isCheckingUpdate = false
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag  = json["tag_name"] as? String else {
                    self.updateStatus = "Could not check for updates"; return
                }
                let latest = tag.trimmingCharacters(in: .init(charactersIn: "v"))
                self.updateStatus = latest == appVersion
                    ? "✓ v\(appVersion) — up to date"
                    : "↑ v\(latest) available — download at GitHub"
            }
        }.resume()
    }
}

// MARK: - Shared Toolbar

private func makeToolbar(monitor: JSONMonitor) -> some View {
    HStack(spacing: 16) {
        HStack(spacing: 8) {
            Image(systemName: "curlybraces")
                .font(.title3).foregroundStyle(.blue)
            Text(appName)
                .font(.title3).fontWeight(.semibold)
        }
        Spacer()
        ForEach(ViewMode.allCases, id: \.self) { mode in
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { monitor.currentView = mode }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: mode.icon)
                    Text(mode.rawValue)
                }
                .font(.callout)
                .foregroundStyle(monitor.currentView == mode ? .primary : .secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(monitor.currentView == mode ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }
    .padding(.horizontal, 20).padding(.vertical, 12)
}

// MARK: - Editor View

struct JSONEditorView: View {
    @ObservedObject var monitor: JSONMonitor
    @State private var justPasted = false

    var body: some View {
        VStack(spacing: 0) {
            makeToolbar(monitor: monitor)
            Divider()
            GeometryReader { geo in
                HStack(spacing: 0) {
                    // Left: Input
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("INPUT")
                                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                if let str = NSPasteboard.general.string(forType: .string) {
                                    monitor.inputText = str
                                    justPasted = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { justPasted = false }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: justPasted ? "checkmark.circle.fill" : "doc.on.clipboard")
                                    Text(justPasted ? "Pasted!" : "Paste")
                                }
                                .font(.caption)
                                .foregroundStyle(justPasted ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            .cursor(.pointingHand)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)

                        TextEditor(text: $monitor.inputText)
                            .font(.system(size: 13, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .background(Color(nsColor: .textBackgroundColor))
                            .padding(.horizontal, 16).padding(.bottom, 8)
                    }
                    .frame(width: geo.size.width / 2)

                    // Center: Actions
                    VStack(spacing: 12) {
                        Spacer()

                        Button { monitor.formatJSON() } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "wand.and.stars").font(.title3)
                                Text("Format").font(.caption2)
                            }
                            .frame(width: 56)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.regular)
                        .keyboardShortcut("f", modifiers: [.command])

                        Button { monitor.minifyJSON() } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "arrow.down.right.and.arrow.up.left").font(.title3)
                                Text("Minify").font(.caption2)
                            }
                            .frame(width: 56)
                        }
                        .buttonStyle(.bordered).controlSize(.regular)
                        .keyboardShortcut("m", modifiers: [.command])

                        if let err = monitor.errorMessage {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red).font(.caption)
                                .help(err)
                        }

                        Spacer()
                    }
                    .frame(width: 72)

                    // Right: Output
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("OUTPUT")
                                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                            Spacer()
                            if !monitor.outputText.isEmpty {
                                Text(monitor.stats).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)

                        TextEditor(text: .constant(monitor.outputText))
                            .font(.system(size: 13, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .background(Color(nsColor: .textBackgroundColor))
                            .padding(.horizontal, 16).padding(.bottom, 8)
                    }
                    .frame(width: geo.size.width / 2 - 72)
                }
            }
            Divider()
            // Bottom bar
            HStack(spacing: 12) {
                if !monitor.outputText.isEmpty {
                    Button {
                        monitor.copyOutput()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: monitor.justCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            Text(monitor.justCopied ? "Copied!" : "Copy Output")
                        }
                        .font(.caption)
                        .foregroundStyle(monitor.justCopied ? .green : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .cursor(.pointingHand)
                }

                if let err = monitor.errorMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(err)
                    }
                    .font(.caption2).foregroundStyle(.red)
                    .lineLimit(1)
                }

                Spacer()

                Button {
                    monitor.inputText = ""; monitor.outputText = ""; monitor.errorMessage = nil
                } label: {
                    HStack(spacing: 4) { Image(systemName: "trash"); Text("Clear") }
                        .font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("k", modifiers: [.command])
                .cursor(.pointingHand)

                Divider().frame(height: 12)

                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.tertiary)
                    .cursor(.pointingHand)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }
}

// MARK: - Compare View

struct CompareView: View {
    @ObservedObject var monitor: JSONMonitor
    @State private var copiedDiff = false
    @State private var activeFilter: DiffType? = nil

    private var addedCount: Int   { monitor.diffEntries.filter { $0.type == .added }.count }
    private var removedCount: Int { monitor.diffEntries.filter { $0.type == .removed }.count }
    private var changedCount: Int { monitor.diffEntries.filter { $0.type == .changed }.count }

    private var filteredEntries: [DiffEntry] {
        guard let filter = activeFilter else { return monitor.diffEntries }
        return monitor.diffEntries.filter { $0.type == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            makeToolbar(monitor: monitor)
            Divider()
            GeometryReader { geo in
                VStack(spacing: 0) {
                    // Editor panels with swap button
                    HStack(spacing: 0) {
                        editorPanel(label: "LEFT JSON", text: $monitor.compareLeft)
                        VStack {
                            Spacer()
                            Button { monitor.swapCompareInputs() } label: {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.caption).fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .cursor(.pointingHand)
                            .help("Swap left and right")
                            Spacer()
                        }
                        .frame(width: 40)
                        editorPanel(label: "RIGHT JSON", text: $monitor.compareRight)
                    }
                    .frame(height: geo.size.height * 0.42)
                    .padding(.horizontal, 20).padding(.top, 12)

                    // Action bar
                    HStack(spacing: 12) {
                        Button {
                            activeFilter = nil
                            monitor.compareJSONs()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.left.arrow.right.circle.fill")
                                Text("Compare")
                            }.font(.callout).fontWeight(.medium)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .keyboardShortcut("d", modifiers: [.command])

                        Button {
                            monitor.clearCompare()
                            activeFilter = nil
                            copiedDiff = false
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Clear")
                            }.font(.callout)
                        }
                        .buttonStyle(.bordered).controlSize(.large)

                        Spacer()

                        if !monitor.diffEntries.isEmpty {
                            Button {
                                monitor.copyCompareResult()
                                copiedDiff = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedDiff = false }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: copiedDiff ? "checkmark.circle.fill" : "doc.on.doc")
                                    Text(copiedDiff ? "Copied!" : "Copy Diff")
                                }
                                .font(.callout)
                                .foregroundStyle(copiedDiff ? .green : Color.accentColor)
                            }
                            .buttonStyle(.plain)
                            .cursor(.pointingHand)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 10)

                    Divider()

                    // Results section
                    VStack(alignment: .leading, spacing: 0) {
                        if monitor.diffState == .differences {
                            // Filter bar
                            HStack(spacing: 8) {
                                Text("RESULTS").font(.caption).fontWeight(.bold).foregroundStyle(.secondary)
                                Spacer()
                                filterBadge(type: nil, label: "All", count: monitor.diffEntries.count, color: .secondary)
                                if addedCount > 0 {
                                    filterBadge(type: .added, label: "Added", count: addedCount, color: .green)
                                }
                                if removedCount > 0 {
                                    filterBadge(type: .removed, label: "Removed", count: removedCount, color: .red)
                                }
                                if changedCount > 0 {
                                    filterBadge(type: .changed, label: "Changed", count: changedCount, color: .orange)
                                }
                            }
                            .padding(.horizontal, 20).padding(.vertical, 8)
                            Divider()
                        }

                        ScrollView {
                            switch monitor.diffState {
                            case .idle:
                                Text("Paste two JSON documents above and click Compare.")
                                    .font(.callout).foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 40)

                            case .identical:
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.green).font(.title2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("No differences found")
                                            .font(.callout).fontWeight(.medium)
                                        Text("Both JSON documents are structurally identical.")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 32)

                            case .error(let msg):
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red).font(.title2)
                                    Text(msg).font(.callout).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 32)

                            case .differences:
                                LazyVStack(alignment: .leading, spacing: 1) {
                                    ForEach(filteredEntries) { entry in
                                        diffRow(entry)
                                    }
                                }
                                .padding(.horizontal, 20).padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            Divider()
            HStack {
                if monitor.diffState == .differences {
                    Text("\(filteredEntries.count) of \(monitor.diffEntries.count) difference\(monitor.diffEntries.count == 1 ? "" : "s")")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.tertiary)
                    .cursor(.pointingHand)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    // MARK: - Filter badge (clickable)

    private func filterBadge(type: DiffType?, label: String, count: Int, color: Color) -> some View {
        let isActive = activeFilter == type
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                activeFilter = (activeFilter == type) ? nil : type
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(count)").fontWeight(.semibold)
                Text(label)
            }
            .font(.caption)
            .foregroundStyle(isActive ? .white : color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(isActive ? color : color.opacity(0.12))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }

    // MARK: - Diff row

    private func diffRow(_ entry: DiffEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.type.icon)
                .foregroundStyle(entry.type.color)
                .font(.system(size: 13))
                .frame(width: 16, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.path)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                switch entry.type {
                case .added:
                    valueLabel("RIGHT", entry.rightValue ?? "", color: .green)
                case .removed:
                    valueLabel("LEFT", entry.leftValue ?? "", color: .red)
                case .changed:
                    HStack(spacing: 0) {
                        valueLabel("LEFT", entry.leftValue ?? "", color: .red)
                        Image(systemName: "arrow.right")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                        valueLabel("RIGHT", entry.rightValue ?? "", color: .green)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(entry.type.color.opacity(0.04))
        .cornerRadius(6)
    }

    private func valueLabel(_ side: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(side)
                .font(.system(size: 9, weight: .bold, design: .default))
                .foregroundStyle(color.opacity(0.8))
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.08))
        .cornerRadius(3)
    }

    // MARK: - Editor panel

    private func editorPanel(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var monitor: JSONMonitor

    var body: some View {
        VStack(spacing: 0) {
            makeToolbar(monitor: monitor)
            Divider()

            ScrollView {
                VStack(spacing: 1) {
                    // Formatting group
                    sectionHeader("Formatting")

                    settingRow {
                        HStack {
                            settingLabel("Indentation", icon: "increase.indent", subtitle: nil)
                            Spacer()
                            Picker("", selection: $monitor.indentStyle) {
                                ForEach(IndentStyle.allCases, id: \.value) { Text($0.rawValue).tag($0.value) }
                            }
                            .pickerStyle(.segmented).labelsHidden()
                            .frame(width: 200)
                        }
                    }

                    settingRow {
                        HStack {
                            settingLabel("Sort Keys", icon: "arrow.up.arrow.down", subtitle: "Alphabetically sort object keys")
                            Spacer()
                            Toggle("", isOn: $monitor.sortKeys).toggleStyle(.switch).labelsHidden()
                        }
                    }

                    // Appearance group
                    sectionHeader("Appearance")

                    settingRow {
                        HStack {
                            settingLabel("Theme", icon: "circle.lefthalf.filled", subtitle: nil)
                            Spacer()
                            Picker("", selection: $monitor.appTheme) {
                                ForEach(AppTheme.allCases, id: \.rawValue) {
                                    Text($0.rawValue).tag($0.rawValue.lowercased())
                                }
                            }
                            .pickerStyle(.segmented).labelsHidden()
                            .frame(width: 200)
                        }
                    }

                    settingRow {
                        HStack {
                            settingLabel("Color Preset", icon: "paintpalette", subtitle: nil)
                            Spacer()
                            Picker("", selection: $monitor.colorPreset) {
                                ForEach(ColorPreset.allCases, id: \.rawValue) {
                                    Text($0.rawValue).tag($0.rawValue)
                                }
                            }
                            .pickerStyle(.segmented).labelsHidden()
                            .frame(width: 200)
                        }
                    }

                    // Shortcuts group
                    sectionHeader("Shortcuts")

                    settingRow {
                        VStack(spacing: 0) {
                            shortcutRow("Format JSON",  "⌘F", isLast: false)
                            shortcutRow("Minify JSON",  "⌘M", isLast: false)
                            shortcutRow("Compare",      "⌘D", isLast: false)
                            shortcutRow("Clear All",    "⌘K", isLast: false)
                            shortcutRow("Paste",        "⌘V", isLast: true)
                        }
                    }

                    // About group
                    sectionHeader("About")

                    settingRow {
                        HStack(spacing: 12) {
                            Image(systemName: "curlybraces")
                                .font(.title2).foregroundStyle(.blue)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(appName).font(.callout).fontWeight(.semibold)
                                    Text("v\(appVersion)").font(.caption).foregroundStyle(.tertiary)
                                }
                                Text(appTagline)
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Link("GitHub", destination: URL(string: "https://github.com/\(githubRepo)")!)
                                .font(.caption)
                        }
                    }

                    settingRow {
                        HStack {
                            settingLabel("Updates", icon: "arrow.triangle.2.circlepath", subtitle: monitor.updateStatus.isEmpty ? nil : monitor.updateStatus)
                            Spacer()
                            Button(monitor.isCheckingUpdate ? "Checking..." : "Check Now") {
                                monitor.checkForUpdates()
                            }
                            .font(.caption)
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(monitor.isCheckingUpdate)
                        }
                    }

                    settingRow {
                        HStack {
                            Image(systemName: "lock.shield")
                                .font(.caption).foregroundStyle(.green)
                                .frame(width: 20)
                            Text("All data stored locally. Nothing leaves your Mac.")
                                .font(.caption2).foregroundStyle(.tertiary)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }

            Divider()
            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.tertiary)
                    .cursor(.pointingHand)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    // MARK: - Setting components

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption).fontWeight(.bold).foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 16).padding(.bottom, 4)
    }

    private func settingRow<C: View>(@ViewBuilder content: () -> C) -> some View {
        content()
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
    }

    private func settingLabel(_ title: String, icon: String, subtitle: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                if let sub = subtitle {
                    Text(sub).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func shortcutRow(_ action: String, _ shortcut: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(action).font(.caption)
                Spacer()
                Text(shortcut)
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1)).cornerRadius(3)
            }
            .padding(.vertical, 5)
            if !isLast {
                Divider()
            }
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @ObservedObject var monitor: JSONMonitor
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Group {
            switch monitor.currentView {
            case .format:   JSONEditorView(monitor: monitor)
            case .compare:  CompareView(monitor: monitor)
            case .settings: SettingsView(monitor: monitor)
            }
        }
        .background(themedBackground)
        .onAppear  { applyTheme() }
        .onChange(of: monitor.appTheme)    { _ in applyTheme() }
        .onChange(of: monitor.colorPreset) { _ in applyTheme() }
    }

    private var themedBackground: Color {
        guard monitor.colorPreset == ColorPreset.tokyoNight.rawValue else { return .clear }
        return colorScheme == .dark ? Color(hex: "24283b") : Color(hex: "e6e7ed")
    }

    private func applyTheme() {
        let t = AppTheme(rawValue: monitor.appTheme.capitalized) ?? .system
        NSApp.appearance = t == .light ? NSAppearance(named: .aqua)
                         : t == .dark  ? NSAppearance(named: .darkAqua)
                         : nil
    }
}

// MARK: - App Entry

@main
struct JSONxApp: App {
    @StateObject private var monitor = JSONMonitor()

    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor)
                .frame(width: 900, height: 700)
        } label: {
            Image(systemName: "curlybraces")
            Text(appName)
        }
        .menuBarExtraStyle(.window)
    }
}

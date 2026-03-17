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
            compareResult = "Both JSON inputs required"; return
        }
        let cleanedLeft  = stripComments(from: compareLeft)
        let cleanedRight = stripComments(from: compareRight)
        guard let leftData  = cleanedLeft.data(using: .utf8),
              let rightData = cleanedRight.data(using: .utf8) else {
            compareResult = "Invalid encoding"; return
        }
        do {
            let leftObj  = try JSONSerialization.jsonObject(with: leftData)
            let rightObj = try JSONSerialization.jsonObject(with: rightData)
            if formatForComparison(leftObj) == formatForComparison(rightObj) {
                compareResult = "✓ JSONs are identical"
            } else {
                compareResult = "≠ Differences:\n\(findDifferences(leftObj, rightObj))"
            }
        } catch {
            compareResult = "✗ Parse error"
        }
    }

    private func formatForComparison(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    private func findDifferences(_ left: Any, _ right: Any) -> String {
        var diffs: [String] = []
        collectDifferences(left, right, path: "", diffs: &diffs)
        return diffs.isEmpty ? "No differences" : diffs.prefix(20).joined(separator: "\n")
    }

    private func collectDifferences(_ left: Any, _ right: Any, path: String, diffs: inout [String]) {
        if let leftDict = left as? [String: Any], let rightDict = right as? [String: Any] {
            for key in Set(leftDict.keys).union(rightDict.keys).sorted() {
                let p = path.isEmpty ? key : "\(path).\(key)"
                if leftDict[key] == nil {
                    diffs.append("+ \(p): only in RIGHT")
                } else if rightDict[key] == nil {
                    diffs.append("- \(p): only in LEFT")
                } else {
                    let l = leftDict[key]!, r = rightDict[key]!
                    if !valuesEqual(l, r) {
                        if l is [String: Any] && r is [String: Any] { collectDifferences(l, r, path: p, diffs: &diffs) }
                        else if l is [Any] && r is [Any] { collectDifferences(l, r, path: p, diffs: &diffs) }
                        else { diffs.append("~ \(p): \(stringify(l)) → \(stringify(r))") }
                    }
                }
            }
        } else if let leftArr = left as? [Any], let rightArr = right as? [Any] {
            if leftArr.count != rightArr.count {
                diffs.append("~ \(path): array length \(leftArr.count) → \(rightArr.count)")
            }
            for idx in 0..<min(leftArr.count, rightArr.count) {
                let p = "\(path)[\(idx)]"
                if !valuesEqual(leftArr[idx], rightArr[idx]) {
                    if leftArr[idx] is [String: Any] && rightArr[idx] is [String: Any] {
                        collectDifferences(leftArr[idx], rightArr[idx], path: p, diffs: &diffs)
                    } else {
                        diffs.append("~ \(p): \(stringify(leftArr[idx])) → \(stringify(rightArr[idx]))")
                    }
                }
            }
        } else {
            diffs.append("~ \(path): type mismatch")
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
        if a as? String == b as? String { return true }
        if a as? Int    == b as? Int    { return true }
        if a as? Double == b as? Double { return true }
        if a as? Bool   == b as? Bool   { return true }
        if let aDict = a as? [String: Any], let bDict = b as? [String: Any] {
            return NSDictionary(dictionary: aDict).isEqual(to: bDict)
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

    var body: some View {
        VStack(spacing: 0) {
            makeToolbar(monitor: monitor)
            Divider()
            GeometryReader { geo in
                VStack(spacing: 0) {
                    inputSection(height: (geo.size.height - 88) / 2)
                    actionBar
                    Divider()
                    outputSection(height: (geo.size.height - 88) / 2)
                }
            }
            Divider()
            bottomBar
        }
    }

    private func inputSection(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("INPUT")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
                Button {
                    monitor.pasteFromClipboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste")
                    }.font(.caption)
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
            }
            .padding(.horizontal, 20)

            TextEditor(text: $monitor.inputText)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 20)
        }
        .frame(height: height)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                monitor.formatJSON()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                    Text("Format")
                }.font(.callout).fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut("f", modifiers: [.command])

            Button {
                monitor.minifyJSON()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                    Text("Minify")
                }.font(.callout)
            }
            .buttonStyle(.bordered).controlSize(.large)
            .keyboardShortcut("m", modifiers: [.command])

            Spacer()

            if let err = monitor.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(err)
                }
                .font(.caption).foregroundStyle(.red)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.red.opacity(0.1)).cornerRadius(6)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func outputSection(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("OUTPUT")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                Spacer()
                if !monitor.outputText.isEmpty {
                    Text(monitor.stats).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 20)

            TextEditor(text: .constant(monitor.outputText))
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                .padding(.horizontal, 20)
        }
        .frame(height: height)
    }

    private var bottomBar: some View {
        HStack {
            if !monitor.outputText.isEmpty {
                Button {
                    monitor.copyOutput()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: monitor.justCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        Text(monitor.justCopied ? "Copied!" : "Copy Output")
                    }
                    .font(.callout)
                    .foregroundStyle(monitor.justCopied ? .green : Color.accentColor)
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
            }
            Spacer()
            Button {
                monitor.inputText = ""; monitor.outputText = ""; monitor.errorMessage = nil
            } label: {
                HStack(spacing: 6) { Image(systemName: "trash"); Text("Clear All") }
                    .font(.callout).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: [.command])
            .cursor(.pointingHand)

            Divider().frame(height: 14).padding(.horizontal, 4)

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).font(.caption2).foregroundStyle(.tertiary)
                .cursor(.pointingHand)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

// MARK: - Compare View

struct CompareView: View {
    @ObservedObject var monitor: JSONMonitor

    var body: some View {
        VStack(spacing: 0) {
            makeToolbar(monitor: monitor)
            Divider()
            GeometryReader { geo in
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        editorPanel(label: "LEFT JSON",  text: $monitor.compareLeft)
                        editorPanel(label: "RIGHT JSON", text: $monitor.compareRight)
                    }
                    .frame(height: geo.size.height * 0.48)
                    .padding(.horizontal, 20).padding(.top, 12)

                    HStack {
                        Button {
                            monitor.compareJSONs()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.left.arrow.right.circle.fill")
                                Text("Compare")
                            }.font(.callout).fontWeight(.medium)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .keyboardShortcut("d", modifiers: [.command])
                    }
                    .padding(.vertical, 12)

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("DIFFERENCES")
                            .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                        ScrollView {
                            if monitor.compareResult.isEmpty {
                                Text("Paste two JSON blobs above, then tap Compare.")
                                    .font(.callout).foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 40)
                            } else {
                                Text(monitor.compareResult)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                                    .background(
                                        monitor.compareResult.contains("✓") ? Color.green.opacity(0.1) :
                                        monitor.compareResult.contains("✗") ? Color.red.opacity(0.1) :
                                        Color.orange.opacity(0.1)
                                    )
                                    .cornerRadius(8)
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                }
            }
            Divider()
            // Bottom bar
            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.tertiary)
                    .cursor(.pointingHand)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

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
                VStack(alignment: .leading, spacing: 24) {

                    // 1 — Formatting
                    settingSection("Formatting Options") {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Indentation Style")
                                    .font(.callout).fontWeight(.medium)
                                Picker("", selection: $monitor.indentStyle) {
                                    ForEach(IndentStyle.allCases, id: \.value) { Text($0.rawValue).tag($0.value) }
                                }
                                .pickerStyle(.segmented).labelsHidden()
                            }
                            Toggle(isOn: $monitor.sortKeys) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sort Keys Alphabetically").font(.callout).fontWeight(.medium)
                                    Text("Automatically sort JSON object keys").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                        }
                    }

                    // 2 — Keyboard Shortcuts
                    settingSection("Keyboard Shortcuts") {
                        VStack(alignment: .leading, spacing: 8) {
                            shortcutRow("Format JSON",  "⌘F")
                            shortcutRow("Minify JSON",  "⌘M")
                            shortcutRow("Compare",      "⌘D")
                            shortcutRow("Clear All",    "⌘K")
                            shortcutRow("Paste",        "⌘V")
                        }
                    }

                    // 3 — Appearance
                    settingSection("Appearance") {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Theme").font(.callout).fontWeight(.medium)
                                Picker("", selection: $monitor.appTheme) {
                                    ForEach(AppTheme.allCases, id: \.rawValue) {
                                        Text($0.rawValue).tag($0.rawValue.lowercased())
                                    }
                                }
                                .pickerStyle(.segmented).labelsHidden()
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Color Preset").font(.callout).fontWeight(.medium)
                                Picker("", selection: $monitor.colorPreset) {
                                    ForEach(ColorPreset.allCases, id: \.rawValue) {
                                        Text($0.rawValue).tag($0.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented).labelsHidden()
                            }
                        }
                    }

                    // 4 — Updates
                    settingSection("Updates") {
                        VStack(alignment: .leading, spacing: 8) {
                            Button(monitor.isCheckingUpdate ? "Checking…" : "Check for Updates") {
                                monitor.checkForUpdates()
                            }
                            .disabled(monitor.isCheckingUpdate)
                            if !monitor.updateStatus.isEmpty {
                                Text(monitor.updateStatus)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }

                    // 5 — About
                    settingSection("About") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(appName) v\(appVersion)").font(.callout).fontWeight(.medium)
                                Spacer()
                                Link("Changelog ↗",
                                     destination: URL(string: "https://github.com/\(githubRepo)/commits/main/")!)
                                    .font(.caption)
                            }
                            Text(appTagline)
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("All data stored locally. Nothing leaves your Mac.")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(24)
            }

            Divider()
            HStack {
                Spacer()
                Button("Quit \(appName)") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.bordered).controlSize(.small).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func settingSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)
        }
    }

    private func shortcutRow(_ action: String, _ shortcut: String) -> some View {
        HStack {
            Text(action).font(.caption)
            Spacer()
            Text(shortcut)
                .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1)).cornerRadius(4)
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

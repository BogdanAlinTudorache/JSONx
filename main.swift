import SwiftUI
import AppKit

// MARK: - Models

enum ViewMode: String, CaseIterable {
    case format = "Format"
    case compare = "Compare"
    case settings = "Settings"
    
    var icon: String {
        switch self {
        case .format: return "doc.text"
        case .compare: return "arrow.left.arrow.right"
        case .settings: return "gearshape"
        }
    }
}

enum IndentStyle: String, CaseIterable {
    case two = "2 Spaces"
    case four = "4 Spaces"
    case tab = "Tab"
    
    var indent: String {
        switch self {
        case .two: return "  "
        case .four: return "    "
        case .tab: return "\t"
        }
    }
    
    var value: String {
        switch self {
        case .two: return "2"
        case .four: return "4"
        case .tab: return "tab"
        }
    }
}

enum AppTheme: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

// MARK: - ViewModel

final class JSONMonitor: ObservableObject {
    @Published var inputText: String = ""
    @Published var outputText: String = ""
    @Published var errorMessage: String? = nil
    @Published var currentView: ViewMode = .format
    @Published var justCopied: Bool = false

    @Published var compareLeft: String = ""
    @Published var compareRight: String = ""
    @Published var compareResult: String = ""

    @AppStorage("indentStyle") var indentStyle: String = "2"
    @AppStorage("sortKeys") var sortKeys: Bool = false
    @AppStorage("appTheme") var appTheme: String = "system"
    
    private func stripComments(from json: String) -> String {
        var result = ""
        var inString = false
        var escaped = false
        var i = json.startIndex
        
        while i < json.endIndex {
            let char = json[i]
            
            if escaped {
                result.append(char)
                escaped = false
                i = json.index(after: i)
                continue
            }
            
            if char == "\\" && inString {
                result.append(char)
                escaped = true
                i = json.index(after: i)
                continue
            }
            
            if char == "\"" {
                inString.toggle()
                result.append(char)
                i = json.index(after: i)
                continue
            }
            
            if !inString && char == "/" {
                let nextIndex = json.index(after: i)
                if nextIndex < json.endIndex {
                    let nextChar = json[nextIndex]
                    
                    if nextChar == "/" {
                        while i < json.endIndex && json[i] != "\n" {
                            i = json.index(after: i)
                        }
                        if i < json.endIndex {
                            result.append("\n")
                            i = json.index(after: i)
                        }
                        continue
                    }
                    
                    if nextChar == "*" {
                        i = json.index(after: nextIndex)
                        while i < json.endIndex {
                            if json[i] == "*" {
                                let afterStar = json.index(after: i)
                                if afterStar < json.endIndex && json[afterStar] == "/" {
                                    i = json.index(after: afterStar)
                                    break
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

    func formatJSON() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Input is empty"; return
        }
        let cleanedInput = stripComments(from: inputText)
        guard let data = cleanedInput.data(using: .utf8) else {
            errorMessage = "Invalid encoding"; return
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            var opts: JSONSerialization.WritingOptions = [.prettyPrinted]
            if sortKeys { opts.insert(.sortedKeys) }
            let pretty = try JSONSerialization.data(withJSONObject: obj, options: opts)
            guard var str = String(data: pretty, encoding: .utf8) else { return }

            let style = IndentStyle(rawValue: indentStyle) ?? .two
            if style != .two {
                let lines = str.components(separatedBy: "\n")
                str = lines.map { line in
                    let spaces = line.prefix(while: { $0 == " " }).count
                    let indentCount = spaces / 2
                    return String(repeating: style.indent, count: indentCount) + line.dropFirst(spaces)
                }.joined(separator: "\n")
            }
            outputText = str
            errorMessage = nil
        } catch {
            errorMessage = "Parse error: \(error.localizedDescription)"
        }
    }

    func minifyJSON() {
        let cleanedInput = stripComments(from: inputText)
        guard let data = cleanedInput.data(using: .utf8) else {
            errorMessage = "Invalid encoding"; return
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            let compact = try JSONSerialization.data(withJSONObject: obj, options: [])
            outputText = String(data: compact, encoding: .utf8) ?? ""
            errorMessage = nil
        } catch {
            errorMessage = "Parse error: \(error.localizedDescription)"
        }
    }

    func compareJSONs() {
        guard !compareLeft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !compareRight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            compareResult = "Both JSON inputs required"
            return
        }

        let cleanedLeft = stripComments(from: compareLeft)
        let cleanedRight = stripComments(from: compareRight)
        
        guard let leftData = cleanedLeft.data(using: .utf8),
              let rightData = cleanedRight.data(using: .utf8) else {
            compareResult = "Invalid encoding"
            return
        }

        do {
            let leftObj = try JSONSerialization.jsonObject(with: leftData)
            let rightObj = try JSONSerialization.jsonObject(with: rightData)

            let leftStr = formatForComparison(leftObj)
            let rightStr = formatForComparison(rightObj)

            if leftStr == rightStr {
                compareResult = "✓ JSONs are identical"
            } else {
                let differences = findDifferences(leftObj, rightObj)
                compareResult = "≠ Differences:\n\(differences)"
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
            let allKeys = Set(leftDict.keys).union(Set(rightDict.keys))
            for key in allKeys.sorted() {
                let currentPath = path.isEmpty ? key : "\(path).\(key)"
                
                if leftDict[key] == nil {
                    diffs.append("+ \(currentPath): only in RIGHT")
                } else if rightDict[key] == nil {
                    diffs.append("- \(currentPath): only in LEFT")
                } else {
                    let leftVal = leftDict[key]!
                    let rightVal = rightDict[key]!
                    
                    if !valuesEqual(leftVal, rightVal) {
                        if leftVal is [String: Any] && rightVal is [String: Any] {
                            collectDifferences(leftVal, rightVal, path: currentPath, diffs: &diffs)
                        } else if leftVal is [Any] && rightVal is [Any] {
                            collectDifferences(leftVal, rightVal, path: currentPath, diffs: &diffs)
                        } else {
                            diffs.append("~ \(currentPath): \(stringify(leftVal)) → \(stringify(rightVal))")
                        }
                    }
                }
            }
        } else if let leftArr = left as? [Any], let rightArr = right as? [Any] {
            if leftArr.count != rightArr.count {
                diffs.append("~ \(path): array length \(leftArr.count) → \(rightArr.count)")
            }
            let minCount = min(leftArr.count, rightArr.count)
            for idx in 0..<minCount {
                let currentPath = "\(path)[\(idx)]"
                if !valuesEqual(leftArr[idx], rightArr[idx]) {
                    if leftArr[idx] is [String: Any] && rightArr[idx] is [String: Any] {
                        collectDifferences(leftArr[idx], rightArr[idx], path: currentPath, diffs: &diffs)
                    } else {
                        diffs.append("~ \(currentPath): \(stringify(leftArr[idx])) → \(stringify(rightArr[idx]))")
                    }
                }
            }
        } else {
            diffs.append("~ \(path): type mismatch")
        }
    }
    
    private func stringify(_ value: Any) -> String {
        if let str = value as? String { return "\"\(str)\"" }
        if let num = value as? NSNumber { return "\(num)" }
        if value is NSNull { return "null" }
        if value is [String: Any] { return "{...}" }
        if value is [Any] { return "[...]" }
        return "\(value)"
    }

    private func valuesEqual(_ a: Any?, _ b: Any?) -> Bool {
        if a is NSNull && b is NSNull { return true }
        if a as? String == b as? String { return true }
        if a as? Int == b as? Int { return true }
        if a as? Double == b as? Double { return true }
        if a as? Bool == b as? Bool { return true }
        if let aDict = a as? [String: Any], let bDict = b as? [String: Any] {
            return NSDictionary(dictionary: aDict).isEqual(to: bDict)
        }
        return false
    }

    func pasteFromClipboard() {
        if let str = NSPasteboard.general.string(forType: .string) {
            inputText = str
        }
    }

    func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
        justCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.justCopied = false
        }
    }

    var stats: String {
        guard let data = outputText.data(using: .utf8),
              !outputText.isEmpty else { return "" }
        let bytes = data.count
        let lines = outputText.components(separatedBy: "\n").count
        return "\(lines) lines, \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
    }
}

// MARK: - Editor View

struct JSONEditorView: View {
    @ObservedObject var monitor: JSONMonitor

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                toolbar
                
                Divider()
                
                GeometryReader { contentGeometry in
                    VStack(spacing: 0) {
                        inputSection(height: (contentGeometry.size.height - 100) / 2)
                        
                        actionBar
                        
                        Divider()
                        
                        outputSection(height: (contentGeometry.size.height - 100) / 2)
                    }
                }
                
                Divider()
                
                bottomBar
            }
        }
    }
    
    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "curlybraces")
                    .font(.title3)
                    .foregroundStyle(.blue)
                Text("JSONx")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            
            Spacer()
            
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        monitor.currentView = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                        Text(mode.rawValue)
                    }
                    .font(.callout)
                    .foregroundStyle(monitor.currentView == mode ? .primary : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        monitor.currentView == mode ?
                        Color.accentColor.opacity(0.15) : Color.clear
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    private func inputSection(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("INPUT")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    monitor.pasteFromClipboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            
            TextEditor(text: $monitor.inputText)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
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
                }
                .font(.callout)
                .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("f", modifiers: [.command])
            
            Button {
                monitor.minifyJSON()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                    Text("Minify")
                }
                .font(.callout)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut("m", modifiers: [.command])
            
            Spacer()
            
            if let err = monitor.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(err)
                }
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    private func outputSection(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("OUTPUT")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                if !monitor.outputText.isEmpty {
                    Text(monitor.stats)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 20)
            
            TextEditor(text: .constant(monitor.outputText))
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
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
                    .foregroundStyle(monitor.justCopied ? .green : .accentColor)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Button {
                monitor.inputText = ""
                monitor.outputText = ""
                monitor.errorMessage = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Clear All")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: [.command])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Compare View

struct CompareView: View {
    @ObservedObject var monitor: JSONMonitor

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "curlybraces")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        Text("JSONx")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                    
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                monitor.currentView = mode
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: mode.icon)
                                Text(mode.rawValue)
                            }
                            .font(.callout)
                            .foregroundStyle(monitor.currentView == mode ? .primary : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                monitor.currentView == mode ?
                                Color.accentColor.opacity(0.15) : Color.clear
                            )
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()

                GeometryReader { contentGeometry in
                    VStack(spacing: 0) {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("LEFT JSON")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                TextEditor(text: $monitor.compareLeft)
                                    .font(.system(size: 13, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("RIGHT JSON")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                TextEditor(text: $monitor.compareRight)
                                    .font(.system(size: 13, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .background(Color(nsColor: .textBackgroundColor))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                            }
                        }
                        .frame(height: contentGeometry.size.height * 0.5)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                        HStack {
                            Button {
                                monitor.compareJSONs()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                                    Text("Compare")
                                }
                                .font(.callout)
                                .fontWeight(.medium)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .padding(.vertical, 12)

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("DIFFERENCES")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 20)
                            
                            ScrollView {
                                if !monitor.compareResult.isEmpty {
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
                                } else {
                                    Text("No comparison yet")
                                        .font(.callout)
                                        .foregroundStyle(.tertiary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 40)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var monitor: JSONMonitor

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "curlybraces")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    Text("JSONx")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            monitor.currentView = mode
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                            Text(mode.rawValue)
                        }
                        .font(.callout)
                        .foregroundStyle(monitor.currentView == mode ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            monitor.currentView == mode ?
                            Color.accentColor.opacity(0.15) : Color.clear
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    settingSection("Formatting Options") {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Indentation Style")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                Picker("Indent", selection: $monitor.indentStyle) {
                                    ForEach(IndentStyle.allCases, id: \.value) { style in
                                        Text(style.rawValue).tag(style.value)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }

                            Toggle(isOn: $monitor.sortKeys) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sort Keys Alphabetically")
                                        .font(.callout)
                                        .fontWeight(.medium)
                                    Text("Automatically sort JSON object keys")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                        }
                    }

                    settingSection("Appearance") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Theme")
                                .font(.callout)
                                .fontWeight(.medium)
                            Picker("Theme", selection: $monitor.appTheme) {
                                ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                                    Text(theme.rawValue).tag(theme.rawValue.lowercased())
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                    
                    settingSection("Keyboard Shortcuts") {
                        VStack(alignment: .leading, spacing: 8) {
                            shortcutRow("Format JSON", "⌘F")
                            shortcutRow("Minify JSON", "⌘M")
                            shortcutRow("Paste", "⌘V")
                            shortcutRow("Copy Output", "⇧⌘C")
                            shortcutRow("Clear All", "⌘K")
                        }
                    }
                    
                    Divider()
                    
                    VStack(spacing: 8) {
                        Text("JSONx v2.0")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Button("Quit JSONx") {
                            NSApplication.shared.terminate(nil)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .padding(24)
            }
        }
    }

    @ViewBuilder
    private func settingSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
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
            Text(action)
                .font(.caption)
            Spacer()
            Text(shortcut)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @ObservedObject var monitor: JSONMonitor

    var body: some View {
        Group {
            switch monitor.currentView {
            case .format: JSONEditorView(monitor: monitor)
            case .compare: CompareView(monitor: monitor)
            case .settings: SettingsView(monitor: monitor)
            }
        }
        .onAppear { applyTheme() }
        .onChange(of: monitor.appTheme) { _ in applyTheme() }
    }

    private func applyTheme() {
        switch monitor.appTheme {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil
        }
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
            Text("JSONx")
        }
        .menuBarExtraStyle(.window)
    }
}
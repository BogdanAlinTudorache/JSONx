import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var n: UInt64 = 0; Scanner(string: s).scanHexInt64(&n)
        self.init(red: Double((n >> 16) & 0xFF)/255, green: Double((n >> 8) & 0xFF)/255, blue: Double(n & 0xFF)/255)
    }
}

// MARK: - Models

enum ViewMode { case format, compare, settings }
enum JSONAction { case format, minify }
enum IndentStyle: String, CaseIterable {
    case two = "2"
    case four = "4"
    case tab = "Tab"
    var indent: String {
        switch self {
        case .two: return "  "
        case .four: return "    "
        case .tab: return "\t"
        }
    }
}
enum AppTheme: String, CaseIterable { case system, light, dark }

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

    func formatJSON() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Input is empty"; return
        }
        guard let data = inputText.data(using: .utf8) else {
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
        guard let data = inputText.data(using: .utf8) else {
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

        guard let leftData = compareLeft.data(using: .utf8),
              let rightData = compareRight.data(using: .utf8) else {
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

        if let leftDict = left as? [String: Any], let rightDict = right as? [String: Any] {
            let allKeys = Set(leftDict.keys).union(Set(rightDict.keys))
            for key in allKeys.sorted() {
                if leftDict[key] == nil {
                    diffs.append("+ Right has: \"\(key)\"")
                } else if rightDict[key] == nil {
                    diffs.append("- Left has: \"\(key)\"")
                } else if !valuesEqual(leftDict[key], rightDict[key]) {
                    diffs.append("~ Value differs: \"\(key)\"")
                }
            }
        } else if let leftArr = left as? [Any], let rightArr = right as? [Any] {
            if leftArr.count != rightArr.count {
                diffs.append("Length: \(leftArr.count) vs \(rightArr.count)")
            }
            for (idx, (l, r)) in zip(leftArr, rightArr).enumerated() {
                if !valuesEqual(l, r) {
                    diffs.append("[\(idx)] differs")
                }
            }
        } else {
            diffs.append("Different types")
        }

        return diffs.isEmpty ? "No differences" : diffs.prefix(10).joined(separator: "\n")
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
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("JSONx")
                    .font(.headline)
                Spacer()

                Button { monitor.pasteFromClipboard() } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.plain)
                .help("Paste")

                Button { withAnimation { monitor.currentView = .compare } } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Compare")

                Button { withAnimation { monitor.currentView = .settings } } label: {
                    Image(systemName: "gearshape").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("INPUT")
                    .font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)

                TextEditor(text: $monitor.inputText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 120)
                    .padding(.horizontal, 10)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .controlBackgroundColor).cornerRadius(6))
                    .padding(.horizontal, 10)
            }

            HStack(spacing: 10) {
                Button("Format") { monitor.formatJSON() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button("Minify") { monitor.minifyJSON() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Spacer()

                if let err = monitor.errorMessage {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("OUTPUT")
                        .font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                    Spacer()
                    if !monitor.outputText.isEmpty {
                        Text(monitor.stats)
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                TextEditor(text: .constant(monitor.outputText))
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 120)
                    .padding(.horizontal, 10)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .controlBackgroundColor).cornerRadius(6))
                    .padding(.horizontal, 10)
            }

            Divider()

            HStack {
                if !monitor.outputText.isEmpty {
                    Button {
                        monitor.copyOutput()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: monitor.justCopied ? "checkmark" : "doc.on.doc")
                            Text(monitor.justCopied ? "Copied!" : "Copy")
                        }
                        .font(.callout)
                        .foregroundStyle(monitor.justCopied ? .green : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button("Clear") {
                    monitor.inputText = ""
                    monitor.outputText = ""
                    monitor.errorMessage = nil
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(width: 420, height: 480)
    }
}

// MARK: - Compare View

struct CompareView: View {
    @ObservedObject var monitor: JSONMonitor

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { withAnimation { monitor.currentView = .format } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.callout)
                        Text("Back").font(.callout)
                    }.foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Compare JSON").font(.headline)
                Spacer()
                Text("Back").font(.callout).opacity(0)
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)

            Divider()

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LEFT")
                        .font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                    TextEditor(text: $monitor.compareLeft)
                        .font(.system(.caption2, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .controlBackgroundColor).cornerRadius(4))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("RIGHT")
                        .font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                    TextEditor(text: $monitor.compareRight)
                        .font(.system(.caption2, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .controlBackgroundColor).cornerRadius(4))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)

            Divider()

            Button("Compare") { monitor.compareJSONs() }
                .buttonStyle(.borderedProminent)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !monitor.compareResult.isEmpty {
                        Text(monitor.compareResult)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(20)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(monitor.compareResult.contains("✓") ? Color.green.opacity(0.08) :
                                        monitor.compareResult.contains("✗") ? Color.red.opacity(0.1) :
                                        Color.orange.opacity(0.08))
                            .cornerRadius(6)
                    }
                }
                .padding(10)
            }

            Divider()

            HStack {
                Spacer()
                Button("Close") { withAnimation { monitor.currentView = .format } }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .frame(width: 420, height: 480)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var monitor: JSONMonitor

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { withAnimation { monitor.currentView = .format } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.callout)
                        Text("Back").font(.callout)
                    }.foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Settings").font(.headline)
                Spacer()
                Text("Back").font(.callout).opacity(0)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    section("FORMATTING") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Indent style").font(.callout)
                            Picker("Indent", selection: $monitor.indentStyle) {
                                ForEach(IndentStyle.allCases, id: \.rawValue) {
                                    Text($0 == .tab ? "Tab" : "\($0.rawValue) spaces").tag($0.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .font(.caption)
                        }

                        Toggle("Sort keys", isOn: $monitor.sortKeys)
                            .font(.callout)
                    }

                    section("APPEARANCE") {
                        Picker("Theme", selection: $monitor.appTheme) {
                            ForEach(AppTheme.allCases, id: \.rawValue) {
                                Text($0.rawValue.capitalized).tag($0.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .font(.caption)
                    }

                    section("ABOUT") {
                        Text("JSONx v2.0")
                            .font(.callout)
                        Text("Format, minify, validate, and compare JSON.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }

            Divider()

            HStack {
                Spacer()
                Button("Quit JSONx") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 10)
        }
        .frame(width: 420, height: 480)
    }

    @ViewBuilder
    private func section<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
            content()
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
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "curlybraces")
                Text("JSONx")
            }
            .font(.system(.body))
        }
        .menuBarExtraStyle(.window)
    }
}
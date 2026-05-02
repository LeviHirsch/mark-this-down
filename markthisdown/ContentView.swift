import SwiftUI
import AppKit

enum DisplayMode { case rendered, raw }
enum SaveState { case untitled, autosaving, saved }

// MARK: - ContentView

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @State private var mode: DisplayMode = .rendered
    @State private var saveState: SaveState = .untitled
    @State private var debounceTask: Task<Void, Never>? = nil
    @State private var showHelp: Bool = false
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.system.rawValue

    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .system }
    private var palette: ThemePalette {
        theme.palette(systemIsDark: colorScheme == .dark)
    }

    private var statusText: String {
        switch saveState {
        case .untitled:   return "Not yet saved"
        case .autosaving: return "Auto-saving…"
        case .saved:      return "Auto-saved"
        }
    }

    var body: some View {
        MarkdownEditor(text: $document.text, mode: mode, palette: palette)
            .navigationSubtitle(statusText)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
                        if fileURL != nil {
                            saveState = .saved
                            debounceTask?.cancel()
                        }
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .help("Save (⌘S)")

                    Button {
                        mode = (mode == .rendered) ? .raw : .rendered
                    } label: {
                        Label(mode == .rendered ? "Raw" : "Rendered",
                              systemImage: mode == .rendered
                                  ? "chevron.left.forwardslash.chevron.right"
                                  : "doc.richtext")
                    }
                    .keyboardShortcut("e", modifiers: .command)
                    .help("Toggle raw / rendered (⌘E)")

                    Menu {
                        ForEach(AppTheme.allCases) { t in
                            Button {
                                themeRaw = t.rawValue
                            } label: {
                                if t.rawValue == themeRaw {
                                    Label(t.displayName, systemImage: "checkmark")
                                } else {
                                    Text(t.displayName)
                                }
                            }
                        }
                    } label: {
                        Label("Theme", systemImage: "paintpalette")
                    }
                    .help("Theme — ⌘L cycles")
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        insertFrontmatter()
                    } label: {
                        Label("Insert Frontmatter", systemImage: "text.badge.plus")
                    }
                    .help("Insert frontmatter at top of document")

                    Button {
                        NSApp.sendAction(
                            #selector(NSDocumentController.newDocument(_:)),
                            to: nil, from: nil
                        )
                    } label: {
                        Label("New", systemImage: "doc.badge.plus")
                    }
                    .help("New document (⌘N)")

                    Button {
                        showHelp.toggle()
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                    .help("Shortcuts and terminal commands")
                    .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                        HelpView().frame(width: 380)
                    }
                }
            }
            .onAppear { recomputeStateForFileURL() }
            .onChange(of: fileURL) { _, _ in recomputeStateForFileURL() }
            .onChange(of: document.text) { _, _ in
                guard fileURL != nil else { return }
                saveState = .autosaving
                debounceTask?.cancel()
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if !Task.isCancelled { saveState = .saved }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .mtdToggleMode)) { _ in
                mode = (mode == .rendered) ? .raw : .rendered
            }
            .onReceive(NotificationCenter.default.publisher(for: .mtdInsertFrontmatter)) { _ in
                insertFrontmatter()
            }
    }

    private func recomputeStateForFileURL() {
        saveState = (fileURL == nil) ? .untitled : .saved
    }

    private func insertFrontmatter() {
        if document.text.hasPrefix("---\n") || document.text.hasPrefix("---\r\n") {
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let block = """
            ---
            title:
            description: |

            date: \(today)
            tags: []
            ---


            """
        document.text = block + document.text
    }
}

// MARK: - Editor (NSTextView wrapped for SwiftUI)

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let mode: DisplayMode
    let palette: ThemePalette

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }

        tv.delegate = context.coordinator
        tv.allowsUndo = true
        tv.isRichText = false
        tv.importsGraphics = false
        tv.usesFindBar = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.textContainerInset = NSSize(width: 28, height: 28)
        tv.string = text
        applyAppearance(to: tv)
        context.coordinator.lastMode = mode
        context.coordinator.applyHighlighting(to: tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        applyAppearance(to: tv)

        if tv.string != text {
            tv.string = text
            context.coordinator.applyHighlighting(to: tv)
        } else if context.coordinator.lastMode != mode {
            context.coordinator.applyHighlighting(to: tv)
        } else {
            // Theme might have changed — just reapply highlighting.
            context.coordinator.applyHighlighting(to: tv)
        }
        context.coordinator.lastMode = mode
    }

    private func applyAppearance(to tv: NSTextView) {
        tv.backgroundColor = palette.background
        tv.drawsBackground = true
        tv.insertionPointColor = palette.bodyColor
        tv.font = palette.bodyFont
        tv.textColor = palette.bodyColor
        tv.linkTextAttributes = [
            .foregroundColor: palette.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        tv.typingAttributes = [
            .font: palette.bodyFont,
            .foregroundColor: palette.bodyColor
        ]
        if let scroll = tv.enclosingScrollView {
            scroll.drawsBackground = true
            scroll.backgroundColor = palette.background
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var lastMode: DisplayMode = .rendered

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            applyHighlighting(to: tv)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if parent.mode == .rendered {
                applyHighlighting(to: tv)
            }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at _: Int) -> Bool {
            if let url = link as? URL { NSWorkspace.shared.open(url); return true }
            if let s = link as? String, let u = URL(string: s) {
                NSWorkspace.shared.open(u); return true
            }
            return false
        }

        // Auto-bullet on Enter
        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            return handleNewline(in: tv)
        }

        private func handleNewline(in tv: NSTextView) -> Bool {
            let nsString = tv.string as NSString
            let cursor = tv.selectedRange().location
            guard cursor <= nsString.length else { return false }

            // Find the start of the current line
            let lineRange = nsString.lineRange(for: NSRange(location: cursor, length: 0))
            let lineStart = lineRange.location
            let prefixRange = NSRange(location: lineStart, length: cursor - lineStart)
            let linePrefix = nsString.substring(with: prefixRange)

            // Match  optional indent + marker + space   where marker is -/*/+ or N.
            guard let re = try? NSRegularExpression(
                pattern: #"^([ \t]*)([-*+]|(\d+)\.)([ \t]+)(.*)$"#)
            else { return false }
            let prefixNSRange = NSRange(location: 0, length: (linePrefix as NSString).length)
            guard let m = re.firstMatch(in: linePrefix, range: prefixNSRange) else { return false }

            let indent = (linePrefix as NSString).substring(with: m.range(at: 1))
            let marker = (linePrefix as NSString).substring(with: m.range(at: 2))
            let space  = (linePrefix as NSString).substring(with: m.range(at: 4))
            let content = (linePrefix as NSString).substring(with: m.range(at: 5))

            // If the user pressed Enter on an empty list item, exit the list.
            if content.isEmpty {
                let deleteRange = NSRange(location: lineStart, length: cursor - lineStart)
                if tv.shouldChangeText(in: deleteRange, replacementString: "") {
                    tv.replaceCharacters(in: deleteRange, with: "")
                    tv.didChangeText()
                }
                return true
            }

            // Continue the list with a fresh marker.
            let nextMarker: String
            if let digits = Int(marker.trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
                nextMarker = "\(digits + 1)."
            } else {
                nextMarker = marker
            }
            let insertion = "\n\(indent)\(nextMarker)\(space)"
            let insertRange = tv.selectedRange()
            if tv.shouldChangeText(in: insertRange, replacementString: insertion) {
                tv.replaceCharacters(in: insertRange, with: insertion)
                tv.didChangeText()
            }
            return true
        }

        func applyHighlighting(to tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let cursorRange = tv.selectedRange()
            let full = NSRange(location: 0, length: (storage.string as NSString).length)
            storage.beginEditing()
            storage.setAttributes([
                .font: parent.palette.bodyFont,
                .foregroundColor: parent.palette.bodyColor
            ], range: full)
            if parent.mode == .rendered {
                SyntaxHighlighter.apply(
                    to: storage,
                    range: full,
                    palette: parent.palette,
                    cursorRange: cursorRange
                )
            }
            storage.endEditing()

            tv.typingAttributes = [
                .font: parent.palette.bodyFont,
                .foregroundColor: parent.palette.bodyColor
            ]
        }
    }
}

// MARK: - Syntax highlighter

enum SyntaxHighlighter {

    static func apply(to storage: NSTextStorage,
                      range: NSRange,
                      palette: ThemePalette,
                      cursorRange: NSRange) {
        let str = storage.string

        // 1. Frontmatter (very top of doc):  ---\n…\n---\n
        enumerate(#"\A---[ \t]*\n(.*?)\n---[ \t]*$"#,
                  in: str, range: range,
                  options: [.dotMatchesLineSeparators, .anchorsMatchLines]) { m in
            storage.addAttribute(.foregroundColor, value: palette.frontmatterColor, range: m.range)
            let italic = NSFontManager.shared.convert(palette.bodyFont, toHaveTrait: .italicFontMask)
            storage.addAttribute(.font, value: italic, range: m.range)
        }

        // 2. Fenced code blocks:  ```lang\n…\n```
        enumerate(#"^```[A-Za-z0-9_+-]*[ \t]*\n([\s\S]*?)\n```[ \t]*$"#,
                  in: str, range: range,
                  options: .anchorsMatchLines) { m in
            storage.addAttribute(.backgroundColor, value: palette.codeBackground, range: m.range)
            storage.addAttribute(.font, value: palette.codeFont, range: m.range)
            // Mute the fence lines slightly
            (try? NSRegularExpression(pattern: "^```[^\n]*$", options: .anchorsMatchLines))?
                .enumerateMatches(in: str, range: m.range) { fm, _, _ in
                    if let fm = fm {
                        storage.addAttribute(.foregroundColor,
                                             value: palette.codeFenceColor, range: fm.range)
                    }
                }
        }

        // 3. ATX headings: # … ######
        enumerate(#"^(#{1,6})[ \t]+.*$"#, in: str, range: range, options: .anchorsMatchLines) { m in
            let hashes = m.range(at: 1)
            let level = max(1, min(6, hashes.length))
            let size = palette.headingSizes[level - 1]
            let bodyDescriptor = palette.bodyFont.fontDescriptor
            let headingFont = NSFont(descriptor: bodyDescriptor, size: size).map {
                NSFontManager.shared.convert($0, toHaveTrait: .boldFontMask)
            } ?? NSFont.systemFont(ofSize: size, weight: .bold)
            storage.addAttribute(.font, value: headingFont, range: m.range)
            storage.addAttribute(.foregroundColor, value: palette.headingColor, range: m.range)
            storage.addAttribute(.foregroundColor, value: palette.markerColor, range: hashes)
        }

        // 4. Horizontal rule:  a line of three or more -, *, or _
        enumerate(#"^[ \t]*(-{3,}|\*{3,}|_{3,})[ \t]*$"#,
                  in: str, range: range, options: .anchorsMatchLines) { m in
            // Hide the dashes; draw a strikethrough across the line for a divider line.
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: m.range)
            storage.addAttribute(.strikethroughStyle,
                                 value: NSUnderlineStyle.single.rawValue, range: m.range)
            storage.addAttribute(.strikethroughColor, value: palette.hrColor, range: m.range)
        }

        // 5. Bold:  **text**  (inline; marker hiding when cursor away)
        enumerate(#"\*\*([^*\n]+)\*\*"#, in: str, range: range) { m in
            let baseFont = (storage.attribute(.font, at: m.range.location, effectiveRange: nil)
                            as? NSFont) ?? palette.bodyFont
            let bold = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            storage.addAttribute(.font, value: bold, range: m.range)
            applyMarker(storage, at: m.range.location, length: 2,
                        cursorIn: m.range, cursorRange: cursorRange, palette: palette)
            applyMarker(storage, at: m.range.location + m.range.length - 2, length: 2,
                        cursorIn: m.range, cursorRange: cursorRange, palette: palette)
        }

        // 6. Italic:  *text*
        enumerate(#"(?<!\*)\*(?!\*)([^*\n]+?)\*(?!\*)"#, in: str, range: range) { m in
            let baseFont = (storage.attribute(.font, at: m.range.location, effectiveRange: nil)
                            as? NSFont) ?? palette.bodyFont
            let italic = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            storage.addAttribute(.font, value: italic, range: m.range)
            applyMarker(storage, at: m.range.location, length: 1,
                        cursorIn: m.range, cursorRange: cursorRange, palette: palette)
            applyMarker(storage, at: m.range.location + m.range.length - 1, length: 1,
                        cursorIn: m.range, cursorRange: cursorRange, palette: palette)
        }

        // 7. Italic underscores: _text_
        enumerate(#"(?<![A-Za-z0-9_])_(?!_)([^_\n]+?)_(?![A-Za-z0-9_])"#,
                  in: str, range: range) { m in
            let baseFont = (storage.attribute(.font, at: m.range.location, effectiveRange: nil)
                            as? NSFont) ?? palette.bodyFont
            let italic = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            storage.addAttribute(.font, value: italic, range: m.range)
            applyMarker(storage, at: m.range.location, length: 1,
                        cursorIn: m.range, cursorRange: cursorRange, palette: palette)
            applyMarker(storage, at: m.range.location + m.range.length - 1, length: 1,
                        cursorIn: m.range, cursorRange: cursorRange, palette: palette)
        }

        // 8. Inline code:  `code`
        enumerate(#"`([^`\n]+)`"#, in: str, range: range) { m in
            storage.addAttribute(.font, value: palette.codeFont, range: m.range)
            storage.addAttribute(.backgroundColor, value: palette.codeBackground, range: m.range)
            applyMarker(storage, at: m.range.location, length: 1,
                        cursorIn: m.range, cursorRange: cursorRange, palette: palette)
            applyMarker(storage, at: m.range.location + m.range.length - 1, length: 1,
                        cursorIn: m.range, cursorRange: cursorRange, palette: palette)
        }

        // 9. Markdown links:  [text](url)
        enumerate(#"\[([^\]\n]+)\]\(([^)\n]+)\)"#, in: str, range: range) { m in
            let textRange = m.range(at: 1)
            let urlRange = m.range(at: 2)
            let urlString = (str as NSString).substring(with: urlRange)
            if let url = URL(string: urlString) {
                storage.addAttribute(.link, value: url, range: textRange)
            }
            storage.addAttribute(.foregroundColor, value: palette.linkColor, range: textRange)
            storage.addAttribute(.underlineStyle,
                                 value: NSUnderlineStyle.single.rawValue, range: textRange)
            storage.addAttribute(.foregroundColor,
                                 value: palette.linkColor.withAlphaComponent(0.55), range: urlRange)
            // Brackets / parens muted
            for offset in [m.range.location,
                           textRange.location + textRange.length,
                           urlRange.location - 1,
                           urlRange.location + urlRange.length] {
                mute(storage, at: offset, length: 1, color: palette.markerColor)
            }
        }

        // 10. Bare URLs / emails via NSDataDetector
        if let detector = try? NSDataDetector(types:
            NSTextCheckingResult.CheckingType.link.rawValue) {
            detector.enumerateMatches(in: str, range: range) { match, _, _ in
                guard let m = match, let url = m.url else { return }
                // Skip links inside markdown link syntax — the `[…](…)` rule already handled them.
                let nsStr = str as NSString
                if m.range.location > 0,
                   nsStr.character(at: m.range.location - 1) == 0x28 /* ( */ {
                    return
                }
                storage.addAttribute(.link, value: url, range: m.range)
                storage.addAttribute(.foregroundColor, value: palette.linkColor, range: m.range)
                storage.addAttribute(.underlineStyle,
                                     value: NSUnderlineStyle.single.rawValue, range: m.range)
            }
        }

        // 11. Blockquote: lines starting with >
        enumerate(#"(?:^>\s?.*$\n?)+"#, in: str, range: range, options: .anchorsMatchLines) { m in
            let para = NSMutableParagraphStyle()
            para.firstLineHeadIndent = 6
            para.headIndent = 18
            storage.addAttribute(.paragraphStyle, value: para, range: m.range)
            storage.addAttribute(.foregroundColor, value: palette.blockquoteColor, range: m.range)
            storage.addAttribute(.backgroundColor,
                                 value: palette.blockquoteBackground, range: m.range)
            let italic = NSFontManager.shared.convert(palette.bodyFont, toHaveTrait: .italicFontMask)
            storage.addAttribute(.font, value: italic, range: m.range)
        }

        // 12. List items: hanging indent + colored marker
        enumerate(#"^([ \t]*)([-*+]|\d+\.)([ \t]+)"#,
                  in: str, range: range, options: .anchorsMatchLines) { m in
            let lineRange = (str as NSString).lineRange(for: m.range)
            let para = NSMutableParagraphStyle()
            para.firstLineHeadIndent = 0
            para.headIndent = 22
            storage.addAttribute(.paragraphStyle, value: para, range: lineRange)
            let marker = m.range(at: 2)
            storage.addAttribute(.foregroundColor, value: palette.markerColor, range: marker)
            let boldBody = NSFontManager.shared.convert(palette.bodyFont, toHaveTrait: .boldFontMask)
            storage.addAttribute(.font, value: boldBody, range: marker)
        }
    }

    // Marker hiding: visible when cursor lies inside the element's range, hidden otherwise.
    private static func applyMarker(_ storage: NSTextStorage,
                                    at location: Int,
                                    length: Int,
                                    cursorIn elementRange: NSRange,
                                    cursorRange: NSRange,
                                    palette: ThemePalette) {
        let bound = (storage.string as NSString).length
        guard location >= 0, location + length <= bound else { return }
        let r = NSRange(location: location, length: length)
        if NSLocationInRange(cursorRange.location, expandedToInclude: elementRange) ||
           rangesIntersect(cursorRange, elementRange) {
            storage.addAttribute(.foregroundColor, value: palette.markerColor, range: r)
        } else {
            // Hide visually: clear color + collapse with negative kerning of the line height.
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: r)
            storage.addAttribute(.kern, value: NSNumber(value: -8.0), range: r)
        }
    }

    private static func mute(_ storage: NSTextStorage, at location: Int, length: Int, color: NSColor) {
        let bound = (storage.string as NSString).length
        guard location >= 0, location + length <= bound else { return }
        storage.addAttribute(.foregroundColor, value: color,
                             range: NSRange(location: location, length: length))
    }

    private static func enumerate(_ pattern: String,
                                  in string: String,
                                  range: NSRange,
                                  options: NSRegularExpression.Options = [],
                                  body: (NSTextCheckingResult) -> Void) {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        re.enumerateMatches(in: string, range: range) { match, _, _ in
            if let m = match { body(m) }
        }
    }

    private static func rangesIntersect(_ a: NSRange, _ b: NSRange) -> Bool {
        let aEnd = a.location + a.length
        let bEnd = b.location + b.length
        return a.location <= bEnd && b.location <= aEnd
    }
}

private func NSLocationInRange(_ loc: Int, expandedToInclude r: NSRange) -> Bool {
    return loc >= r.location && loc <= r.location + r.length
}

// MARK: - Help popover

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("MarkThisDown").font(.title3.bold())

                section("Keyboard shortcuts", rows: [
                    ("⌘N", "New document"),
                    ("⌘S", "Save (also auto-saves)"),
                    ("⌘E", "Toggle raw / rendered view"),
                    ("⌘L", "Cycle theme"),
                    ("⌘W", "Close window (prompts if untitled)"),
                    ("⌘F", "Find in document"),
                ])

                section("Editing tips", rows: [
                    ("Lists", "Enter continues `- `, `* `, `+ `, or numbered (auto-increments). Empty marker line exits."),
                    ("Markers", "**, *, ` markers hide when cursor is off the styled span."),
                    ("Links", "[text](url) and bare https://… or domain.com — click to open."),
                    ("Frontmatter", "Use the toolbar button to insert a YAML block."),
                    ("Comments", "<!-- @ note --> stays in the file but doesn't render. Useful for AI workflows."),
                ])

                section("Terminal", rows: [
                    ("open -a MarkThisDown notes.md", "Open file"),
                    ("open -a MarkThisDown", "Untitled window"),
                    ("open -a MarkThisDown a.md b.md", "Two windows"),
                    ("alias mtd='open -a MarkThisDown'", "Add to ~/.zshrc for short alias"),
                ])
            }
            .padding(16)
        }
        .frame(maxHeight: 520)
    }

    @ViewBuilder
    private func section(_ title: String, rows: [(String, String)]) -> some View {
        Text(title).font(.headline)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.0)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .leading)
                    Text(row.1)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

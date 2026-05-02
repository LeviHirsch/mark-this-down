import SwiftUI
import AppKit

enum DisplayMode { case rendered, raw }
enum SaveState { case untitled, autosaving, saved }

// Custom attribute keys
extension NSAttributedString.Key {
    static let mtdHR = NSAttributedString.Key("mtdHR")
    static let mtdHRColor = NSAttributedString.Key("mtdHRColor")
    static let mtdQuote = NSAttributedString.Key("mtdQuote")
    static let mtdQuoteBG = NSAttributedString.Key("mtdQuoteBG")
    static let mtdQuoteBar = NSAttributedString.Key("mtdQuoteBar")
    static let mtdBullet = NSAttributedString.Key("mtdBullet")
    static let mtdBulletColor = NSAttributedString.Key("mtdBulletColor")
}

private var appVersion: String {
    let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    return "v\(v)"
}

// MARK: - ContentView

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @State private var mode: DisplayMode = .rendered
    @State private var saveState: SaveState = .untitled
    @State private var debounceTask: Task<Void, Never>? = nil
    @State private var showHelp: Bool = false
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.system.rawValue
    @AppStorage("fontScale") private var fontScale: Double = 1.0

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
        MarkdownEditor(text: $document.text,
                       mode: mode,
                       palette: palette,
                       scale: CGFloat(fontScale))
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
                    Text("\(appVersion) · \(zoomLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("App version and current zoom")
                        .onTapGesture(count: 2) { fontScale = 1.0 }

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

    private var zoomLabel: String {
        let pct = Int((fontScale * 100).rounded())
        return "\(pct)%"
    }

    private func recomputeStateForFileURL() {
        saveState = (fileURL == nil) ? .untitled : .saved
    }

    private func insertFrontmatter() {
        if document.text.hasPrefix("---\n") || document.text.hasPrefix("---\r\n") { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
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

// MARK: - Custom NSTextView with reading-width margins + HR drawing

final class ReadingTextView: NSTextView {
    var maxReadingWidth: CGFloat = 760
    var basePadding: CGFloat = 28
    var verticalPadding: CGFloat = 32

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateReadingMargins()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateReadingMargins()
    }

    private func updateReadingMargins() {
        let avail = bounds.width
        let extra = max(0, (avail - maxReadingWidth) / 2)
        let side = max(basePadding, basePadding + extra)
        let target = NSSize(width: side, height: verticalPadding)
        if textContainerInset != target {
            textContainerInset = target
            needsDisplay = true
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawQuoteBackgrounds(in: rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawHorizontalRules(in: dirtyRect)
        drawQuoteBars(in: dirtyRect)
        drawBullets(in: dirtyRect)
    }

    // MARK: drawing helpers

    private func drawQuoteBackgrounds(in dirtyRect: NSRect) {
        guard let lm = layoutManager,
              let tc = textContainer,
              let storage = textStorage else { return }
        let origin = textContainerOrigin
        let leftX = origin.x
        let rightX = origin.x + tc.size.width

        let fullRange = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.mtdQuoteBG, in: fullRange) { value, attrRange, _ in
            guard let color = value as? NSColor else { return }
            let glyphRange = lm.glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            let bounding = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            let r = NSRect(x: leftX, y: origin.y + bounding.minY,
                           width: rightX - leftX, height: bounding.height)
            if !r.intersects(dirtyRect) { return }
            color.setFill()
            r.fill()
        }
    }

    private func drawQuoteBars(in dirtyRect: NSRect) {
        guard let lm = layoutManager,
              let tc = textContainer,
              let storage = textStorage else { return }
        let origin = textContainerOrigin
        let leftX = origin.x
        let barWidth: CGFloat = 3

        let fullRange = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.mtdQuoteBar, in: fullRange) { value, attrRange, _ in
            guard let color = value as? NSColor else { return }
            let glyphRange = lm.glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            let bounding = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            let r = NSRect(x: leftX, y: origin.y + bounding.minY,
                           width: barWidth, height: bounding.height)
            if !r.intersects(dirtyRect) { return }
            color.setFill()
            r.fill()
        }
    }

    private func drawHorizontalRules(in dirtyRect: NSRect) {
        guard let lm = layoutManager,
              let tc = textContainer,
              let storage = textStorage else { return }
        let origin = textContainerOrigin
        let usedRect = lm.usedRect(for: tc)
        let leftX = origin.x
        let rightX = origin.x + max(usedRect.width, tc.size.width)
        let lineWidth: CGFloat = 1

        let fullRange = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.mtdHR, in: fullRange) { value, attrRange, _ in
            guard (value as? Bool) == true else { return }
            let glyphRange = lm.glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            let bounding = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            let drawRect = NSRect(
                x: leftX,
                y: origin.y + bounding.midY - lineWidth / 2,
                width: rightX - leftX,
                height: lineWidth
            )
            if !drawRect.intersects(dirtyRect) { return }
            let color = (storage.attribute(.mtdHRColor,
                                           at: attrRange.location,
                                           effectiveRange: nil) as? NSColor)
                ?? NSColor.separatorColor
            color.setFill()
            drawRect.fill()
        }
    }

    private func drawBullets(in dirtyRect: NSRect) {
        guard let lm = layoutManager,
              let tc = textContainer,
              let storage = textStorage else { return }
        let origin = textContainerOrigin
        let bullet = "•" as NSString

        let fullRange = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.mtdBullet, in: fullRange) { value, attrRange, _ in
            guard (value as? Bool) == true else { return }
            let color = (storage.attribute(.mtdBulletColor,
                                           at: attrRange.location,
                                           effectiveRange: nil) as? NSColor)
                ?? NSColor.secondaryLabelColor
            let font = (storage.attribute(.font,
                                          at: attrRange.location,
                                          effectiveRange: nil) as? NSFont)
                ?? NSFont.systemFont(ofSize: 14)
            let glyphRange = lm.glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            let bounding = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color
            ]
            let bulletSize = bullet.size(withAttributes: attrs)
            // Center bullet on hidden marker glyph
            let cx = origin.x + bounding.midX
            let cy = origin.y + bounding.midY
            let drawRect = NSRect(
                x: cx - bulletSize.width / 2,
                y: cy - bulletSize.height / 2,
                width: bulletSize.width,
                height: bulletSize.height
            )
            if !drawRect.intersects(dirtyRect) { return }
            bullet.draw(at: drawRect.origin, withAttributes: attrs)
        }
    }
}

// MARK: - Editor

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let mode: DisplayMode
    let palette: ThemePalette
    let scale: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        // Manually construct the text stack so we can use ReadingTextView.
        let textContainer = NSTextContainer(size: NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        ))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        layoutManager.allowsNonContiguousLayout = true

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let tv = ReadingTextView(frame: .zero, textContainer: textContainer)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]

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

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = tv

        tv.string = text
        applyAppearance(to: tv)
        context.coordinator.lastMode = mode
        context.coordinator.applyHighlighting(to: tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? ReadingTextView else { return }
        context.coordinator.parent = self
        applyAppearance(to: tv)
        if tv.string != text { tv.string = text }
        context.coordinator.applyHighlighting(to: tv)
        context.coordinator.lastMode = mode
    }

    fileprivate func bodyFontForCurrentMode() -> NSFont {
        let base = mode == .rendered ? palette.renderedBodyFont : palette.rawBodyFont
        return scaled(base)
    }

    fileprivate func scaled(_ font: NSFont) -> NSFont {
        let s = max(0.5, min(3.0, scale))
        return NSFont(descriptor: font.fontDescriptor, size: font.pointSize * s) ?? font
    }

    private func applyAppearance(to tv: NSTextView) {
        tv.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        tv.backgroundColor = palette.background
        tv.drawsBackground = true
        tv.insertionPointColor = palette.bodyColor
        tv.font = bodyFontForCurrentMode()
        tv.textColor = palette.bodyColor
        tv.linkTextAttributes = [
            .foregroundColor: palette.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        tv.typingAttributes = [
            .font: bodyFontForCurrentMode(),
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
            if parent.mode == .rendered { applyHighlighting(to: tv) }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at _: Int) -> Bool {
            if let url = link as? URL { NSWorkspace.shared.open(url); return true }
            if let s = link as? String, let u = URL(string: s) {
                NSWorkspace.shared.open(u); return true
            }
            return false
        }

        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            return handleNewline(in: tv)
        }

        private func handleNewline(in tv: NSTextView) -> Bool {
            let nsString = tv.string as NSString
            let cursor = tv.selectedRange().location
            guard cursor <= nsString.length else { return false }
            let lineRange = nsString.lineRange(for: NSRange(location: cursor, length: 0))
            let lineStart = lineRange.location
            let prefixRange = NSRange(location: lineStart, length: cursor - lineStart)
            let linePrefix = nsString.substring(with: prefixRange)

            guard let re = try? NSRegularExpression(
                pattern: #"^([ \t]*)([-*+]|(\d+)\.)([ \t]+)(.*)$"#)
            else { return false }
            let prefixNSRange = NSRange(location: 0, length: (linePrefix as NSString).length)
            guard let m = re.firstMatch(in: linePrefix, range: prefixNSRange) else { return false }

            let indent = (linePrefix as NSString).substring(with: m.range(at: 1))
            let marker = (linePrefix as NSString).substring(with: m.range(at: 2))
            let space  = (linePrefix as NSString).substring(with: m.range(at: 4))
            let content = (linePrefix as NSString).substring(with: m.range(at: 5))

            if content.isEmpty {
                let deleteRange = NSRange(location: lineStart, length: cursor - lineStart)
                if tv.shouldChangeText(in: deleteRange, replacementString: "") {
                    tv.replaceCharacters(in: deleteRange, with: "")
                    tv.didChangeText()
                }
                return true
            }

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
            let bodyFont = parent.bodyFontForCurrentMode()
            let codeFont = parent.scaled(parent.palette.codeFont)
            let scale = max(0.5, min(3.0, parent.scale))

            storage.beginEditing()
            storage.setAttributes([
                .font: bodyFont,
                .foregroundColor: parent.palette.bodyColor
            ], range: full)
            if parent.mode == .rendered {
                SyntaxHighlighter.apply(
                    to: storage,
                    range: full,
                    palette: parent.palette,
                    bodyFont: bodyFont,
                    codeFont: codeFont,
                    scale: scale,
                    cursorRange: cursorRange
                )
            }
            storage.endEditing()

            tv.typingAttributes = [
                .font: bodyFont,
                .foregroundColor: parent.palette.bodyColor
            ]
            tv.needsDisplay = true
        }
    }
}

// MARK: - Syntax highlighter (rendered mode only)

enum SyntaxHighlighter {

    static func apply(to storage: NSTextStorage,
                      range: NSRange,
                      palette: ThemePalette,
                      bodyFont: NSFont,
                      codeFont: NSFont,
                      scale: CGFloat,
                      cursorRange: NSRange) {
        let str = storage.string

        // 0. HTML comments — hidden in rendered mode (multi-line capable)
        enumerate(#"<!--[\s\S]*?-->"#,
                  in: str, range: range,
                  options: [.dotMatchesLineSeparators]) { m in
            // Per-line: collapse each line's chars; newlines will leave their own height.
            // For block comments on their own line, also kill the paragraph spacing.
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: m.range)
            let charWidth = ("M" as NSString).size(withAttributes: [.font: bodyFont]).width
            storage.addAttribute(.kern, value: NSNumber(value: -Double(charWidth)), range: m.range)

            // If the comment occupies an entire line by itself, collapse that line's height.
            let nsStr = str as NSString
            let lineRange = nsStr.lineRange(for: m.range)
            // Trim trailing newline for comparison
            var trimmedLine = lineRange
            if trimmedLine.length > 0 {
                let last = nsStr.character(at: trimmedLine.location + trimmedLine.length - 1)
                if last == 0x0A { trimmedLine.length -= 1 }
            }
            if trimmedLine.location == m.range.location && trimmedLine.length == m.range.length {
                let para = NSMutableParagraphStyle()
                para.maximumLineHeight = 0.01
                para.minimumLineHeight = 0.01
                para.paragraphSpacing = 0
                para.paragraphSpacingBefore = 0
                storage.addAttribute(.paragraphStyle, value: para, range: lineRange)
            }
        }

        // 1. Frontmatter
        enumerate(#"\A---[ \t]*\n(.*?)\n---[ \t]*$"#,
                  in: str, range: range,
                  options: [.dotMatchesLineSeparators, .anchorsMatchLines]) { m in
            storage.addAttribute(.foregroundColor, value: palette.frontmatterColor, range: m.range)
        }

        // 2. Fenced code blocks
        enumerate(#"^```[A-Za-z0-9_+-]*[ \t]*\n([\s\S]*?)\n```[ \t]*$"#,
                  in: str, range: range, options: .anchorsMatchLines) { m in
            storage.addAttribute(.backgroundColor, value: palette.codeBackground, range: m.range)
            storage.addAttribute(.font, value: codeFont, range: m.range)
            (try? NSRegularExpression(pattern: "^```[^\n]*$", options: .anchorsMatchLines))?
                .enumerateMatches(in: str, range: m.range) { fm, _, _ in
                    if let fm = fm {
                        storage.addAttribute(.foregroundColor,
                                             value: palette.codeFenceColor, range: fm.range)
                    }
                }
        }

        // 3. Horizontal rule:  --- / *** / ___ on a line — drawn as full-width line
        enumerate(#"^[ \t]*(-{3,}|\*{3,}|_{3,})[ \t]*$"#,
                  in: str, range: range, options: .anchorsMatchLines) { m in
            storage.addAttribute(.mtdHR, value: true, range: m.range)
            storage.addAttribute(.mtdHRColor, value: palette.hrColor, range: m.range)
            // Hide the dashes; the line is drawn separately by the text view
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: m.range)
        }

        // 4. Blockquote — left bar + box bg drawn by view; > markers hidden
        enumerate(#"^>\s?.*$"#, in: str, range: range, options: .anchorsMatchLines) { m in
            let para = NSMutableParagraphStyle()
            para.firstLineHeadIndent = 14
            para.headIndent = 14
            storage.addAttribute(.paragraphStyle, value: para, range: m.range)
            storage.addAttribute(.mtdQuote, value: true, range: m.range)
            storage.addAttribute(.mtdQuoteBG, value: palette.blockquoteBackground, range: m.range)
            storage.addAttribute(.mtdQuoteBar, value: palette.secondaryColor, range: m.range)
            // Hide the leading > and (optional) following space
            let lineNS = (str as NSString).substring(with: m.range)
            if lineNS.hasPrefix(">") {
                var hideLen = 1
                if lineNS.count >= 2, lineNS[lineNS.index(lineNS.startIndex, offsetBy: 1)] == " " {
                    hideLen = 2
                }
                hideRange(storage,
                          range: NSRange(location: m.range.location, length: hideLen),
                          in: bodyFont)
            }
        }

        // 5. Lists — bullet markers (-, *, +) drawn as •; numbered (1.) keeps source text
        enumerate(#"^([ \t]*)([-*+])([ \t]+)"#,
                  in: str, range: range, options: .anchorsMatchLines) { m in
            let lineRange = (str as NSString).lineRange(for: m.range)
            let para = NSMutableParagraphStyle()
            para.firstLineHeadIndent = 0
            para.headIndent = 22
            storage.addAttribute(.paragraphStyle, value: para, range: lineRange)
            let marker = m.range(at: 2)
            // Hide the source - / * / +; the view paints a • at this position
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: marker)
            storage.addAttribute(.mtdBullet, value: true, range: marker)
            storage.addAttribute(.mtdBulletColor, value: palette.secondaryColor, range: marker)
        }
        enumerate(#"^([ \t]*)(\d+\.)([ \t]+)"#,
                  in: str, range: range, options: .anchorsMatchLines) { m in
            let lineRange = (str as NSString).lineRange(for: m.range)
            let para = NSMutableParagraphStyle()
            para.firstLineHeadIndent = 0
            para.headIndent = 22
            storage.addAttribute(.paragraphStyle, value: para, range: lineRange)
            let marker = m.range(at: 2)
            storage.addAttribute(.foregroundColor, value: palette.secondaryColor, range: marker)
        }

        // 6. ATX headings — applies size + bold to whole line; #'s hide when cursor off line
        enumerate(#"^(#{1,6})[ \t]+.*$"#, in: str, range: range, options: .anchorsMatchLines) { m in
            let hashes = m.range(at: 1)
            let level = max(1, min(6, hashes.length))
            let size = palette.headingSizes[level - 1] * scale
            let descriptor = bodyFont.fontDescriptor
            let sized = NSFont(descriptor: descriptor, size: size)
                ?? NSFont.systemFont(ofSize: size)
            let bold = NSFontManager.shared.convert(sized, toHaveTrait: .boldFontMask)
            storage.addAttribute(.font, value: bold, range: m.range)

            let lineRange = (str as NSString).lineRange(for: m.range)
            if rangeContainsCursor(lineRange, cursor: cursorRange) {
                storage.addAttribute(.foregroundColor, value: palette.markerColor, range: hashes)
            } else {
                hideRange(storage, range: hashes, in: bodyFont)
            }
        }

        // 7. Bold
        enumerate(#"\*\*([^*\n]+)\*\*"#, in: str, range: range) { m in
            let baseFont = (storage.attribute(.font, at: m.range.location, effectiveRange: nil)
                            as? NSFont) ?? bodyFont
            let bold = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            storage.addAttribute(.font, value: bold, range: m.range)
            applyMarker(storage, at: m.range.location, length: 2,
                        elementRange: m.range, cursor: cursorRange,
                        markerColor: palette.markerColor, bodyFont: bodyFont)
            applyMarker(storage, at: m.range.location + m.range.length - 2, length: 2,
                        elementRange: m.range, cursor: cursorRange,
                        markerColor: palette.markerColor, bodyFont: bodyFont)
        }

        // 8. Italic
        enumerate(#"(?<!\*)\*(?!\*)([^*\n]+?)\*(?!\*)"#, in: str, range: range) { m in
            let baseFont = (storage.attribute(.font, at: m.range.location, effectiveRange: nil)
                            as? NSFont) ?? bodyFont
            let italic = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            storage.addAttribute(.font, value: italic, range: m.range)
            applyMarker(storage, at: m.range.location, length: 1,
                        elementRange: m.range, cursor: cursorRange,
                        markerColor: palette.markerColor, bodyFont: bodyFont)
            applyMarker(storage, at: m.range.location + m.range.length - 1, length: 1,
                        elementRange: m.range, cursor: cursorRange,
                        markerColor: palette.markerColor, bodyFont: bodyFont)
        }

        // 9. Italic underscores
        enumerate(#"(?<![A-Za-z0-9_])_(?!_)([^_\n]+?)_(?![A-Za-z0-9_])"#,
                  in: str, range: range) { m in
            let baseFont = (storage.attribute(.font, at: m.range.location, effectiveRange: nil)
                            as? NSFont) ?? bodyFont
            let italic = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            storage.addAttribute(.font, value: italic, range: m.range)
            applyMarker(storage, at: m.range.location, length: 1,
                        elementRange: m.range, cursor: cursorRange,
                        markerColor: palette.markerColor, bodyFont: bodyFont)
            applyMarker(storage, at: m.range.location + m.range.length - 1, length: 1,
                        elementRange: m.range, cursor: cursorRange,
                        markerColor: palette.markerColor, bodyFont: bodyFont)
        }

        // 10. Inline code
        enumerate(#"`([^`\n]+)`"#, in: str, range: range) { m in
            storage.addAttribute(.font, value: codeFont, range: m.range)
            storage.addAttribute(.backgroundColor, value: palette.codeBackground, range: m.range)
            applyMarker(storage, at: m.range.location, length: 1,
                        elementRange: m.range, cursor: cursorRange,
                        markerColor: palette.markerColor, bodyFont: bodyFont)
            applyMarker(storage, at: m.range.location + m.range.length - 1, length: 1,
                        elementRange: m.range, cursor: cursorRange,
                        markerColor: palette.markerColor, bodyFont: bodyFont)
        }

        // 11. Markdown links
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
            for offset in [m.range.location,
                           textRange.location + textRange.length,
                           urlRange.location - 1,
                           urlRange.location + urlRange.length] {
                mute(storage, at: offset, length: 1, color: palette.markerColor)
            }
        }

        // 12. Bare URLs / emails via NSDataDetector
        if let detector = try? NSDataDetector(types:
            NSTextCheckingResult.CheckingType.link.rawValue) {
            detector.enumerateMatches(in: str, range: range) { match, _, _ in
                guard let m = match, let url = m.url else { return }
                let nsStr = str as NSString
                if m.range.location > 0,
                   nsStr.character(at: m.range.location - 1) == 0x28 {
                    return
                }
                storage.addAttribute(.link, value: url, range: m.range)
                storage.addAttribute(.foregroundColor, value: palette.linkColor, range: m.range)
                storage.addAttribute(.underlineStyle,
                                     value: NSUnderlineStyle.single.rawValue, range: m.range)
            }
        }
    }

    // MARK: helpers

    private static func applyMarker(_ storage: NSTextStorage,
                                    at location: Int,
                                    length: Int,
                                    elementRange: NSRange,
                                    cursor: NSRange,
                                    markerColor: NSColor,
                                    bodyFont: NSFont) {
        let bound = (storage.string as NSString).length
        guard location >= 0, location + length <= bound else { return }
        let r = NSRange(location: location, length: length)
        if rangeContainsCursor(elementRange, cursor: cursor) {
            storage.addAttribute(.foregroundColor, value: markerColor, range: r)
        } else {
            hideRange(storage, range: r, in: bodyFont)
        }
    }

    private static func hideRange(_ storage: NSTextStorage, range: NSRange, in font: NSFont) {
        let charWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
        storage.addAttribute(.kern, value: NSNumber(value: -Double(charWidth)), range: range)
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

    private static func rangeContainsCursor(_ element: NSRange, cursor: NSRange) -> Bool {
        let cStart = cursor.location
        let cEnd = cursor.location + cursor.length
        let eStart = element.location
        let eEnd = element.location + element.length
        return cStart <= eEnd && cEnd >= eStart
    }
}

// MARK: - Help popover

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("MarkThisDown").font(.title3.bold())
                    Spacer()
                    Text(appVersion).font(.caption).foregroundStyle(.secondary)
                }

                section("Keyboard shortcuts", rows: [
                    ("⌘N", "New document"),
                    ("⌘S", "Save"),
                    ("⌘E", "Toggle raw / rendered"),
                    ("⌘L", "Cycle theme"),
                    ("⌘= / ⌘-", "Zoom in / out"),
                    ("⌘0", "Reset zoom"),
                    ("⌘W", "Close window"),
                    ("⌘F", "Find in document"),
                ])

                section("Editing tips", rows: [
                    ("Lists", "Enter continues -, *, +, or numbered. Empty marker exits."),
                    ("Markers", "**, *, ` chars hide when cursor is off the styled span."),
                    ("Links", "[text](url) or bare https://… and domain.com — click to open."),
                    ("Frontmatter", "Toolbar button inserts a YAML block at top."),
                    ("Comments", "<!-- @ note --> stays in file but doesn't render."),
                ])

                section("Terminal", rows: [
                    ("open -a MarkThisDown notes.md", "Open file"),
                    ("open -a MarkThisDown", "Untitled window"),
                    ("alias mtd='open -a MarkThisDown'", "Add to ~/.zshrc"),
                ])

                Text("Tooltip delay is a macOS setting; if hovers feel slow check System Settings → Accessibility.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .frame(maxHeight: 560)
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

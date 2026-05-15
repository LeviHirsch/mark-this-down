import SwiftUI
import AppKit
import Combine

enum DisplayMode { case rendered, raw }
enum SaveState { case untitled, autosaving, saved }

extension NSAttributedString.Key {
    static let mtdHR = NSAttributedString.Key("mtdHR")
    static let mtdHRColor = NSAttributedString.Key("mtdHRColor")
    static let mtdQuote = NSAttributedString.Key("mtdQuote")
    static let mtdQuoteBG = NSAttributedString.Key("mtdQuoteBG")
    static let mtdQuoteBar = NSAttributedString.Key("mtdQuoteBar")
    static let mtdBullet = NSAttributedString.Key("mtdBullet")
    static let mtdBulletColor = NSAttributedString.Key("mtdBulletColor")
    static let mtdComment = NSAttributedString.Key("mtdComment")
    static let mtdCommentLocation = NSAttributedString.Key("mtdCommentLocation")
    static let mtdTablePipe = NSAttributedString.Key("mtdTablePipe")
    static let mtdTablePipeColor = NSAttributedString.Key("mtdTablePipeColor")
}

private var appVersion: String {
    let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    return "v\(v)"
}

// MARK: - Editor jump request

/// Token published by the sidebar to ask the editor to scroll to and select a
/// comment location. The nonce makes re-clicks of the same card trigger another
/// jump even when `location` is unchanged.
struct EditorJumpToken: Equatable {
    let location: Int
    let nonce: Int
}

// MARK: - Comment model

struct MTDComment: Identifiable, Equatable {
    let id: Int           // range.location, stable within a single parse cycle
    let range: NSRange    // includes <!-- and -->
    let body: String      // inner text, trimmed
    let lineNumber: Int
    let contextLine: String

    static func parse(_ text: String) -> [MTDComment] {
        let nsText = text as NSString
        let fenceRanges = findFenceRanges(text)
        guard let re = try? NSRegularExpression(
            pattern: "<!--[\\s\\S]*?-->",
            options: []
        ) else { return [] }

        var results: [MTDComment] = []
        let full = NSRange(location: 0, length: nsText.length)
        re.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let m = match else { return }
            // skip if inside a code fence
            if fenceRanges.contains(where: { NSLocationInRange(m.range.location, $0) }) {
                return
            }
            let raw = nsText.substring(with: m.range)
            // body = strip leading <!-- and trailing -->
            var body = String(raw.dropFirst(4).dropLast(3))
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let lineRange = nsText.lineRange(for: NSRange(location: m.range.location, length: 0))
            let lineNumber = lineNumberFor(location: m.range.location, in: nsText)
            var context = nsText.substring(with: lineRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if context.count > 80 { context = String(context.prefix(78)) + "…" }
            results.append(MTDComment(
                id: m.range.location,
                range: m.range,
                body: body,
                lineNumber: lineNumber,
                contextLine: context
            ))
        }
        return results
    }

    private static func findFenceRanges(_ text: String) -> [NSRange] {
        guard let re = try? NSRegularExpression(
            pattern: #"^```[\s\S]*?^```[ \t]*$"#,
            options: [.anchorsMatchLines]
        ) else { return [] }
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)
        var ranges: [NSRange] = []
        re.enumerateMatches(in: text, range: full) { m, _, _ in
            if let m = m { ranges.append(m.range) }
        }
        return ranges
    }

    private static func lineNumberFor(location: Int, in nsText: NSString) -> Int {
        var line = 1
        var idx = 0
        while idx < location {
            if nsText.character(at: idx) == 0x0A { line += 1 }
            idx += 1
        }
        return line
    }
}

// MARK: - ContentView

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @State private var mode: DisplayMode = .rendered
    @State private var saveState: SaveState = .untitled
    @State private var debounceTask: Task<Void, Never>? = nil
    @State private var showHelp: Bool = false
    @State private var showSidebar: Bool = false
    @State private var focusedCommentLocation: Int? = nil
    @State private var comments: [MTDComment] = []
    @State private var jumpToken: EditorJumpToken? = nil
    @State private var frontmatterCollapsed: Bool = false
    @State private var showOutline: Bool = false
    @State private var headings: [MTDHeading] = []
    @State private var outlineJumped: Bool = false
    @StateObject private var scrollBridge = EditorScrollBridge()
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.system.rawValue
    @AppStorage("fontScale") private var fontScale: Double = 1.0

    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .system }
    private var palette: ThemePalette {
        theme.palette(systemIsDark: colorScheme == .dark)
    }

    private var hasFrontmatter: Bool {
        frontmatterRange(in: document.text) != nil
    }

    private var statusText: String {
        switch saveState {
        case .untitled:   return "Not yet saved"
        case .autosaving: return "Auto-saving…"
        case .saved:      return "Auto-saved"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ActivityBar(showOutline: $showOutline,
                        palette: palette,
                        onToggleOutline: toggleOutline)
            if showOutline {
                OutlineView(headings: headings,
                            palette: palette,
                            onSelect: jumpToHeading,
                            onClose: toggleOutline)
                    .frame(width: 240)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            MarkdownEditor(text: $document.text,
                           mode: mode,
                           palette: palette,
                           scale: CGFloat(fontScale),
                           commentRanges: comments.map { $0.range },
                           frontmatterCollapsed: frontmatterCollapsed && hasFrontmatter,
                           jumpToken: jumpToken,
                           scrollBridge: scrollBridge,
                           onCommentTap: { location in
                               focusedCommentLocation = location
                               showSidebar = true
                           })
        }
            .navigationSubtitle(statusText)
            .inspector(isPresented: $showSidebar) {
                CommentsSidebar(
                    documentText: $document.text,
                    comments: comments,
                    focusedCommentLocation: $focusedCommentLocation,
                    onAddComment: triggerAddComment,
                    onJumpToComment: { loc in
                        jumpToken = EditorJumpToken(
                            location: loc,
                            nonce: (jumpToken?.nonce ?? 0) + 1
                        )
                    }
                )
                .inspectorColumnWidth(min: 240, ideal: 300, max: 420)
            }
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
                        triggerAddComment()
                    } label: {
                        Label("Add Comment", systemImage: "text.bubble")
                    }
                    .help("Add a comment at the cursor (⌘')")

                    Button {
                        showSidebar.toggle()
                    } label: {
                        Label("Comments", systemImage: "sidebar.right")
                    }
                    .help("Toggle comments sidebar (⌘\\)")

                    Button {
                        frontmatterButtonAction()
                    } label: {
                        Label(frontmatterButtonLabel, systemImage: frontmatterButtonIcon)
                    }
                    .help(frontmatterButtonHelp)

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
            .onAppear {
                recomputeStateForFileURL()
                comments = MTDComment.parse(document.text)
                headings = parseHeadings(document.text)
            }
            .onChange(of: fileURL) { _, _ in recomputeStateForFileURL() }
            .onChange(of: document.text) { _, newText in
                comments = MTDComment.parse(newText)
                headings = parseHeadings(newText)
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
            .onReceive(NotificationCenter.default.publisher(for: .mtdToggleSidebar)) { _ in
                showSidebar.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mtdCommentAdded)) { note in
                if let loc = note.userInfo?["location"] as? Int {
                    showSidebar = true
                    focusedCommentLocation = loc
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .mtdToggleOutline)) { _ in
                toggleOutline()
            }
    }

    private func toggleOutline() {
        if showOutline {
            if outlineJumped {
                scrollBridge.discard()
            } else {
                scrollBridge.restore()
            }
            outlineJumped = false
            showOutline = false
        } else {
            scrollBridge.save()
            showOutline = true
        }
    }

    private func jumpToHeading(_ h: MTDHeading) {
        // Position the cursor at the start of the heading *text*, not at the
        // line start (before the `#`s). Walk past `#`s and the separating
        // whitespace; fall back to the line start if anything looks off.
        let ns = document.text as NSString
        var p = h.location
        let endLoc = ns.length
        while p < endLoc, ns.character(at: p) == 0x23 { p += 1 } // '#'
        while p < endLoc {
            let c = ns.character(at: p)
            if c == 0x20 || c == 0x09 { p += 1 } else { break }
        }
        jumpToken = EditorJumpToken(
            location: p,
            nonce: (jumpToken?.nonce ?? 0) + 1
        )
        outlineJumped = true
    }

    private var zoomLabel: String {
        let pct = Int((fontScale * 100).rounded())
        return "\(pct)%"
    }

    private func recomputeStateForFileURL() {
        saveState = (fileURL == nil) ? .untitled : .saved
    }

    private func triggerAddComment() {
        NSApp.sendAction(Selector(("mtdInsertCommentAction:")), to: nil, from: nil)
    }

    private func insertFrontmatter() {
        if hasFrontmatter { return }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())
        let starter = "---\ntitle: \ndate: \(today)\ntags: \n---\n\n"
        document.text = starter + document.text
        frontmatterCollapsed = false
    }

    private var frontmatterButtonLabel: String {
        if !hasFrontmatter { return "Add frontmatter" }
        return frontmatterCollapsed ? "Expand" : "Collapse"
    }

    private var frontmatterButtonIcon: String {
        if !hasFrontmatter { return "text.badge.plus" }
        return frontmatterCollapsed ? "chevron.down.circle" : "chevron.up.circle"
    }

    private var frontmatterButtonHelp: String {
        if !hasFrontmatter { return "Add minimal frontmatter at top of document" }
        return frontmatterCollapsed
            ? "Expand frontmatter block"
            : "Collapse frontmatter block"
    }

    private func frontmatterButtonAction() {
        if !hasFrontmatter {
            insertFrontmatter()
        } else {
            frontmatterCollapsed.toggle()
        }
    }
}

func frontmatterRange(in text: String) -> NSRange? {
    let pattern = #"\A---[ \t]*\n.*?\n---[ \t]*$"#
    guard let re = try? NSRegularExpression(
        pattern: pattern,
        options: [.dotMatchesLineSeparators, .anchorsMatchLines]
    ) else { return nil }
    let ns = text as NSString
    let full = NSRange(location: 0, length: ns.length)
    return re.firstMatch(in: text, range: full)?.range
}

// MARK: - Comments Sidebar

struct CommentsSidebar: View {
    @Binding var documentText: String
    let comments: [MTDComment]
    @Binding var focusedCommentLocation: Int?
    let onAddComment: () -> Void
    let onJumpToComment: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Comments")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onAddComment) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add comment at cursor (⌘')")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if comments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No comments yet.\nPress ⌘' to add one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(comments) { c in
                                CommentCard(
                                    comment: c,
                                    isFocused: c.id == focusedCommentLocation,
                                    onUpdate: { updateBody(of: c, to: $0) },
                                    onDelete: { deleteComment(c) },
                                    onTap: {
                                        focusedCommentLocation = c.id
                                        onJumpToComment(c.id)
                                    }
                                )
                                .id(c.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: focusedCommentLocation) { _, new in
                        guard let new else { return }
                        if comments.contains(where: { $0.id == new }) {
                            withAnimation { proxy.scrollTo(new, anchor: .center) }
                        }
                    }
                }
            }
        }
    }

    private func updateBody(of comment: MTDComment, to newBody: String) {
        let nsText = documentText as NSString
        guard NSMaxRange(comment.range) <= nsText.length else { return }
        let cleaned = newBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement: String
        if cleaned.isEmpty {
            replacement = "<!--  -->"
        } else if cleaned.contains("\n") {
            replacement = "<!--\n\(cleaned)\n-->"
        } else {
            replacement = "<!-- \(cleaned) -->"
        }
        let updated = nsText.replacingCharacters(in: comment.range, with: replacement)
        if updated != documentText { documentText = updated }
    }

    private func deleteComment(_ comment: MTDComment) {
        let nsText = documentText as NSString
        guard NSMaxRange(comment.range) <= nsText.length else { return }
        documentText = nsText.replacingCharacters(in: comment.range, with: "")
        focusedCommentLocation = nil
    }
}

// MARK: - Comment Card

struct CommentCard: View {
    let comment: MTDComment
    let isFocused: Bool
    let onUpdate: (String) -> Void
    let onDelete: () -> Void
    let onTap: () -> Void

    @State private var editingBody: String
    @FocusState private var bodyFocused: Bool

    init(comment: MTDComment,
         isFocused: Bool,
         onUpdate: @escaping (String) -> Void,
         onDelete: @escaping () -> Void,
         onTap: @escaping () -> Void) {
        self.comment = comment
        self.isFocused = isFocused
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onTap = onTap
        self._editingBody = State(initialValue: comment.body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Line \(comment.lineNumber)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    // Defocus first so the text field doesn't try to commit
                    // a stale body after deletion.
                    bodyFocused = false
                    DispatchQueue.main.async { onDelete() }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete comment")
            }

            commentEditor
                .background(
                    // Hidden Esc-handler. .cancelAction binds Esc; running buttons run only
                    // when this view's window contains the responder.
                    Group {
                        if bodyFocused {
                            Button("") {
                                editingBody = comment.body
                                bodyFocused = false
                            }
                            .keyboardShortcut(.cancelAction)
                            .opacity(0)
                            .frame(width: 0, height: 0)
                        }
                    }
                )

            if !comment.contextLine.isEmpty {
                Text(comment.contextLine)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isFocused
                      ? Color.accentColor.opacity(0.12)
                      : Color.gray.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused
                        ? Color.accentColor.opacity(0.6)
                        : Color.gray.opacity(0.18), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onAppear { editingBody = comment.body }
        .task {
            if isFocused { bodyFocused = true }
        }
        .onChange(of: comment.body) { _, newBody in
            if !bodyFocused { editingBody = newBody }
        }
        .onChange(of: isFocused) { _, focused in
            if focused { bodyFocused = true }
        }
        .onChange(of: bodyFocused) { _, focused in
            if focused {
                onTap()
            } else if editingBody != comment.body {
                onUpdate(editingBody)
            }
        }
    }

    @ViewBuilder
    private var commentEditor: some View {
        TextField("Comment", text: $editingBody, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...12)
            .focused($bodyFocused)
            .onKeyPress { press in
                if press.key == .return,
                   !press.modifiers.contains(.shift),
                   !press.modifiers.contains(.command) {
                    bodyFocused = false
                    return .handled
                }
                return .ignored
            }
    }
}

// MARK: - ReadingTextView

final class ReadingTextView: NSTextView {
    var maxReadingWidth: CGFloat = 760
    var basePadding: CGFloat = 28
    var verticalPadding: CGFloat = 32

    var onCommentTap: ((Int) -> Void)?

    private let marginIconSize: CGFloat = 22
    private let marginIconRightInset: CGFloat = 8
    private let marginIconReserve: CGFloat = 44   // right-side reserved area for comment icons

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateReadingMargins()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateReadingMargins()
    }

    private func updateReadingMargins() {
        guard let tc = textContainer else { return }
        let avail = bounds.width
        let reserve = marginIconReserve
        // Target text container width: capped at maxReadingWidth, never below 40.
        let targetContainer = min(maxReadingWidth,
                                  max(40, avail - 2 * basePadding - reserve))
        let slack = max(0, avail - targetContainer - reserve)
        let leftPad = max(basePadding, slack / 2)
        let rightPad = leftPad + reserve
        let containerWidth = max(40, avail - leftPad - rightPad)

        let inset = NSSize(width: leftPad, height: verticalPadding)
        if textContainerInset != inset { textContainerInset = inset }
        if tc.widthTracksTextView { tc.widthTracksTextView = false }
        if abs(tc.size.width - containerWidth) > 0.5 {
            tc.size = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        needsDisplay = true
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
        drawTablePipes(in: dirtyRect)

        // Margin icons live OUTSIDE the textContainer clip — expand to full bounds.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).setClip()
        drawCommentMarginIcons(in: dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Mouse handling for margin icon click

    override func mouseDown(with event: NSEvent) {
        let pointInView = convert(event.locationInWindow, from: nil)
        // Precise hit on a comment icon → focus that comment.
        // Otherwise — including the empty right-margin band — fall through to
        // default text-view handling (no-op for the margin, no fallback).
        if let location = commentLocationForMarginIcon(at: pointInView) {
            onCommentTap?(location)
            return
        }
        super.mouseDown(with: event)
    }

    // Force-claim hit-tests in our bounds so right-margin clicks reach mouseDown.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if bounds.contains(local) { return self }
        return super.hitTest(point)
    }

    private func commentLocationForMarginIcon(at point: NSPoint) -> Int? {
        guard let lm = layoutManager,
              let tc = textContainer,
              let storage = textStorage else { return nil }
        let origin = textContainerOrigin
        let rightX = origin.x + tc.size.width
        // Quick reject: must be in the reserved right margin band (generous bounds)
        if point.x < rightX || point.x > rightX + marginIconReserve + 8 { return nil }

        let full = NSRange(location: 0, length: storage.length)
        var found: Int? = nil
        storage.enumerateAttribute(.mtdComment, in: full) { value, attrRange, stop in
            guard (value as? Bool) == true else { return }
            let glyphRange = lm.glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            let bounding = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            // Use the icon's full LINE band as the hit area — easier to click.
            let lineBand = NSRect(
                x: rightX,
                y: origin.y + bounding.minY,
                width: marginIconReserve + 8,
                height: max(bounding.height, marginIconSize + 4)
            )
            if lineBand.contains(point) {
                if let loc = storage.attribute(.mtdCommentLocation,
                                               at: attrRange.location,
                                               effectiveRange: nil) as? Int {
                    found = loc
                }
                stop.pointee = true
            }
        }
        return found
    }

    private func marginIconRect(for bounding: NSRect, origin: NSPoint) -> NSRect {
        // Place icon JUST OUTSIDE the right edge of the text container,
        // inside the reserved right margin band.
        let rightX = origin.x + (textContainer?.size.width ?? 0)
        let cy = origin.y + bounding.midY
        return NSRect(
            x: rightX + marginIconRightInset,
            y: cy - marginIconSize / 2,
            width: marginIconSize,
            height: marginIconSize
        )
    }

    // MARK: - Custom drawing

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

    private func drawTablePipes(in dirtyRect: NSRect) {
        guard let lm = layoutManager,
              let tc = textContainer,
              let storage = textStorage else { return }
        let origin = textContainerOrigin
        let lineWidth: CGFloat = 1

        let fullRange = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.mtdTablePipe, in: fullRange) { value, attrRange, _ in
            guard (value as? Bool) == true else { return }
            let color = (storage.attribute(.mtdTablePipeColor,
                                           at: attrRange.location,
                                           effectiveRange: nil) as? NSColor)
                ?? NSColor.separatorColor
            let glyphRange = lm.glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            let bounding = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            let r = NSRect(
                x: origin.x + bounding.midX - lineWidth / 2,
                y: origin.y + bounding.minY,
                width: lineWidth,
                height: bounding.height
            )
            if !r.intersects(dirtyRect) { return }
            color.setFill()
            r.fill()
        }
    }

    private func drawCommentMarginIcons(in dirtyRect: NSRect) {
        guard let lm = layoutManager,
              let tc = textContainer,
              let storage = textStorage else { return }
        let origin = textContainerOrigin

        guard let baseSymbol = NSImage(systemSymbolName: "text.bubble",
                                       accessibilityDescription: nil) else { return }
        let tint = NSColor.secondaryLabelColor.usingColorSpace(.sRGB)
            ?? NSColor.secondaryLabelColor
        let cfg = NSImage.SymbolConfiguration(pointSize: marginIconSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        let configured = baseSymbol.withSymbolConfiguration(cfg) ?? baseSymbol

        var seenY: Set<Int> = []
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.mtdComment, in: fullRange) { value, attrRange, _ in
            guard (value as? Bool) == true else { return }
            let glyphRange = lm.glyphRange(forCharacterRange: attrRange,
                                           actualCharacterRange: nil)
            let bounding = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            let key = Int((origin.y + bounding.minY).rounded())
            if seenY.contains(key) { return }
            seenY.insert(key)
            let iconRect = marginIconRect(for: bounding, origin: origin)
            configured.draw(in: iconRect, from: .zero,
                            operation: .sourceOver, fraction: 1.0,
                            respectFlipped: true, hints: nil)
        }
    }

    // MARK: - Smart comment insertion (called via responder chain from ⌘')

    @objc func mtdInsertCommentAction(_ sender: Any?) {
        let nsText = string as NSString
        let sel = selectedRange()

        // AC7: cursor inside (or on the delimiter line of) a frontmatter block → no-op.
        if let fm = frontmatterRange(in: nsText as String) {
            let cursor = sel.location
            let lineRangeOfCursor = nsText.lineRange(
                for: NSRange(location: min(cursor, nsText.length), length: 0)
            )
            let fmEnd = NSMaxRange(fm)
            // Inside the frontmatter span OR on a line that lies within it.
            if (cursor >= fm.location && cursor <= fmEnd) ||
                (lineRangeOfCursor.location >= fm.location
                    && lineRangeOfCursor.location < fmEnd) {
                return
            }
        }

        let plan = computeCommentInsertion(in: nsText as String, selection: sel)

        let insertion = plan.insertion
        let location = plan.insertion_location
        let newCursor = plan.cursor_location

        let replaceRange = NSRange(location: location, length: 0)
        if shouldChangeText(in: replaceRange, replacementString: insertion) {
            // Use NSAttributedString to inherit current typing attrs
            let attr = NSAttributedString(string: insertion, attributes: typingAttributes)
            textStorage?.replaceCharacters(in: replaceRange, with: attr)
            didChangeText()
        }

        setSelectedRange(NSRange(location: newCursor, length: 0))
        scrollRangeToVisible(NSRange(location: newCursor, length: 0))

        // Notify ContentView to open sidebar and focus
        let commentLoc = location
        NotificationCenter.default.post(
            name: .mtdCommentAdded,
            object: nil,
            userInfo: ["location": commentLoc]
        )
    }

    private struct InsertionPlan {
        let insertion: String
        let insertion_location: Int
        let cursor_location: Int
    }

    private func computeCommentInsertion(in text: String, selection: NSRange) -> InsertionPlan {
        let nsText = text as NSString

        // Empty selection — DEC-002 cursor-position-aware rule.
        if selection.length == 0 {
            let lineRange = nsText.lineRange(for: NSRange(location: selection.location, length: 0))
            let lineText = nsText.substring(with: lineRange)
            // Structural marker: heading `#{1,6} `, bullet `[-*+] `,
            // numbered `\d+\. `, blockquote `> `. Capture the marker so we
            // can find the first text-char offset.
            let markerPattern = #"^[ \t]*(#{1,6}|[-*+]|\d+\.|>)[ \t]+"#
            if let markerRange = lineText.range(of: markerPattern, options: .regularExpression),
               markerRange.lowerBound == lineText.startIndex {
                let markerEndOffset = lineText.distance(from: lineText.startIndex,
                                                        to: markerRange.upperBound)
                let firstTextCharLoc = lineRange.location + markerEndOffset
                let cursor = selection.location
                if cursor <= firstTextCharLoc {
                    // Marker zone → insert at end-of-line. Compute EOL = end
                    // of lineRange minus the trailing newline (if any).
                    var eol = NSMaxRange(lineRange)
                    if eol > lineRange.location {
                        let last = nsText.character(at: eol - 1)
                        if last == 0x0A { eol -= 1 }
                    }
                    let needsLeadingSpace: Bool = {
                        if eol == lineRange.location { return false }
                        let prev = nsText.character(at: eol - 1)
                        return !(prev == 0x20 || prev == 0x09)
                    }()
                    let template = needsLeadingSpace ? " <!--  -->" : "<!--  -->"
                    let cursorOffset = needsLeadingSpace ? 6 : 5
                    return InsertionPlan(
                        insertion: template,
                        insertion_location: eol,
                        cursor_location: eol + cursorOffset
                    )
                }
                // Past marker zone → fall through to inline-at-cursor below.
            }
            // Inline at cursor. Leading space if not already preceded by ws.
            let cursor = selection.location
            let needsLeadingSpace: Bool = {
                if cursor == 0 { return false }
                if cursor > nsText.length { return false }
                let prev = nsText.character(at: cursor - 1)
                if prev == 0x0A { return false }
                return !(prev == 0x20 || prev == 0x09)
            }()
            let template = needsLeadingSpace ? " <!--  -->" : "<!--  -->"
            let cursorOffset = needsLeadingSpace ? 6 : 5
            return InsertionPlan(
                insertion: template,
                insertion_location: cursor,
                cursor_location: cursor + cursorOffset
            )
        }

        let selText = nsText.substring(with: selection)
        if selText.contains("\n") {
            let lineRange = nsText.lineRange(for: NSRange(location: selection.location, length: 0))
            let template = "<!--  -->\n"
            return InsertionPlan(
                insertion: template,
                insertion_location: lineRange.location,
                cursor_location: lineRange.location + 5
            )
        }
        let after = NSMaxRange(selection)
        let template = " <!--  -->"
        return InsertionPlan(
            insertion: template,
            insertion_location: after,
            cursor_location: after + 6
        )
    }
}

// MARK: - Line-number ruler (raw mode only)

final class LineNumberRulerView: NSRulerView {
    var lineNumberColor: NSColor = .secondaryLabelColor
    var rulerFont: NSFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    init(textView: NSTextView, scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 44
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = clientView as? NSTextView,
              let lm = tv.layoutManager,
              let tc = tv.textContainer else { return }
        let nsString = tv.string as NSString
        if nsString.length == 0 { return }

        // Paint background to match the text view so the gutter blends in.
        if let bg = tv.backgroundColor.usingColorSpace(.sRGB) {
            bg.setFill()
            bounds.fill()
        }

        let visibleRect = tv.visibleRect
        let glyphRange = lm.glyphRange(forBoundingRect: visibleRect, in: tc)
        if glyphRange.length == 0 && nsString.length > 0 { return }
        let charRange = lm.characterRange(forGlyphRange: glyphRange,
                                          actualGlyphRange: nil)

        // Compute starting logical line number by counting newlines before charRange.
        var lineNumber = 1
        var idx = 0
        while idx < charRange.location {
            if nsString.character(at: idx) == 0x0A { lineNumber += 1 }
            idx += 1
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: rulerFont,
            .foregroundColor: lineNumberColor
        ]

        let originY = tv.textContainerOrigin.y
        var cursor = charRange.location
        let endChar = NSMaxRange(charRange)

        // Iterate by paragraph (logical line). Only the first line fragment of
        // each paragraph gets a number — wrapped continuation rows are skipped.
        while cursor < endChar {
            let lineRange = nsString.lineRange(for: NSRange(location: cursor, length: 0))
            let glyphIdx = lm.glyphIndexForCharacter(at: lineRange.location)
            var effective = NSRange(location: 0, length: 0)
            let fragRect = lm.lineFragmentRect(forGlyphAt: glyphIdx,
                                               effectiveRange: &effective)

            // Convert fragment rect (layoutManager coords) to ruler coords.
            // textContainerOrigin already accounts for textContainerInset.
            let yInTextView = fragRect.minY + originY
            let yInRuler = yInTextView - visibleRect.minY

            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attrs)
            let drawRect = NSRect(
                x: bounds.width - size.width - 6,
                y: yInRuler + (fragRect.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            label.draw(in: drawRect, withAttributes: attrs)

            lineNumber += 1
            let next = NSMaxRange(lineRange)
            if next <= cursor { break }
            cursor = next
        }
    }
}

// MARK: - Editor

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let mode: DisplayMode
    let palette: ThemePalette
    let scale: CGFloat
    let commentRanges: [NSRange]
    let frontmatterCollapsed: Bool
    let jumpToken: EditorJumpToken?
    let scrollBridge: EditorScrollBridge
    let onCommentTap: (Int) -> Void

    func makeNSView(context: Context) -> NSScrollView {
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
        tv.onCommentTap = onCommentTap

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
        scrollBridge.scrollView = scroll

        let ruler = LineNumberRulerView(textView: tv, scrollView: scroll)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = (mode == .raw)
        ruler.lineNumberColor = palette.lineNumberColor
        context.coordinator.ruler = ruler

        // Redraw the gutter on text edits and on every scroll tick.
        // Cocoa redraws on scroll *most* of the time, but with
        // allowsNonContiguousLayout = true the layout manager can return stale
        // fragment rects mid-scroll — observing contentView bounds keeps the
        // gutter glued to the text.
        NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: tv, queue: .main
        ) { [weak ruler] _ in
            ruler?.needsDisplay = true
        }
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scroll.contentView, queue: .main
        ) { [weak ruler] _ in
            ruler?.needsDisplay = true
        }

        tv.string = text
        applyAppearance(to: tv)
        context.coordinator.lastMode = mode
        context.coordinator.applyHighlighting(to: tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? ReadingTextView else { return }
        context.coordinator.parent = self
        tv.onCommentTap = onCommentTap
        if scrollBridge.scrollView !== scroll { scrollBridge.scrollView = scroll }
        applyAppearance(to: tv)
        if tv.string != text {
            Self.smartReplace(in: tv, with: text)
        }
        context.coordinator.applyHighlighting(to: tv)
        context.coordinator.lastMode = mode

        // Line-number gutter visibility tracks raw mode (AC11.3).
        scroll.rulersVisible = (mode == .raw)
        if let ruler = context.coordinator.ruler {
            ruler.lineNumberColor = palette.lineNumberColor
            ruler.needsDisplay = true
        }

        // Run the sidebar-requested jump AFTER applyHighlighting so the highlight
        // path's save/restore of scroll origin (ContentView.swift:1183-1188) does
        // not immediately undo our intentional scroll change.
        if let token = jumpToken,
           token.nonce != context.coordinator.lastAppliedJumpNonce {
            let len = (tv.string as NSString).length
            if token.location >= 0 && token.location <= len {
                let r = NSRange(location: token.location, length: 0)
                tv.setSelectedRange(r)
                tv.scrollRangeToVisible(r)
            }
            context.coordinator.lastAppliedJumpNonce = token.nonce
        }
    }

    /// Replace only the changed range — preserves cursor, scroll, selection, focus.
    /// Used when the binding mutates from outside (e.g. comment edits in sidebar).
    fileprivate static func smartReplace(in tv: NSTextView, with newText: String) {
        let oldNS = tv.string as NSString
        let newNS = newText as NSString
        let oldLen = oldNS.length
        let newLen = newNS.length
        if oldLen == newLen && oldNS.isEqual(to: newText) { return }

        // Find common prefix length
        var prefix = 0
        let upper = min(oldLen, newLen)
        while prefix < upper
            && oldNS.character(at: prefix) == newNS.character(at: prefix) {
            prefix += 1
        }
        // Find common suffix length
        var suffix = 0
        while suffix < (upper - prefix)
            && oldNS.character(at: oldLen - 1 - suffix)
               == newNS.character(at: newLen - 1 - suffix) {
            suffix += 1
        }

        let oldChange = NSRange(location: prefix, length: oldLen - prefix - suffix)
        let newSubLen = newLen - prefix - suffix
        let replacement = newNS.substring(with: NSRange(location: prefix, length: newSubLen))

        guard let storage = tv.textStorage else { return }
        // Direct storage mutation — does NOT fire textDidChange (that's user-edits only),
        // does NOT touch undo, does NOT scroll.
        storage.beginEditing()
        storage.replaceCharacters(in: oldChange, with: replacement)
        storage.endEditing()
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
        var lastAppliedJumpNonce: Int = 0
        weak var ruler: LineNumberRulerView?

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

            // Save scroll position; layout invalidation from setAttributes can
            // nudge the visible area otherwise.
            let savedScroll = tv.enclosingScrollView?.contentView.bounds.origin

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
                    cursorRange: cursorRange,
                    commentRanges: parent.commentRanges,
                    frontmatterCollapsed: parent.frontmatterCollapsed
                )
            } else {
                // Raw mode: still mark comment ranges so margin icon shows
                for r in parent.commentRanges {
                    if NSMaxRange(r) <= full.length {
                        storage.addAttribute(.mtdComment, value: true, range: r)
                        storage.addAttribute(.mtdCommentLocation,
                                             value: r.location, range: r)
                    }
                }
            }
            storage.endEditing()

            tv.typingAttributes = [
                .font: bodyFont,
                .foregroundColor: parent.palette.bodyColor
            ]
            tv.needsDisplay = true

            // Restore scroll position so re-highlight doesn't visually shift the doc.
            if let savedScroll, let clip = tv.enclosingScrollView?.contentView {
                if clip.bounds.origin != savedScroll {
                    clip.setBoundsOrigin(savedScroll)
                    tv.enclosingScrollView?.reflectScrolledClipView(clip)
                }
            }
        }
    }
}

// MARK: - Syntax highlighter

enum SyntaxHighlighter {

    static func apply(to storage: NSTextStorage,
                      range: NSRange,
                      palette: ThemePalette,
                      bodyFont: NSFont,
                      codeFont: NSFont,
                      scale: CGFloat,
                      cursorRange: NSRange,
                      commentRanges: [NSRange],
                      frontmatterCollapsed: Bool = false) {
        let str = storage.string

        // Tag every comment range so the margin icon renders in both modes
        for r in commentRanges {
            if NSMaxRange(r) <= range.length {
                storage.addAttribute(.mtdComment, value: true, range: r)
                storage.addAttribute(.mtdCommentLocation, value: r.location, range: r)
            }
        }

        // 0. Hide HTML comments in rendered mode. If a comment fully owns its line
        //    (no other text on the line), collapse the line's height so it doesn't
        //    leave a visible blank in render.
        for r in commentRanges {
            guard NSMaxRange(r) <= range.length else { continue }
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: r)
            let charWidth = ("M" as NSString).size(withAttributes: [.font: bodyFont]).width
            storage.addAttribute(.kern, value: NSNumber(value: -Double(charWidth)), range: r)

            let nsStr = str as NSString
            let lineRange = nsStr.lineRange(for: r)
            var trimmed = lineRange
            if trimmed.length > 0 {
                let last = nsStr.character(at: trimmed.location + trimmed.length - 1)
                if last == 0x0A { trimmed.length -= 1 }
            }
            // DEC-002: comment-only lines always render as a visible blank
            // row. The block-above-structural-line heuristic was eliminated
            // when structural-line insertion moved to EOL.
            _ = trimmed
        }

        // 1. Frontmatter
        enumerate(#"\A---[ \t]*\n(.*?)\n---[ \t]*$"#,
                  in: str, range: range,
                  options: [.dotMatchesLineSeparators, .anchorsMatchLines]) { m in
            storage.addAttribute(.foregroundColor, value: palette.frontmatterColor, range: m.range)

            if frontmatterCollapsed {
                // Hide the entire frontmatter block — opening `---`, content,
                // and closing `---` all disappear. Include the trailing newline
                // so no blank row remains. State change does not modify
                // document.text — purely a visual collapse.
                let nsStr = str as NSString
                let closingLine = nsStr.lineRange(
                    for: NSRange(location: NSMaxRange(m.range) - 1, length: 0)
                )
                let hideStart = m.range.location
                let hideEnd = NSMaxRange(closingLine)
                guard hideStart < hideEnd else { return }
                let hideRange = NSRange(location: hideStart, length: hideEnd - hideStart)
                let para = NSMutableParagraphStyle()
                para.maximumLineHeight = 0.01
                para.minimumLineHeight = 0.01
                para.paragraphSpacing = 0
                para.paragraphSpacingBefore = 0
                storage.addAttribute(.paragraphStyle, value: para, range: hideRange)
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: hideRange)
                let charWidth = ("M" as NSString).size(withAttributes: [.font: bodyFont]).width
                storage.addAttribute(.kern, value: NSNumber(value: -Double(charWidth)),
                                     range: hideRange)
            }
        }

        // 2. Fenced code blocks
        var fenceRanges: [NSRange] = []
        enumerate(#"^```[A-Za-z0-9_+-]*[ \t]*\n([\s\S]*?)\n```[ \t]*$"#,
                  in: str, range: range, options: .anchorsMatchLines) { m in
            fenceRanges.append(m.range)
            storage.addAttribute(.backgroundColor, value: palette.codeBackground, range: m.range)
            storage.addAttribute(.font, value: codeFont, range: m.range)
            // Hide the opening and closing fence-delimiter lines in rendered
            // mode — unless the cursor is somewhere inside this fence (in
            // which case the delimiters reappear so the user can edit them).
            let cursorInFence = rangeContainsCursor(m.range, cursor: cursorRange)
            (try? NSRegularExpression(pattern: "^```[^\n]*$", options: .anchorsMatchLines))?
                .enumerateMatches(in: str, range: m.range) { fm, _, _ in
                    guard let fm = fm else { return }
                    if cursorInFence {
                        storage.addAttribute(.foregroundColor,
                                             value: palette.codeFenceColor, range: fm.range)
                        return
                    }
                    let para = NSMutableParagraphStyle()
                    para.maximumLineHeight = 0.01
                    para.minimumLineHeight = 0.01
                    para.paragraphSpacing = 0
                    para.paragraphSpacingBefore = 0
                    storage.addAttribute(.paragraphStyle, value: para, range: fm.range)
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: fm.range)
                    let cw = ("M" as NSString).size(withAttributes: [.font: codeFont]).width
                    storage.addAttribute(.kern, value: NSNumber(value: -Double(cw)), range: fm.range)
                }
        }

        // Frontmatter range (used as a skip-zone for tables and path/tag coloring)
        var frontmatterRange: NSRange? = nil
        if let re = try? NSRegularExpression(
            pattern: #"\A---[ \t]*\n.*?\n---[ \t]*$"#,
            options: [.dotMatchesLineSeparators, .anchorsMatchLines]
        ), let m = re.firstMatch(in: str, range: range) {
            frontmatterRange = m.range
        }

        let isInFenceOrFrontmatter: (NSRange) -> Bool = { r in
            if let fm = frontmatterRange, NSIntersectionRange(r, fm).length > 0 { return true }
            return fenceRanges.contains { NSIntersectionRange(r, $0).length > 0 }
        }

        // 2.5 GFM pipe tables. Detect: header line with at least one `|`, followed
        //     by a separator line `| --- | --- |` (with optional alignment colons),
        //     followed by zero or more body lines containing `|`.
        applyTables(to: storage,
                    str: str,
                    range: range,
                    palette: palette,
                    codeFont: codeFont,
                    bodyFont: bodyFont,
                    skip: isInFenceOrFrontmatter)

        // 3. Horizontal rule
        enumerate(#"^[ \t]*(-{3,}|\*{3,}|_{3,})[ \t]*$"#,
                  in: str, range: range, options: .anchorsMatchLines) { m in
            storage.addAttribute(.mtdHR, value: true, range: m.range)
            storage.addAttribute(.mtdHRColor, value: palette.hrColor, range: m.range)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: m.range)
        }

        // 4. Blockquote
        enumerate(#"^>\s?.*$"#, in: str, range: range, options: .anchorsMatchLines) { m in
            let para = NSMutableParagraphStyle()
            para.firstLineHeadIndent = 14
            para.headIndent = 14
            storage.addAttribute(.paragraphStyle, value: para, range: m.range)
            storage.addAttribute(.mtdQuote, value: true, range: m.range)
            storage.addAttribute(.mtdQuoteBG, value: palette.blockquoteBackground, range: m.range)
            storage.addAttribute(.mtdQuoteBar, value: palette.secondaryColor, range: m.range)
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

        // 5. Lists
        enumerate(#"^([ \t]*)([-*+])([ \t]+)"#,
                  in: str, range: range, options: .anchorsMatchLines) { m in
            let lineRange = (str as NSString).lineRange(for: m.range)
            let para = NSMutableParagraphStyle()
            para.firstLineHeadIndent = 0
            para.headIndent = 22
            storage.addAttribute(.paragraphStyle, value: para, range: lineRange)
            let marker = m.range(at: 2)
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

        // 6. Headings
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
            // Include the whitespace separating `#`s from heading text — it's
            // part of the heading marker, not the title.
            let strNS = str as NSString
            var end = NSMaxRange(hashes)
            let rangeEnd = NSMaxRange(range)
            while end < rangeEnd {
                let c = strNS.character(at: end)
                if c == 0x20 || c == 0x09 { end += 1 } else { break }
            }
            let marker = NSRange(location: hashes.location, length: end - hashes.location)
            if rangeContainsCursor(lineRange, cursor: cursorRange) {
                storage.addAttribute(.foregroundColor, value: palette.markerColor, range: marker)
            } else {
                // Use the heading's actual bold font for kern math so the
                // separating space — which is wider in the heading font than
                // in bodyFont — collapses fully.
                hideRange(storage, range: marker, in: bold)
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
        var mdLinkRanges: [NSRange] = []
        enumerate(#"\[([^\]\n]+)\]\(([^)\n]+)\)"#, in: str, range: range) { m in
            mdLinkRanges.append(m.range)
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

        // 12. Bare URLs
        var bareURLRanges: [NSRange] = []
        if let detector = try? NSDataDetector(types:
            NSTextCheckingResult.CheckingType.link.rawValue) {
            detector.enumerateMatches(in: str, range: range) { match, _, _ in
                guard let m = match, let url = m.url else { return }
                let nsStr = str as NSString
                if m.range.location > 0,
                   nsStr.character(at: m.range.location - 1) == 0x28 { return }
                // Don't auto-link inside hidden HTML comments
                if commentRanges.contains(where: {
                    NSLocationInRange(m.range.location, $0)
                }) { return }
                bareURLRanges.append(m.range)
                storage.addAttribute(.link, value: url, range: m.range)
                storage.addAttribute(.foregroundColor, value: palette.linkColor, range: m.range)
                storage.addAttribute(.underlineStyle,
                                     value: NSUnderlineStyle.single.rawValue, range: m.range)
            }
        }

        // 13. File-path coloring (DEC-001) and bracket-tag coloring.
        //     Skip inside fenced code blocks, frontmatter, comments, inline code,
        //     Markdown links (text + URL), and bare URLs already styled above.
        var inlineCodeRanges: [NSRange] = []
        enumerate(#"`([^`\n]+)`"#, in: str, range: range) { m in
            inlineCodeRanges.append(m.range)
        }

        let pathTagSkip: (NSRange) -> Bool = { r in
            if isInFenceOrFrontmatter(r) { return true }
            if commentRanges.contains(where: { NSIntersectionRange(r, $0).length > 0 }) { return true }
            if inlineCodeRanges.contains(where: { NSIntersectionRange(r, $0).length > 0 }) { return true }
            if mdLinkRanges.contains(where: { NSIntersectionRange(r, $0).length > 0 }) { return true }
            if bareURLRanges.contains(where: { NSIntersectionRange(r, $0).length > 0 }) { return true }
            return false
        }

        // File paths: (a) starts with ./ ../ ~/ or /, OR (b) ends with a generic
        // .ext pattern. Word-boundary anchored to avoid grabbing surrounding prose.
        let pathPattern =
            #"(?<![\w./~-])((?:\.{1,2}/|~/|/)[A-Za-z0-9_./~\-]+|[A-Za-z0-9_~][A-Za-z0-9_./~\-]*\.[A-Za-z0-9]{1,6})\b"#
        enumerate(pathPattern, in: str, range: range) { m in
            if pathTagSkip(m.range) { return }
            storage.addAttribute(.foregroundColor, value: palette.pathColor, range: m.range)
        }

        // Bracket-tags: [text] not followed by ( (which would be a Markdown link).
        enumerate(#"\[([^\]\n]+)\](?!\()"#, in: str, range: range) { m in
            if pathTagSkip(m.range) { return }
            let inner = m.range(at: 1)
            storage.addAttribute(.foregroundColor, value: palette.tagColor, range: inner)
        }
    }

    // MARK: - Tables

    private static func applyTables(to storage: NSTextStorage,
                                    str: String,
                                    range: NSRange,
                                    palette: ThemePalette,
                                    codeFont: NSFont,
                                    bodyFont: NSFont,
                                    skip: (NSRange) -> Bool) {
        let nsStr = str as NSString
        let separatorRE = try? NSRegularExpression(
            pattern: #"^[ \t]*\|?[ \t]*:?-{3,}:?(?:[ \t]*\|[ \t]*:?-{3,}:?)+[ \t]*\|?[ \t]*$"#)
        guard let separatorRE else { return }

        // Walk lines, find separator lines, then expand up (header) and down (body).
        var idx = range.location
        let end = NSMaxRange(range)
        while idx < end {
            let lineRange = nsStr.lineRange(for: NSRange(location: idx, length: 0))
            let lineStr = nsStr.substring(with: lineRange)
            let lineNoNewline = lineStr.trimmingCharacters(in: CharacterSet.newlines)
            let lineLen = (lineNoNewline as NSString).length
            let trimRange = NSRange(location: 0, length: lineLen)

            if separatorRE.firstMatch(in: lineNoNewline, range: trimRange) != nil {
                // Header is the line directly above; must contain at least one `|`
                let prevEnd = lineRange.location
                if prevEnd == 0 { idx = NSMaxRange(lineRange); continue }
                let headerLineRange = nsStr.lineRange(
                    for: NSRange(location: prevEnd - 1, length: 0)
                )
                let headerStr = nsStr.substring(with: headerLineRange)
                if !headerStr.contains("|") { idx = NSMaxRange(lineRange); continue }

                let tableStart = headerLineRange.location
                var tableEnd = NSMaxRange(lineRange)
                // Body lines: while next line still has a `|` and is not blank.
                var cursor = tableEnd
                while cursor < end {
                    let next = nsStr.lineRange(for: NSRange(location: cursor, length: 0))
                    let nextStr = nsStr.substring(with: next)
                        .trimmingCharacters(in: CharacterSet.newlines)
                    if nextStr.isEmpty || !nextStr.contains("|") { break }
                    tableEnd = NSMaxRange(next)
                    cursor = tableEnd
                }

                let tableRange = NSRange(location: tableStart, length: tableEnd - tableStart)
                if !skip(tableRange) {
                    styleTable(storage: storage,
                               nsStr: nsStr,
                               headerLineRange: headerLineRange,
                               separatorLineRange: lineRange,
                               tableRange: tableRange,
                               palette: palette,
                               codeFont: codeFont,
                               bodyFont: bodyFont)
                }

                idx = tableEnd
            } else {
                idx = NSMaxRange(lineRange)
                if lineRange.length == 0 { break }
            }
        }
    }

    private static func styleTable(storage: NSTextStorage,
                                   nsStr: NSString,
                                   headerLineRange: NSRange,
                                   separatorLineRange: NSRange,
                                   tableRange: NSRange,
                                   palette: ThemePalette,
                                   codeFont: NSFont,
                                   bodyFont: NSFont) {
        // Whole table: monospace + tinted background (matches code-block treatment).
        storage.addAttribute(.font, value: codeFont, range: tableRange)
        storage.addAttribute(.backgroundColor, value: palette.codeBackground, range: tableRange)

        // Header row: bold.
        let baseHeaderFont = (storage.attribute(.font,
                                                at: headerLineRange.location,
                                                effectiveRange: nil) as? NSFont) ?? codeFont
        let bold = NSFontManager.shared.convert(baseHeaderFont, toHaveTrait: .boldFontMask)
        storage.addAttribute(.font, value: bold, range: headerLineRange)

        // Separator row: collapse to a hairline so it doesn't visually clutter
        // the rendered table; column separators come from drawTablePipes.
        let para = NSMutableParagraphStyle()
        para.maximumLineHeight = 0.01
        para.minimumLineHeight = 0.01
        para.paragraphSpacing = 0
        para.paragraphSpacingBefore = 0
        storage.addAttribute(.paragraphStyle, value: para, range: separatorLineRange)
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: separatorLineRange)
        let charWidth = ("M" as NSString).size(withAttributes: [.font: codeFont]).width
        storage.addAttribute(.kern, value: NSNumber(value: -Double(charWidth)),
                             range: separatorLineRange)

        // Mark every `|` in the table (other than the separator row) as a pipe.
        // Hide the glyph and stash a draw flag so drawTablePipes can render a
        // 1pt vertical line through each pipe's bounding rect — stacking them
        // forms continuous column separators.
        var i = tableRange.location
        let end = NSMaxRange(tableRange)
        while i < end {
            if NSLocationInRange(i, separatorLineRange) {
                i += 1
                continue
            }
            if nsStr.character(at: i) == 0x7C { // '|'
                let r = NSRange(location: i, length: 1)
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: r)
                storage.addAttribute(.mtdTablePipe, value: true, range: r)
                storage.addAttribute(.mtdTablePipeColor, value: palette.tableBorderColor, range: r)
            }
            i += 1
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

    fileprivate static func hideRange(_ storage: NSTextStorage, range: NSRange, in font: NSFont) {
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
                    ("⌘'", "Add comment at cursor"),
                    ("⌘\\", "Toggle comments sidebar"),
                    ("⌘W", "Close window"),
                    ("⌘F", "Find in document"),
                ])

                section("Comments (v2)", rows: [
                    ("Format", "<!-- text --> in your file. Plain HTML comments."),
                    ("Add", "Cursor in line → inline. Selection → after / before."),
                    ("Sidebar", "Right side, ⌘\\ to toggle. Edit text directly."),
                    ("Margin icon", "Click to open sidebar focused on that comment."),
                    ("Code", "Comments inside ``` blocks are NOT hidden."),
                ])

                section("Editing tips", rows: [
                    ("Lists", "Enter continues -, *, +, or numbered. Empty marker exits."),
                    ("Markers", "**, *, ` chars hide when cursor is off the styled span."),
                    ("Links", "[text](url) or bare https://… and domain.com."),
                    ("Frontmatter", "Toolbar button inserts a YAML block at top."),
                ])

                section("Terminal", rows: [
                    ("open -a MarkThisDown notes.md", "Open file"),
                    ("alias mtd='open -a MarkThisDown'", "Add to ~/.zshrc"),
                ])
            }
            .padding(16)
        }
        .frame(maxHeight: 600)
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

// MARK: - Outline model

struct MTDHeading: Identifiable, Equatable {
    let id: Int        // line-start location, stable within a single parse cycle
    let level: Int     // 1...6
    let text: String
    let location: Int  // character offset of the heading line start
}

func parseHeadings(_ text: String) -> [MTDHeading] {
    let ns = text as NSString
    if ns.length == 0 { return [] }
    let fm = frontmatterRange(in: text)
    let fences = mtdFindFenceRangesForOutline(text)

    guard let re = try? NSRegularExpression(
        pattern: #"^(#{1,6})[ \t]+(.+?)[ \t]*#*[ \t]*$"#,
        options: [.anchorsMatchLines]
    ) else { return [] }

    let full = NSRange(location: 0, length: ns.length)
    var out: [MTDHeading] = []
    re.enumerateMatches(in: text, range: full) { m, _, _ in
        guard let m = m else { return }
        let loc = m.range.location
        if let fm = fm, NSLocationInRange(loc, fm) { return }
        if fences.contains(where: { NSLocationInRange(loc, $0) }) { return }
        let hashes = ns.substring(with: m.range(at: 1))
        var title = ns.substring(with: m.range(at: 2))
        // DEC-002: strip inline HTML comments (and any whitespace that
        // immediately precedes them) so they don't appear in the outline.
        if let stripRe = try? NSRegularExpression(
            pattern: #"[ \t]*<!--.*?-->"#,
            options: [.dotMatchesLineSeparators]
        ) {
            let r = NSRange(location: 0, length: (title as NSString).length)
            title = stripRe.stringByReplacingMatches(in: title, range: r, withTemplate: "")
        }
        title = title.trimmingCharacters(in: .whitespaces)
        out.append(MTDHeading(id: loc, level: hashes.count,
                              text: title, location: loc))
    }
    return out
}

fileprivate func mtdFindFenceRangesForOutline(_ text: String) -> [NSRange] {
    guard let re = try? NSRegularExpression(
        pattern: #"^```[\s\S]*?^```[ \t]*$"#,
        options: [.anchorsMatchLines]
    ) else { return [] }
    let ns = text as NSString
    let full = NSRange(location: 0, length: ns.length)
    var ranges: [NSRange] = []
    re.enumerateMatches(in: text, range: full) { m, _, _ in
        if let m = m { ranges.append(m.range) }
    }
    return ranges
}

// MARK: - Editor scroll bridge
//
// Lets ContentView capture and restore the editor's clipView origin around
// open/close of the outline panel (AC12.4). The MarkdownEditor wires the
// scroll view weakly into the bridge on makeNSView.

@MainActor
final class EditorScrollBridge: ObservableObject {
    weak var scrollView: NSScrollView?
    private var saved: NSPoint?

    func save() {
        guard let sv = scrollView else { return }
        saved = sv.contentView.bounds.origin
    }
    func restore() {
        guard let pt = saved, let sv = scrollView else { saved = nil; return }
        saved = nil
        sv.contentView.scroll(to: pt)
        sv.reflectScrolledClipView(sv.contentView)
    }
    func discard() { saved = nil }
}

// MARK: - Activity Bar (leading in-window vertical button strip)

struct ActivityBar: View {
    @Binding var showOutline: Bool
    let palette: ThemePalette
    let onToggleOutline: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onToggleOutline) {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(
                        showOutline
                            ? Color.accentColor
                            : Color(palette.secondaryColor)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(showOutline
                                  ? Color.accentColor.opacity(0.15)
                                  : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle outline (⌘⇧O)")
            Spacer()
        }
        .padding(.vertical, 10)
        .frame(width: 40)
        .frame(maxHeight: .infinity)
        .background(
            Color(palette.background)
                .overlay(Color.gray.opacity(palette.isDark ? 0.08 : 0.05))
        )
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(palette.isDark ? 0.25 : 0.15))
                .frame(width: 1),
            alignment: .trailing
        )
    }
}

// MARK: - Outline View

struct OutlineView: View {
    let headings: [MTDHeading]
    let palette: ThemePalette
    let onSelect: (MTDHeading) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Outline")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Close outline")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if headings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "number")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No headings yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(headings) { h in
                            OutlineRow(heading: h, palette: palette,
                                       onSelect: { onSelect(h) })
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(palette.background))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(palette.isDark ? 0.25 : 0.15))
                .frame(width: 1),
            alignment: .trailing
        )
    }
}

struct OutlineRow: View {
    let heading: MTDHeading
    let palette: ThemePalette
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                Text(heading.text)
                    .font(.system(
                        size: 12.5,
                        weight: heading.level <= 1 ? .semibold
                              : heading.level == 2 ? .medium
                              : .regular
                    ))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Color(palette.bodyColor))
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(heading.level - 1) * 12 + 10)
            .padding(.trailing, 10)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

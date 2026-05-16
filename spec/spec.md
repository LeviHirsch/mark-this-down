# markthisdown — Specification (iteration 1)

> Status: draft
> Revision: 3
> Prior iteration: brownfield — no prior iteration through this skill
> Last updated: 2026-05-10

## Motivation

Formalize the spec for an existing system and surface any code/spec drift. The project has shipped v2.0.12 with a working comment workflow but without a machine-readable spec; this iteration locks in the baseline and delivers the bug fixes and surface-coverage work needed to make the app reliable for daily use.

## Current state `[from-code]`

- **Entry point:** `MarkThisDownApp.swift:107` — `@main` DocumentGroup SwiftUI app; AppStorage for `theme` and `fontScale`; notification-driven commands for toggle/zoom/comment/sidebar (⌘E ⌘L ⌘= ⌘- ⌘0 ⌘' ⌘\\).
- **Document model:** `markthisdownDocument.swift:4-28` — `FileDocument` supporting `.md` (net.daringfireball.markdown) and plain-text read; UTF-8 write to `.md` only; autosave supplied by AppKit.
- **Core editor:** `ContentView.swift:96-298` — binds document text; `DisplayMode` (rendered/raw); `SaveState` enum; toolbar with 5+5 buttons; debounced 1.5s save-state transition.
- **Comment data model:** `ContentView.swift:26-92` — `MTDComment` struct; regex `<!--[\s\S]*?-->` excluding triple-backtick ranges; fields: id/range/body/lineNumber/contextLine (≤80 chars); reparsed on every `onChange` of `document.text` (currently runs twice per render — bug A2).
- **Comments sidebar:** `ContentView.swift:302-400` — right inspector 240–420pt, toggled ⌘\\; cards sorted by document position; search filter on body+contextLine (to be removed — bug A3); "+" button calls `triggerAddComment`; per-card delete.
- **Comment card UI:** `ContentView.swift:404-520` — editable body TextField 1–12 lines; delete button; context-line preview; accent-color highlight when focused; Enter commits, Shift/Cmd+Enter newlines, Esc reverts; auto-focus unreliable after ⌘' insertion (bug A4).
- **NSTextView subclass:** `ContentView.swift:524-896` — `ReadingTextView`; 760pt reading-width cap; basePadding 28pt + 44pt margin reserve; custom draw for HR/quote-bg/quote-bar/bullets/comment margin icons (22pt SF Symbol `text.bubble`, secondary-label tint, drawn outside text container clip).
- **Comment insertion:** `ContentView.swift:815-895` — `mtdInsertCommentAction`; empty selection mid-line → inline `<!--  -->`; empty selection on structural line (`#`/`-*/+`/`>`/`\d+\.`) → block-above with newline; selection without newline → inline after; selection with newline → block-above; cursor lands inside spaces at offset 5; posts `mtdCommentAdded`.
- **Margin click:** `ContentView.swift:586-655` — hit-tests right-margin band; falls back to first comment on failed hit-test (bug A5 — should no-op instead).
- **Syntax highlighter:** `ContentView.swift:1173-1459` — regex-based, cursor-aware; frontmatter (italic gray), fenced code (monospace + tinted bg), HR (hidden text + full-width line), blockquotes, bullets, headings h1–h6 (scale with zoom, markers hidden off-cursor), bold/italic/inline-code/links/bare URLs via NSDataDetector.
- **Comment hiding:** `ContentView.swift:1193-1217` — clear foreground + negative kern; standalone-line comments: paragraph line-height set to 0.01.
- **Scroll preservation:** `ContentView.swift:1114-1167` — saves/restores `clipView.bounds.origin` around full-storage `setAttributes` to prevent layout-invalidation scroll nudge.
- **Theme system:** `markthisdownApp.swift:5-102` — `ThemePalette` (10 colors, 3 fonts, heading-sizes array); `AppTheme` (system/light/dark); `.next` cycles; `.palette(systemIsDark:)` returns palette.
- **Info.plist:** CFBundleShortVersionString is "1.2" — stale; shipped version is 2.0.12 (bug A1).

## Change delta

### Added
- Tables rendering in `ReadingTextView` / SyntaxHighlighter.
- File-path and `[bracket-tag]` coloring in SyntaxHighlighter.
- Line numbers in raw mode — reserved left margin, wrap-aware.
- Outline view — left-side toggle panel showing document headings; saves and restores scroll position on toggle.
- Image paste: pasting an image inserts a Markdown image reference rather than embedding pixel data. Behavior varies by pasteboard source — see AC17 and open questions.
- `mtd` CLI tool: a bundled command-line tool; `mtd -n` opens a new blank document. Architecture and install mechanism TBD — see AC18 and open questions.

### Modified
- `Info.plist` CFBundleShortVersionString: "1.2" → "2.0.12". `[build-change-todo]`
- Comment parse: promote `comments` to `@State`, driven by a single `onChange` handler — eliminates double-parse-per-render. `[build-change-todo]`
- `CommentsSidebar`: remove search bar entirely. `[build-change-todo]`
- ⌘' insertion: fix auto-focus timing so new comment card receives keyboard focus reliably. `[build-change-todo]`
- `commentLocationForMarginIcon`: remove first-comment fallback; failed hit-test is a no-op. `[build-change-todo]`
- `ReadingTextView`: unified frontmatter toggle button (add / collapse / expand). `[build-change-todo]`
- Comment insertion: block ⌘' when cursor is inside frontmatter block. `[build-change-todo]`
- Sidebar card: clicking a card jumps the editor to the comment's location and scrolls it into view.

### Removed
- Sidebar comment search bar (filtered comment text only, not document content — useless in practice; in-document search deferred to D-001).

## Invariants `[must not change]`

- Comments are stored as plain `<!-- -->` HTML in the document body; no custom format, no companion files.
- Document extension is `.md` only; no `.mtd` or other custom extension.
- Document remains LLM-readable without custom tooling.
- Autosave is AppKit-supplied; the app does not implement a custom save path.
- Comment margin icons are visible in rendered mode alongside every comment.
- Existing comment insert / edit / delete UX is preserved: blur-commits edits, Esc reverts, Enter confirms, Shift/Cmd+Enter inserts newline.
- Raw mode shows plain comment text and continues to render margin icons.
- Comments inside triple-backtick fences are excluded from parsing, hiding, and icon-marking.
- Scroll position is preserved across `applyHighlighting` calls.
- Theme cycling (system/light/dark) and font-zoom (⌘= ⌘- ⌘0) continue to work.

## Provisional invariants

- **Comment parse is synchronous on every `document.text` change** (after single-parse fix): acceptable while document comment count stays well under ~500. Trigger: if lag is measurable at typical document sizes post-fix, re-evaluate as a `/spec decide` — see D-003.
- **Structural-line block-above insertion applies to list items**: current shipped behavior. Trigger: if D-004 is resolved in favor of inline-for-list-items, this invariant is superseded by the delta.

## Migration

None.

## Goal

Provide a local-first annotation layer on plain Markdown files that preserves full interoperability — comments as standard HTML, no companion files, no custom extensions, LLM-readable without tooling — while delivering the bug fixes and markdown surface coverage that make the app reliable for daily use.

## Constraints

- macOS only; SwiftUI + AppKit.
- `.md` files only; UTF-8.
- Comments as plain `<!-- -->`; no companion files; no custom sigils.
- No third-party rendering libraries — existing regex-based SyntaxHighlighter extended in-place.

## Success criteria

- All seven Phase A `[build-change-todo]` items are implemented and manually verified.
- Tables, file-path/bracket-tag coloring render correctly for common cases.
- Line numbers appear in raw mode and track correctly on wrapped lines.
- Outline view opens, lists headings, and scroll position is restored on close.
- Sidebar card click scrolls the editor to the comment's location.
- Comment insert/edit/delete/navigate workflow produces no data loss in normal use.
- Pasting an image (file-on-disk source) inserts a Markdown image reference; raw pixel data is never embedded.
- `mtd -n` from the terminal opens a new blank document.
- No previously-working behavior listed in Invariants is broken.

## Out of scope

- Threaded comments.
- `@`-sigil or `TODO:`/`CITE:`-prefix typed comments.
- Custom `.mtd` file extension.
- Brew tap or package distribution of the CLI (the bundled CLI tool itself is in scope; distribution via Homebrew is not).
- Git remote / cloud sync.
- In-document search (deferred — D-001).
- Code-block token-level syntax highlighting (not in scope; block-level monospace styling is existing behavior covered by AC14.4).
- Code-fence edge cases: indented fences, backticks in comment body, comment delimiters as literal code-block content (deferred — D-002).
- Comment parse debouncing beyond the single-parse fix (deferred — D-003).
- List item insertion semantics redesign (deferred — D-004).
- Raw-mode IDE enrichments beyond line numbers and current-line highlight (e.g. minimap, fold indicators, syntax-aware breadcrumbs) — deferred.

## Acceptance criteria (MECE)

### AC1. Info.plist version is correct `[delta]`
- AC1.1. `CFBundleShortVersionString` in `Info.plist` reads "2.0.12". `[delta]`
- AC1.2. Toolbar version label displays "v2.0.12 · <zoom>%". `[delta]`

### AC2. Comment parse runs once per text change `[delta]`
- AC2.1. `comments` is a `@State` variable updated by a single `onChange` handler on `document.text`. `[delta]`
- AC2.2. No duplicate parse occurs during a single `applyHighlighting` call cycle. `[delta]`

### AC3. Sidebar search bar is removed `[delta]`
- AC3.1. `CommentsSidebar` contains no search field or filter state. `[delta]`
- AC3.2. All comments are shown in position order with no filter applied. `[delta]`

### AC4. ⌘' auto-focus is reliable `[delta]`
- AC4.1. After ⌘' inserts a new comment with sidebar open, the new comment card's body field receives keyboard focus without requiring a manual click. `[delta]`
- AC4.2. After ⌘' with sidebar closed, sidebar opens and the new card receives focus. `[delta]`

### AC5. Margin icon hit-test: failed hit is a no-op `[delta]`
- AC5.1. Clicking the right-margin band where no comment icon is drawn produces no action (no sidebar open, no scroll, no selection change). `[delta]`
- AC5.2. Clicking the right-margin band at a line with a comment icon still opens the sidebar and scrolls to that comment. `[adopted]`

### AC6. Frontmatter toggle `[delta]`
- AC6.1. `ReadingTextView` shows a persistent toggle button whose label and action depend on document state. The button's visual form and placement are decided at implementation time. `[delta]`
- AC6.2. When no frontmatter block exists, the button reads "Add frontmatter"; activating it inserts a starter frontmatter block at the document top with placeholder `title:`, `date: <today>`, and `tags:` fields, and leaves it expanded. `[delta]`
- AC6.3. When a frontmatter block exists, the button reads "Collapse" or "Expand" depending on current collapse state. `[delta]`
- AC6.4. Activating "Collapse" hides the entire frontmatter block in rendered mode — opening `---` delimiter, content lines, and closing `---` delimiter all become invisible with no remaining row. The frontmatter remains present in `document.text` and is fully visible in raw mode regardless of collapse state. `[delta]`
- AC6.5. Activating "Expand" restores all frontmatter lines; collapse/expand state does not modify `document.text`. `[delta]`

### AC7. ⌘' blocked inside frontmatter `[delta]`
- AC7.1. With cursor inside a frontmatter block, ⌘' is a no-op (no comment inserted, no sidebar action). `[delta]`
- AC7.2. With cursor on the `---` delimiter line, behavior matches AC7.1 (treated as inside frontmatter). `[delta]`

### AC8. Sidebar card click jumps to comment `[delta]`
- AC8.1. Clicking a comment card in the sidebar scrolls the editor so the comment's location is visible. `[delta]`
- AC8.2. The editor cursor is moved to the comment location on card click. `[delta]`
- AC8.3. Jump works whether the comment is above or below the current viewport. `[delta]`

### AC9. Tables rendering `[delta]`
- AC9.1. A GFM pipe table (`| col | col |` with separator row) renders with visible column separators and header styling in rendered mode. `[delta]`
- AC9.2. Table source is hidden or styled in rendered mode consistent with other block elements. `[delta]`
- AC9.3. Raw mode shows the plain table source unchanged. `[adopted]`

### AC10. File-path and bracket-tag coloring `[delta]`
- AC10.1. Bare file paths are colored distinctly in rendered mode. A token is treated as a file path if it starts with `./`, `~/`, or `/`, or ends with a recognized file extension. The recognized extension list is defined via `/spec decide` before Phase 3 implementation. `[delta]`
- AC10.2. `[bracket-tag]` tokens are colored distinctly. A token is a bracket-tag if it matches `[text]` and is not immediately followed by `(` (which would make it a Markdown link). `[delta]`
- AC10.3. Coloring does not apply inside fenced code blocks or frontmatter. `[delta]`

### AC11. Line numbers in raw mode `[delta]`
- AC11.1. In raw mode, a reserved left margin displays line numbers for each logical line of the document. `[delta]`
- AC11.2. When a logical line wraps across multiple visual rows, only the first visual row is numbered; continuation rows show no number. `[delta]`
- AC11.3. Line numbers are not visible in rendered mode. `[delta]`
- AC11.4. The gutter's reserved width is preserved in rendered mode — the gutter itself is invisible, but the horizontal space it occupies remains, so toggling between raw and rendered modes does not horizontally reposition the document text. `[delta]`
- AC11.5. The gutter is positioned relative to the left edge of the text content area, not relative to the window or scroll-view edge; it sits immediately adjacent to the text. `[delta]`

### AC12. Outline view `[delta]`
- AC12.1. A toggle button opens/closes a left-side panel listing all ATX headings (`#`–`######`) in document order. The toggle mechanism and panel placement are decided at implementation time. `[delta]`
- AC12.2. Each outline entry shows heading level (indented) and text. `[delta]`
- AC12.3. Clicking an outline entry scrolls the editor to that heading and places the cursor at the start of the heading text (past the `#` markers and their separating whitespace). `[delta]`
- AC12.4. Opening the outline view saves the current scroll position; closing restores it. `[delta]`
- AC12.5. Outline list updates when headings are added, removed, or renamed. `[delta]`

### AC13. Core comment workflow is preserved `[adopted]`
- AC13.1. ⌘' on an empty mid-line selection inserts inline `<!--  -->` with cursor inside the spaces. `[adopted]`
- AC13.2. ⌘' on an empty selection on a structural line (heading `#{1,6} `, list item `[-*+] ` or `\d+\. `, blockquote `> `) follows a cursor-position-aware rule: if the cursor is in the marker zone (positions 0..N where N is the offset of the first text character past the marker and its separating whitespace), the comment is inserted at end-of-line with a leading space; otherwise the comment is inserted inline at the cursor position with a leading space if not already preceded by whitespace. `[delta]`
- AC13.3. ⌘' on a selection without a newline inserts inline comment after selection. `[adopted]`
- AC13.4. ⌘' on a selection containing a newline inserts a block-above comment. `[adopted]`
- AC13.5. Comment body edits commit on blur; Esc reverts; Enter confirms; Shift/Cmd+Enter inserts newline. `[adopted]`
- AC13.6. Per-card delete button removes the comment from document text. `[adopted]`

### AC14. Markdown rendering baseline is preserved `[adopted]`
- AC14.1. Headings h1–h6 render with correct relative sizes scaled by zoom factor; the `#` markers *and the whitespace separating them from the heading text* are hidden off-cursor. `[adopted]`
- AC14.2. Bold (`**...**`) and italic (`*...*` / `_..._`) render with markers hidden off-cursor. `[adopted]`
- AC14.3. Inline code renders with monospace font and tinted background; backtick markers hidden. `[adopted]`
- AC14.4. Fenced code blocks render with monospace font and tinted background; the triple-backtick delimiter lines are hidden off-cursor and reappear (in muted color) when the cursor is inside the fence. `[adopted]`
- AC14.5. Blockquotes render with 4% tint background and 3pt left bar; `>` marker hidden off-cursor. `[adopted]`
- AC14.6. HR renders as full-width 1pt line; source text hidden. `[adopted]`
- AC14.7. Unordered list bullets render as `•` in secondary color; `-`/`*`/`+` markers hidden. `[adopted]`
- AC14.8. Markdown links render with link text colored and URL muted. `[adopted]`
- AC14.9. Bare URLs are detected and colored via NSDataDetector. `[adopted]`
- AC14.10. Frontmatter block renders in italic gray. `[adopted]`

### AC15. Theme and zoom controls are preserved `[adopted]`
- AC15.1. ⌘E cycles theme (system → light → dark → system). `[adopted]`
- AC15.2. ⌘= / ⌘- adjust fontScale; ⌘0 resets to 1.0; double-click version label resets zoom. `[adopted]`
- AC15.3. Toolbar displays current version and zoom percentage. `[adopted]`

### AC16. Scroll preservation across highlight recompute `[adopted]`
- AC16.1. After any text change triggering `applyHighlighting`, the visible scroll position does not jump. `[adopted]`

### AC17. Image paste inserts a Markdown reference `[delta]`
- AC17.1. When the pasteboard contains a file URL pointing to an image file, paste inserts `![](path)` at the cursor, where `path` is the file URL's path. `[delta]`
- AC17.2. When the pasteboard contains only raw image data (screenshot, web copy — no file URL), the exact behavior (save-and-insert vs. no-op vs. placeholder) is resolved via `/spec decide` during implementation. `[delta]`
- AC17.3. Default NSTextView behavior of embedding raw image data into the text storage is suppressed in all cases. `[delta]`
- AC17.4. Whether the inserted path is absolute or relative to the document file is resolved via `/spec decide` during implementation. `[delta]`

### AC18. `mtd` CLI tool `[delta]`
- AC18.1. A command-line executable named `mtd` is bundled inside the app (e.g., `Contents/MacOS/mtd`). `[delta]`
- AC18.2. `mtd -n` opens a new blank `.md` document — launching the app if not running, or targeting the running instance if it is. `[delta]`
- AC18.3. The mechanism by which the CLI communicates with or activates the app (URL scheme, XPC, `open` with arguments, AppleScript, etc.) is resolved via `/spec decide` during implementation. `[delta]`
- AC18.4. The install mechanism (menu item that symlinks to `/usr/local/bin/mtd`, manual step in README, etc.) is resolved via `/spec decide` during implementation. `[delta]`
- AC18.5. Additional `mtd` subcommands beyond `-n` are out of scope for this iteration.

### AC19. Reader-first focus on document open `[delta]`
- AC19.1. When opening a document with non-trivial content, the editor scrolls to the top, the text view is NOT first responder, and no caret is visible. "Non-trivial content" = the document has at least one non-frontmatter, non-whitespace character. `[delta]`
- AC19.2. When opening an empty document, or a document whose only content is a frontmatter block, the text view IS first responder, with the caret placed at character offset 0 (empty case) or at the first character past the frontmatter closing delimiter (frontmatter-only case). `[delta]`
- AC19.3. Standard click-to-edit behavior is preserved: clicking on text content places the caret at the click point and makes the text view first responder. `[delta]`
- AC19.4. Programmatic cursor moves (outline jump per AC12.3, sidebar card jump per AC8.3, etc.) take first responder and place the caret at the target regardless of prior focus state. `[delta]`
- AC19.5. No in-session gesture is provided to return to the no-cursor reading state once the user has clicked into text; reading state applies only at document open. The user accepts standard NSTextView behavior thereafter. `[delta]`

### AC20. Scroll anchoring across mode and sidebar toggles `[delta]`
- AC20.1. Toggling between raw and rendered modes preserves the visual position of an anchor line: the line on screen before the toggle occupies approximately the same y-offset within the viewport after the toggle. `[delta]`
- AC20.2. Opening or closing the outline sidebar preserves the visual position of an anchor line using the same mechanism as AC20.1. `[delta]`
- AC20.3. The anchor is the cursor's logical line when the text view is first responder AND the cursor lies within the visible rect; otherwise the topmost visible logical line. `[delta]`
- AC20.4. Anchor capture is a discrete action triggered by the toggle (mode or sidebar); it is NOT a continuous watch that runs on every layout pass. `[delta]`
- AC20.5. Live window resize is NOT anchored; text reflow during a resize drag is acceptable. `[delta]`

### AC21. Raw-mode current-line highlight `[delta]`
- AC21.1. In raw mode, the logical line containing the caret renders with a tint band across the full text content width. Tint = body color at 4% alpha. `[delta]`
- AC21.2. In raw mode, the gutter row aligned with the caret's logical line renders with a matching tint band. `[delta]`
- AC21.3. In raw mode, the gutter label for the caret's logical line renders in bold. `[delta]`
- AC21.4. In rendered mode, no current-line highlight is shown (neither in the text body nor in the gutter). `[delta]`
- AC21.5. The current-line highlight is only active when the text view is first responder; when focus is elsewhere (per AC19) no highlight is shown. `[delta]`

## Implementation phases

### Phase 1. Bug fixes (Phase A build-change-todos)
**Delivers:** All seven known correctness bugs are resolved; the app is stable and behaves as documented.
**Unblocks:** Phases 2, 3, and 4 — establishes a correct rendering and comment foundation before extending it.
- AC1.1, AC1.2
- AC2.1, AC2.2
- AC3.1, AC3.2
- AC4.1, AC4.2
- AC5.1
- AC6.1, AC6.2, AC6.3, AC6.4, AC6.5
- AC7.1, AC7.2

### Phase 2. Comment navigation
**Delivers:** Sidebar cards navigate to their comment location in the editor.
**Depends on:** Phase 1 (stable comment state and sidebar baseline)
- AC8.1, AC8.2, AC8.3

### Phase 3. Markdown surface — tables, coloring, and line numbers
**Delivers:** Tables render visually; file paths and bracket-tags are colored; line numbers appear in raw mode with a current-line highlight.
**Depends on:** Phase 1 (correct syntax highlighter state post-bug-fixes)
**Note:** Resolve file-path extension allowlist via `/spec decide` before starting this phase.
- AC9.1, AC9.2
- AC10.1, AC10.2, AC10.3
- AC11.1, AC11.2, AC11.3, AC11.4, AC11.5
- AC21.1, AC21.2, AC21.3, AC21.4, AC21.5

### Phase 4. Outline view
**Delivers:** Left-panel outline listing headings; click-to-jump; scroll restore on close.
**Depends on:** Phase 1 (stable document state and scroll preservation)
- AC12.1, AC12.2, AC12.3, AC12.4, AC12.5

### Phase 5. Image paste
**Delivers:** Pasting an image inserts a Markdown reference instead of embedding pixel data.
**Depends on:** Phase 1 (stable NSTextView baseline)
**Note:** Two `/spec decide` questions must be resolved before implementation: raw-image-data behavior (AC17.2) and absolute vs. relative path (AC17.4).
- AC17.1, AC17.2, AC17.3, AC17.4

### Phase 6. `mtd` CLI tool
**Delivers:** Bundled CLI; `mtd -n` opens a new blank document.
**Depends on:** Phase 1 (app stability)
**Note:** Two `/spec decide` questions must be resolved before implementation: communication mechanism (AC18.3) and install mechanism (AC18.4).
- AC18.1, AC18.2, AC18.3, AC18.4, AC18.5

### Phase 7. Reader-first focus and scroll anchoring
**Delivers:** Documents open in a no-cursor reading state when they have content; empty and frontmatter-only documents open in an editing state with the caret in the right place; mode toggle and outline-sidebar toggle preserve the user's vertical position via a discrete line-anchor mechanism.
**Depends on:** Phase 3 (gutter and current-line behavior), Phase 4 (outline sidebar).
- AC19.1, AC19.2, AC19.3, AC19.4, AC19.5
- AC20.1, AC20.2, AC20.3, AC20.4, AC20.5

## Open questions

- **File-path extension allowlist (AC10.1):** Detection rule is defined (starts with `./`, `~/`, `/`, or ends with a recognized extension), but the recognized extension list must be defined via `/spec decide` before Phase 3 implementation begins.
- **Image paste — raw data behavior (AC17.2):** When the pasteboard has only pixel data (screenshot, web copy), what happens? Options: save image to `./images/` and insert path; insert a placeholder string; no-op. Resolve via `/spec decide` at Phase 5 start.
- **Image paste — path style (AC17.4):** When a file URL is available, should the inserted path be absolute or relative to the document's location? Resolve via `/spec decide` at Phase 5 start.
- **CLI communication mechanism (AC18.3):** How does `mtd -n` activate the running app? Options: custom URL scheme (`mtd://new`), XPC service, `open -a MarkThisDown --args -n` with `application(_:open:)`, AppleScript. Resolve via `/spec decide` at Phase 6 start.
- **CLI install mechanism (AC18.4):** How does `mtd` get onto the user's PATH? Options: "Install CLI Tool" menu item that symlinks `Contents/MacOS/mtd → /usr/local/bin/mtd`; manual README instruction; post-install script. Resolve via `/spec decide` at Phase 6 start.

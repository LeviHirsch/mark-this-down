# markthisdown — Specification (iteration 1)

> Status: draft
> Revision: 1
> Prior iteration: brownfield — no prior iteration through this skill
> Last updated: 2026-05-06

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
- Code-block syntax highlighting inside fenced regions.
- Outline view — left-side toggle panel showing document headings; saves and restores scroll position on toggle.

### Modified
- `Info.plist` CFBundleShortVersionString: "1.2" → "2.0.12". `[build-change-todo]`
- Comment parse: promote `comments` to `@State`, driven by a single `onChange` handler — eliminates double-parse-per-render. `[build-change-todo]`
- `CommentsSidebar`: remove search bar entirely. `[build-change-todo]`
- ⌘' insertion: fix auto-focus timing so new comment card receives keyboard focus reliably. `[build-change-todo]`
- `commentLocationForMarginIcon`: remove first-comment fallback; failed hit-test is a no-op. `[build-change-todo]`
- `ReadingTextView`: implement frontmatter collapse/expand toggle. `[build-change-todo]`
- Comment insertion: block ⌘' when cursor is inside frontmatter block. `[build-change-todo]`
- Sidebar card: clicking a card jumps the editor to the comment's location and scrolls it into view.

### Removed
- Sidebar comment search bar (useless filter; in-document search deferred to D-001).

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

Ship the bug fixes and full markdown surface coverage that make markthisdown a reliable, visually complete daily markdown editor with a snappy comment workflow.

## Constraints

- macOS only; SwiftUI + AppKit.
- `.md` files only; UTF-8.
- Comments as plain `<!-- -->`; no companion files; no custom sigils.
- No third-party rendering libraries — existing regex-based SyntaxHighlighter extended in-place.

## Success criteria

- All seven Phase A `[build-change-todo]` items are implemented and manually verified.
- Tables, file-path/bracket-tag coloring, and code-block syntax highlighting render correctly for common cases.
- Outline view opens, lists headings, and scroll position is restored on close.
- Sidebar card click scrolls the editor to the comment's location.
- Comment insert/edit/delete/navigate workflow produces no data loss in normal use.
- No previously-working behavior listed in Invariants is broken.

## Out of scope

- Threaded comments.
- `@`-sigil or `TODO:`/`CITE:`-prefix typed comments.
- Custom `.mtd` file extension.
- Brew tap or package distribution.
- Git remote / cloud sync.
- In-document search (deferred — D-001).
- Code-fence edge cases: indented fences, backticks in comment body, comment delimiters as literal code-block content (deferred — D-002).
- Comment parse debouncing beyond the single-parse fix (deferred — D-003).
- List item insertion semantics redesign (deferred — D-004).

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

### AC6. Frontmatter collapse/expand `[delta]`
- AC6.1. A document with a YAML frontmatter block (`---` … `---`) shows a collapse affordance in `ReadingTextView`. `[delta]`
- AC6.2. Activating collapse hides the frontmatter body lines; a single summary line (e.g., "frontmatter") remains visible. `[delta]`
- AC6.3. Activating expand restores all frontmatter lines. `[delta]`
- AC6.4. Collapse/expand state does not modify `document.text`. `[delta]`

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
- AC10.1. Bare file paths (containing `/` and a recognized extension or starting with `./` or `~/`) are colored distinctly in rendered mode. `[delta]`
- AC10.2. `[bracket-tag]` tokens (alphanumeric text wrapped in `[` `]` that are not Markdown link syntax) are colored distinctly. `[delta]`
- AC10.3. Coloring does not apply inside fenced code blocks or frontmatter. `[delta]`

### AC11. Code-block syntax highlighting `[delta]`
- AC11.1. Fenced code blocks with a recognized language tag (e.g., ` ```swift `, ` ```python `, ` ```js `) receive token-level coloring inside the block. `[delta]`
- AC11.2. Fenced code blocks with no language tag or an unrecognized tag render as plain monospace (current behavior preserved). `[adopted]`
- AC11.3. Highlighting does not alter the stored document text. `[delta]`

### AC12. Outline view `[delta]`
- AC12.1. A toggle button opens/closes a left-side panel listing all ATX headings (`#`–`######`) in document order. `[delta]`
- AC12.2. Each outline entry shows heading level (indented) and text. `[delta]`
- AC12.3. Clicking an outline entry scrolls the editor to that heading and moves the cursor to it. `[delta]`
- AC12.4. Opening the outline view saves the current scroll position; closing restores it. `[delta]`
- AC12.5. Outline list updates when headings are added, removed, or renamed. `[delta]`

### AC13. Core comment workflow is preserved `[adopted]`
- AC13.1. ⌘' on an empty mid-line selection inserts inline `<!--  -->` with cursor inside the spaces. `[adopted]`
- AC13.2. ⌘' on an empty structural-line selection inserts a block-above comment with a newline. `[adopted]`
- AC13.3. ⌘' on a selection without a newline inserts inline comment after selection. `[adopted]`
- AC13.4. ⌘' on a selection containing a newline inserts a block-above comment. `[adopted]`
- AC13.5. Comment body edits commit on blur; Esc reverts; Enter confirms; Shift/Cmd+Enter inserts newline. `[adopted]`
- AC13.6. Per-card delete button removes the comment from document text. `[adopted]`

### AC14. Markdown rendering baseline is preserved `[adopted]`
- AC14.1. Headings h1–h6 render with correct relative sizes scaled by zoom factor; `#` markers hidden off-cursor. `[adopted]`
- AC14.2. Bold (`**...**`) and italic (`*...*` / `_..._`) render with markers hidden off-cursor. `[adopted]`
- AC14.3. Inline code renders with monospace font and tinted background; backtick markers hidden. `[adopted]`
- AC14.4. Fenced code blocks render with monospace font and tinted background. `[adopted]`
- AC14.5. Blockquotes render with 4% tint background and 3pt left bar; `>` marker hidden off-cursor. `[adopted]`
- AC14.6. HR renders as full-width 1pt line; source text hidden. `[adopted]`
- AC14.7. Unordered list bullets render as `•` in secondary color; `-`/`*`/`+` markers hidden. `[adopted]`
- AC14.8. Markdown links render with link text colored and URL muted. `[adopted]`
- AC14.9. Bare URLs are detected and colored via NSDataDetector. `[adopted]`
- AC14.10. Frontmatter block renders in italic gray. `[adopted]`
- AC14.11. Standalone comment lines leave no blank space in rendered mode (line height 0.01). `[adopted]`

### AC15. Theme and zoom controls are preserved `[adopted]`
- AC15.1. ⌘E cycles theme (system → light → dark → system). `[adopted]`
- AC15.2. ⌘= / ⌘- adjust fontScale; ⌘0 resets to 1.0; double-click version label resets zoom. `[adopted]`
- AC15.3. Toolbar displays current version and zoom percentage. `[adopted]`

### AC16. Scroll preservation across highlight recompute `[adopted]`
- AC16.1. After any text change triggering `applyHighlighting`, the visible scroll position does not jump. `[adopted]`

## Implementation phases

### Phase 1. Bug fixes (Phase A build-change-todos)
**Delivers:** All seven known correctness bugs are resolved; the app is stable and behaves as documented.
**Unblocks:** Phase 2 (surface coverage) — establishes a correct rendering and comment foundation before extending it.
- AC1.1, AC1.2
- AC2.1, AC2.2
- AC3.1, AC3.2
- AC4.1, AC4.2
- AC5.1
- AC6.1, AC6.2, AC6.3, AC6.4
- AC7.1, AC7.2

### Phase 2. Comment navigation
**Delivers:** Sidebar cards navigate to their comment location in the editor.
**Depends on:** Phase 1 (stable comment state and sidebar baseline)
- AC8.1, AC8.2, AC8.3

### Phase 3. Markdown surface — tables and coloring
**Delivers:** Tables render visually; file paths and bracket-tags are colored; fenced code blocks highlight by language.
**Depends on:** Phase 1 (correct syntax highlighter state post-bug-fixes)
- AC9.1, AC9.2
- AC10.1, AC10.2, AC10.3
- AC11.1, AC11.3

### Phase 4. Outline view
**Delivers:** Left-panel outline listing headings; click-to-jump; scroll restore on close.
**Depends on:** Phase 1 (stable document state and scroll preservation), Phase 2 (navigation pattern established)
- AC12.1, AC12.2, AC12.3, AC12.4, AC12.5

## Open questions

- **Code-block syntax highlighting scope (AC11.1):** The interview confirmed this is in-scope but did not specify which languages to support or which highlighting engine to use. The constraint bans third-party renderers but is silent on a lightweight token-regex approach vs. a bundled grammar library. Needs a `/spec decide` before Phase 3 implementation begins.
- **File-path detection heuristic (AC10.1):** The interview did not define the regex or extension allowlist for "file path." Needs a `/spec decide` before Phase 3 implementation begins.
- **Bracket-tag exclusion from Markdown links (AC10.2):** `[text](url)` is a Markdown link; `[bracket-tag]` alone is a tag. The boundary rule needs to be stated precisely — especially for `[tag]` with no following `(`.
- **Outline view placement and toggle mechanism (AC12.1):** The interview noted "left toggle (button or side-panel, design deferred to implementation)." The exact UI needs to be decided before Phase 4.
- **Frontmatter collapse affordance (AC6.1):** The interview did not specify whether collapse is triggered by a button, a click on the `---` line, or a disclosure triangle. Implementation should decide and document.

# MarkThisDown — Dev Log

**Currently shipping**: `v2.0.12` at `~/Applications/MarkThisDown.app`.
Open via `open -a MarkThisDown` or the `mtd` alias.

Project layout:
- Active: `~/dev/mtd_mark-this-down/markthisdown/` (the live Xcode project)
- Archive of v1.3: `~/dev/mtd_mark-this-down/markthisdown-v1.3/`

## How to resume

1. `cd ~/dev/mtd_mark-this-down/markthisdown`
2. Open `markthisdown.xcodeproj` in Xcode (or just edit Swift files and run `./scripts/install.sh`)
3. To rebuild + install + lsregister + alias: `./scripts/install.sh --no-alias` (alias already set)
4. Toolbar in upper right shows the active version — bump `MARKETING_VERSION` in `markthisdown.xcodeproj/project.pbxproj` for each meaningful change so it's visible

## Architecture (one-screen recap)

Native macOS app, SwiftUI shell + AppKit text engine.

- **`MarkThisDownApp.swift`** — `@main`, `DocumentGroup`, theme + zoom AppStorage, `View` menu commands (⌘E, ⌘L, ⌘=, ⌘0, ⌘', ⌘\\)
- **`MarkdownDocument.swift`** — `FileDocument` reading/writing UTF-8 `.md`/plain text
- **`ContentView.swift`** — everything else:
  - `ContentView` — toolbar, sidebar, status indicator, frontmatter insert, comment dispatch
  - `CommentsSidebar` + `CommentCard` — list, search, edit-on-blur, delete
  - `MTDComment` — regex parser; skips ranges inside fenced code
  - `MarkdownEditor` (NSViewRepresentable) — wraps `ReadingTextView` in `NSScrollView`
  - `ReadingTextView` (`NSTextView` subclass) — reading-width margins, custom drawing for HR / quote bar / bullets / comment margin icons; `mouseDown` hit-tests right-margin band
  - `SyntaxHighlighter` — regex-based; runs on every `applyHighlighting` over the full storage; tags ranges with both standard and custom (`mtdHR`, `mtdComment`, etc.) attributes
  - `HelpView` — popover content

Drawing trick of note: NSTextView clips its own `draw(_:)` to the textContainer's interior. To paint in the right margin, save graphics state, call `NSBezierPath(rect: bounds).setClip()`, draw, restore. Lost a couple hours to this.

## Version log (latest first)

| Ver | Change |
|---|---|
| 2.0.12 | Preserve scroll position across `applyHighlighting` (typing no longer jumps the visible area) |
| 2.0.11 | Comment margin icon click → opens sidebar focused on that comment (had to override `hitTest`) |
| 2.0.10 | Bigger comment icons (22pt), wider hit-band |
| 2.0.9 | Comment icons actually render — clip-expansion in `draw(_:)` |
| 2.0.4–2.0.8 | Diagnostic builds chasing icon visibility |
| 2.0.3 | Enter commits comment, Shift/Cmd+Enter newline, Esc reverts; structural-line placement; standalone-line block comments collapse cleanly |
| 2.0.2 | Surgical text replacement (longest-common-prefix/suffix diff) — fixes scrolling, focus, dropped spaces, phantom `>`s during sidebar editing |
| 2.0.1 | Comment edit commit-on-blur; theme-tinted icon attempt |
| 2.0.0 | Comments sidebar (inspector), margin icons (initially broken), `⌘'` smart insert, `⌘\\` toggle. Code-fence exclusion at parse time |
| 1.3 | HTML comments hide in render; quote box with bar; real `•` bullets |
| 1.2 | Reading-width margins, full-width HR, font zoom (`⌘=`/`⌘-`/`⌘0`), version label in toolbar |
| 1.1 | Toolbar reorg, `View` menu, `NSDataDetector` bare URLs, blockquote indent, list hanging indent, auto-bullet, frontmatter button, larger window default |
| 1.0 | First shippable: live styled rendering, raw toggle, save dialog, multi-window, theme menu, app icon, install script |

## Current behavior summary

- **Open / save**: `open -a MarkThisDown notes.md`, ⌘S, ⌘N for new, multi-window
- **Render mode (default)**: live styling for headings, bold/italic/code, links (clickable), HR (full-width line), quotes (bar + bg), `•` bullets, frontmatter (gray), HTML comments hidden (line collapsed if standalone)
- **Raw mode** (⌘E): plain monospace, everything visible
- **Theme**: Follow System / Light / Dark, ⌘L cycles
- **Zoom**: ⌘=/⌘-/⌘0, persisted, range 60–250%
- **Reading width**: capped at 760pt, centered in any wider window
- **Auto-save** with status subtitle ("Auto-saved" / "Auto-saving…" / "Not yet saved")
- **Comments**: HTML `<!-- -->`. Three add paths (⌘', toolbar `text.bubble`, sidebar `+`). Selection-aware placement (inline / after / block-above). Margin icon next to commented lines; click → opens sidebar focused. Edit-on-blur with Enter/Esc semantics.

## Known issues / rough edges

- **Comment count parses on every keystroke**. Fine for hundreds of comments; would need debouncing for thousands.
- **Sidebar search field**: minimally useful; consider removing or making it actually scoped to "in-document search" later.
- **Comment edit body field doesn't auto-focus** reliably when a brand-new comment is created via ⌘'. Sometimes you need to click into the field once. Worth a focused pass.
- **Block comment standalone-line collapse**: works, but the cursor lands inside an invisible character range when ⌘' inserts in render mode. That's a viable design (commit-on-Enter is the workflow), but feels weird first time. Consider auto-flipping to raw or auto-opening sidebar for fresh inserts.
- **Tables**: not styled. Render as plain text with `|` characters visible.
- **Code-block syntax highlighting**: code blocks are tinted but not language-highlighted.
- **Frontmatter cannot be collapsed**.
- **Outline view**: not implemented.

## Next up (priority order)

1. **File-path and `[bracket-tag]` coloring in render** — small, fits the highlighter pipeline. Detect strings that look like file paths (contain `/` and a known extension, or match a path-ish regex) and `[anything]` tokens (excluding markdown link syntax). Color them with theme accent. Especially valuable for AI-generated docs that reference files.
2. **Click sidebar card → editor scrolls/jumps to that comment** — small, high-leverage. Use `NSTextView.scrollRangeToVisible`.
3. **Outline view** — list of headings in a left-side inspector or as a tab in the comments sidebar. Click → jump.
4. **Frontmatter collapse toggle** — needs custom paragraph-style trick to hide a range, with a chevron in the margin or a toolbar button.
5. **Tables** — design pass; choose between (a) styled-text only (color pipes, monospace cells) or (b) actual grid layout via `NSTextAttachment`.
6. **Code-block syntax highlighting** — pull in `Splash` or similar; only activate when fence has a language tag.
7. **Auto-focus the comment field for new ⌘'-inserts** — small UX polish.
8. **Theme catalog expansion** — restore GitHub / Retro Mono / add LaTeX / Solarized; design custom-theme JSON loading.
9. **First-character-of-comment autoscrolls sidebar to focus** — minor.

## Things considered and deferred / declined

- Editing comments in margin popover instead of sidebar — rejected. Sidebar-only is simpler and more discoverable.
- `@`-sigil for typed comments — declined. All HTML comments are first-class; future extension can use prefix conventions like `TODO:` / `CITE:` / `[author]:`.
- Custom `.mtd` file extension — declined. Plain `.md` with HTML comments preserves AI-readability and cross-tool compatibility.
- Brew tap distribution — discussed, not built. Personal tap is feasible (~30 min) once a GitHub repo exists. Notarization needs paid Apple Developer.
- Git remote — not pushed anywhere. Local only.

## Setup commands reference

```bash
# Rebuild + install (no alias change)
~/dev/mtd_mark-this-down/markthisdown/scripts/install.sh --no-alias

# Inspect
ls ~/Applications/MarkThisDown.app
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    ~/Applications/MarkThisDown.app/Contents/Info.plist

# Force-quit
killall markthisdown
```

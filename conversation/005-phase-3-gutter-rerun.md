# Phase 3 Gutter Rerun

Date: 2026-05-15 Participants: Levi, Claude (claude-opus-4-7)

---

## Levi — kickoff: implement AC11.4 and AC11.5

Implement the new work in phase 3 of spec/spec.md ("Markdown surface — tables, coloring, and line numbers") — specifically AC11.4 and AC11.5 only. The rest of phase 3 (AC9, AC10, AC11.1–11.3) is already implemented and committed; do not modify that work except as strictly required to satisfy the new ACs.

[Full task brief included: AC11.4 (gutter's reserved width preserved in rendered mode), AC11.5 (gutter positioned relative to text content area), out-of-scope phases, invariants to preserve, references to spec lines and code locations, and a directive to surface design choices for AC11.4 before writing code.]

---

## Claude — explore current ruler implementation

_Listed `markthisdown/` Swift files and the spec to orient. Read spec.md:155–214 for AC11/AC12 context, grepped ContentView.swift for `LineNumberRuler`/`ruler`/`gutter` references, and read the existing `LineNumberRulerView` class around line 1063._

Key findings:
- `LineNumberRulerView : NSRulerView` with `ruleThickness=44` sits at the scroll-view left wall.
- TextView has `textContainerInset.width = leftPad` (computed for centering; min 28pt, grows to center text within `maxReadingWidth=760` on wide windows).
- In raw mode: ruler at `[0, 44]`, then a `leftPad` gap, then text — AC11.5 violated.
- In rendered mode: `rulersVisible = false`, so the 44pt strip disappears and text shifts left — AC11.4 violated.

Surfaced two design choices via AskUserQuestion: which AC11.5 approach (custom subview, collapse leftPad, fat ruler) and which AC11.4 approach (keep gutter and skip labels vs. hide + compensate inset).

---

## Levi — uncertain on tradeoffs, wants to chat

"My instinct is option #1, but I'm not sure I understand the decision well enough." for AC11.5; for AC11.4 "I would like to chat about it."

---

## Claude — walked through tradeoffs in plain terms

Explained the AC11.5 layout problem with an ASCII diagram showing `[scroll-edge]──ruler(44)──leftPad gap──[text]──`. Walked through three options:
- **Option 1 (custom subview):** stop using NSRulerView, gutter slides with `leftPad`. ~80 lines of new code but cleanly matches AC11.5.
- **Option 2 (collapse leftPad):** force `leftPad = ruleThickness`. Breaks the reading-width centering UX.
- **Option 3 (fat ruler):** widen ruler to absorb leftPad. Doesn't really satisfy "immediately adjacent."

For AC11.4:
- **Option A (keep gutter, skip drawing):** width preservation is "free" — view's own width is single source of truth.
- **Option B (hide + compensate inset):** width preserved by accounting math; two places to keep in sync.

Recommended Option 1 + Option A.

---

## Levi — articulated own model of the design

Laid out a 6-point design:
1. Ruler glued to text content, not scroll edge.
2. Total [scroll-edge → text] space identical across raw/rendered.
3. Minimum [scroll-edge → text] = gutter width.
4. Layout: `[scroll-edge]──leftPad-space(≥0)──[gutter/ruler]──[text]`.
5. Labels right-justified with right-edge padding gap.
6. Width-by-digit-count: how should it adjust as line count grows?

"Is my thinking in line with your suggested combo?"

---

## Claude — confirmed alignment, surfaced width-vs-digits options

Confirmed the combo matches user's thinking. Explained that current `leftPad = max(28, slack/2)` becomes `leftPad = max(gutterWidth, slack/2)`, and detailed three options for digit-count behavior:
- (a) Fixed at 4 digits.
- (b) Dynamic, recomputed on every text change.
- (c) Dynamic but cheap — recompute only when crossing a power-of-10 boundary.

Recommended (a) for minimalism.

---

## Levi — asked about Xcode and overflow behavior

"For 6, what does xcode do? My inclination is actually (c). How would (a) handle something above 9999?"

---

## Claude — answered: Xcode does (c); recommend (c)

Xcode (and VS Code, Sublime) grow gutter dynamically as line count crosses digit boundaries — option (c). Explained how (a) would degrade above 9999 (negative x, labels overflow leftward into the empty band, ugly at narrow windows). Switched recommendation to (c) and noted the implementation is cheap: cache `digitCount`, recompute on `textDidChange`, only resize when value changes.

Going with **Option 1 + Option A + (c)**.

---

## Claude — implemented gutter refactor

_Read remaining context around `updateReadingMargins`, located `textContainerInset` / `lineFragmentPadding` setup, and confirmed `ThemePalette.lineNumberColor` exists in `markthisdownApp.swift`._

Implemented across `ContentView.swift`:
- Added `weak var gutter: LineNumberGutterView?` to `ReadingTextView` and updated `updateReadingMargins` to use `gutter?.gutterWidth` as the leftPad floor (replacing `basePadding` floor). Added `gutter?.syncFrame()` call after each layout pass.
- Replaced `LineNumberRulerView : NSRulerView` with a new `LineNumberGutterView : NSView`. Key methods: `syncFrame()` (positions itself in scroll-view coords at `clip.minX + leftPad - gutterWidth`), `updateWidth()` (sizes for `digitCount` of `8` digits), and `draw(_:)` (right-justified labels with `labelRightInset: 6` and `labelLeftInset: 4`).
- Added `digitCount: Int = 2` property on the gutter with `didSet` to recompute width and trigger re-layout.
- Updated `MarkdownEditor.makeNSView` to add the gutter via `scroll.addFloatingSubview(gutter, for: .vertical)` — the documented API for sticky overlays — instead of `scroll.verticalRulerView`.
- Wired `frameDidChangeNotification` on the scrollView to call `gutter?.syncFrame()`.
- Updated `updateNSView` to toggle `gutter.drawsLabels = (mode == .raw)` instead of `scroll.rulersVisible`.
- Added `Coordinator.updateGutterDigitsIfNeeded(for:)` — counts newlines in `tv.string`, derives `digits = max(2, floor(log10(lines)) + 1)`, only updates if changed.
- Called `updateGutterDigitsIfNeeded` from `textDidChange` and from initial `makeNSView` setup.
- Deferred initial `syncFrame` one runloop tick via `DispatchQueue.main.async` so contentView has real bounds.

---

## Claude — built successfully

_Ran `xcodebuild -scheme markthisdown -configuration Debug build`._

`** BUILD SUCCEEDED **`. AC11.4 + AC11.5 wired up. Then asked about adding current-line highlight as bonus work (Sublime style vs Xcode style).

---

## Levi — additional request: current-line highlight in raw mode

"As an additional thing with the gutter (may as well take care of right now), I would like to have some built-in line editing behavior for raw mode. So we could do what Sublime does (highlights just the gutter) or we could do what xcode does (light highlight on gutter and content line with line label bolded). What do you think?"

---

## Claude — recommended Xcode style

Reasoned that the biggest UX value of current-line highlighting is re-locating the cursor after looking away — gutter-only tint solves only half the problem. Full-line tint plus bold gutter label is more effective. Outlined implementation: tint band in `drawBackground`, bold attrs in gutter draw loop, invalidation via `textViewDidChangeSelection`.

Surfaced two questions: leave it off in rendered mode entirely? Tint strength = 4% body-color (matching blockquote)?

---

## Levi — confirmed both choices

"1-yes leave current-line highlight off entirely. 2-that works for me as a starter."

---

## Claude — implemented current-line highlight

_Located `drawBackground(in:)` at line 685 (already overridden for `drawQuoteBackgrounds`)._

Added to `ReadingTextView`:
- `currentLineHighlightEnabled: Bool`, `currentLineHighlightColor: NSColor`, `currentLineCharIndex: Int` properties.
- `drawCurrentLineHighlight(in:)` — looks up the fragment rect at `currentLineCharIndex`, paints a full-text-container-width band tinted with `currentLineHighlightColor`. Called from `drawBackground`.

Added to `LineNumberGutterView`:
- `currentLineNumber: Int` and `currentLineHighlightColor: NSColor` properties.
- In `draw(_:)`: when `lineNumber == currentLineNumber`, paint a tint band across the full gutter row before drawing the label; use bold attrs for that label (built via `NSFontManager.shared.convert(rulerFont, toHaveTrait: .boldFontMask)`).

Added to `Coordinator`:
- `syncCurrentLine(in:)` — recomputes 1-based line number from `selectedRange().location` by counting newlines; derives line-start char index via `lineRange(for:)`. Sets state on text view and gutter; raw mode only.
- Called from `textViewDidChangeSelection` and from `updateNSView`.

Wired `highlightTint = palette.bodyColor.withAlphaComponent(0.04)` in both `makeNSView` and `updateNSView`.

---

## Claude — second build succeeded

_Ran build again._

`** BUILD SUCCEEDED **` (one pre-existing warning about `Selector` syntax, unrelated). SourceKit diagnostics about `ThemePalette`/`AppTheme`/`MarkdownDocument` being out-of-scope are stale cross-file noise — the actual compiler resolves them fine.

---

## Claude — committed Phase 3 re-run work

_Staged ContentView.swift only (left untracked `conversation/003-*.md` and `conversation/004-*.md` alone — orchestrator scratch). Created commit `aa10dd4`: "Phase 3: AC11.4 + AC11.5 + raw-mode current-line highlight"._

---

## Levi — run mtd, rebuild for testing

`mtd` (CLI shim) returned no output. "Rebuild the app file so I can test."

---

## Claude — rebuilt and launched app

_xcodebuild + `open` on the built .app bundle._

Built and launched. Suggested user toggle modes and move cursor to verify behavior.

---

## Levi — questions on tunable knobs + raised vertical-displacement problem

"1) can you tell me the line where the 6pt margin between the line label and gutter edge is determined? 2) where would I set the bold behavior of the line labels"

Then introduced a new design problem: **vertical-placement jumps between modes.** Switching from rendered to raw on a doc with headings displaces the user's focal content significantly because rendered headings are ~2× body height. Brainstormed two approaches:
1. Match fonts between modes — but defeats the rendered-mode goal.
2. **View anchoring** — capture an anchor line on toggle; restore it to the same y-offset in the new mode. Leaning this way.

Also asked about reading vs editing UX: should clicking negative space null the cursor? Where does cursor start on document open?

---

## Claude — answered + worked through the anchoring problem

Answered: `labelRightInset: CGFloat = 6` at line 1140; bold is built at line 1227 via `NSFontManager.shared.convert(rulerFont, toHaveTrait: .boldFontMask)` used in `boldAttrs` (1228).

On vertical displacement: confirmed user's option 2 is right. Proposed mechanics:
- Capture anchor BEFORE mode toggle: `(anchorCharIndex, yOffsetWithinViewport)`.
- After layout, look up new fragment rect for `anchorCharIndex` and scroll so it sits at the captured y-offset.
- Anchor = cursor's char index if cursor is visible, else first visible line (derivable from `layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)`).
- This generalizes to sidebar open/close, and supersedes the same-y preservation only for mode toggle (in-mode `applyHighlighting` keeps existing AC16.1 behavior).

On cursor/focus: NSTextView always has a selection while it's first responder — "no cursor" can only be expressed as "not first responder." Proposed reader-first policy: existing doc opens with no FR + no caret; empty/frontmatter-only docs open with FR + caret at the right position; click on text places caret normally; click on margin resigns FR. Surfaced six sub-questions (a–f) about discoverability, find bar, click semantics, etc.

---

## Levi — clarified scope + diagnostic question about NSTextView selection

"When you say 'Identify the anchor before the mode toggle', you still intend for that to be determined as part of the script run by the button/command to toggle modes right?"

"A trigger for a similar problem is the re-wrapping that can happen when the text content window is resized when the comments sidebar is opened." — should apply same mechanism to sidebar open/close.

Confirmed: app is "reader first that you can also edit and comment on cleanly."

Asked diagnostic: "Let's say I open a document that has content and start typing... do those keystrokes register (even before the user has explicitly chosen a cursor location) and where in the document would the text be written?" Worried about heading clobber from cursor at offset 0. Asked what "empty range with location" means in NSTextView.

---

## Claude — answered NSTextView model + proposed full reader-first policy

Confirmed mode-toggle anchor is one-shot (capture in toggle action, consume in `updateNSView`). Sidebar toggle: same mechanism, discrete event. Window resize live drag: don't anchor — accept reflow.

Explained NSRange: `length=0` means caret position at `location`, not "no cursor." Typing inserts at `location`, replacing zero chars. So caret at offset 0 in a doc starting with `# Heading` and typing `x` produces `x# Heading` — heading clobbered.

The actual "no cursor" mechanic = text view is NOT first responder. Caret stops blinking, keystrokes don't reach the text view.

Proposed policy:
- **Open existing doc with content** → scroll to top, NOT first responder, no caret.
- **Open empty / frontmatter-only doc** → first responder, caret at offset 0 or just past frontmatter close.
- **Click on text** → standard (place caret, become FR).
- **Click on margin inside text view** → resign FR, return to reading.
- **Programmatic moves** (outline/comment jump) → take FR + place caret.

Anchor logic = cursor-if-FR-and-visible, else first visible line. Works for both cases.

Surfaced sub-questions a–f for ratification.

---

## Levi — ruled on sub-questions

- (a) Fine for resize behavior; don't add click-margin-to-reading (overcomplicates).
- (b) Obsolete.
- (c) Find bar not implemented yet, not important.
- (d) Obsolete.
- (e) Defer reading-mode UI indicator for later.
- (f) Yes, programmatic moves take FR.

---

## Claude — consolidated decisions + flagged gap

Recap: discrete triggers only (mode toggle, sidebar open/close); no live-resize anchoring. Reader-first focus rules locked in. Deferred items list.

**Gap surfaced:** with both margin-click and Esc deferred, there's no in-session gesture to return to no-cursor reading state once user clicks into text. Standard NSTextView behavior (you're editing until something else takes focus). Mild leak — if user scrolls away and types, NSTextView auto-scrolls to caret. Acceptable for v1, but worth flagging.

Recommended Esc-resigns-FR as cheap fix, but offered to defer.

---

## Levi — accept v1 limitation, draft the spec

"That gap is fine for now (no to the Esc idea). Other more important things. Yes please draft and get us back on track."

---

## Claude — drafted spec additions

_Read spec.md structure (motivation, current state, invariants, ACs, phases, open questions) and `decisions.log` format (DEC-001 through DEC-004 set the template)._

Made edits across `spec/spec.md` and `spec/decisions.log`:

**spec.md additions:**
- New AC group **AC19. Reader-first focus on document open** (5 sub-ACs covering existing-doc-no-caret, empty/frontmatter doc with caret, click-to-edit preserved, programmatic moves take FR, v1 no-return-gesture limitation).
- New AC group **AC20. Scroll anchoring across mode and sidebar toggles** (5 sub-ACs: mode toggle anchor, sidebar toggle anchor, anchor selection rule, discrete-action requirement, no-anchor-on-resize).
- New AC group **AC21. Raw-mode current-line highlight** (5 sub-ACs codifying the bonus work: body tint, gutter tint, bold label, off in rendered, off when not FR).
- **Phase 3** updated to include AC21.1–AC21.5.
- New **Phase 7. Reader-first focus and scroll anchoring** containing AC19 + AC20.
- **Out-of-scope** line narrowed: raw-mode IDE enrichments beyond line numbers AND current-line highlight (minimap, fold indicators, syntax breadcrumbs still deferred).

**decisions.log additions:**
- **DEC-005** — Reader-first focus policy on document open. Full rationale (NSTextView always has selection while FR; "no cursor" = not FR; reading-first framing), alternatives considered (always FR at 0, persisted caret, margin-click, Esc), related to AC19.
- **DEC-006** — Scroll anchoring on discrete mode and sidebar toggles. Full mechanism (token captured before toggle, consumed in updateNSView), rationale (raw/rendered line-height differences, headings ~2× body), alternatives (font matching, continuous anchor, anchor live resize, cursor-only anchor), related to AC20 + AC16.1.
- **DEC-007** — Raw-mode current-line highlight rendering. 4% tint matching blockquote intensity, Xcode-style dual tint + bold, alternatives considered (Sublime gutter-only, stronger tint, apply in rendered), related to AC21.

---

## Claude — noticed user's swift edits, committed spec only

_Diff revealed unstaged tweaks: `labelRightInset: 6 → 12`, `boldAttrs → currentAttrs` rename, new `chosenLineNumberColor` palette field, dark-theme `lineNumberColor` experiment (changed to teal but commented out original)._

Staged spec files only. Created commit `53303c1`: "spec: AC19 reader-first focus, AC20 scroll anchoring, AC21 current-line highlight". Left user's swift edits unstaged for their decision.

---

## Levi — wire chosenLineNumberColor through

"12 font yes. and I couldn't figure out how to make the chosenLineNumberColor be the font color used for the line labels when that line is highlighted in raw mode. Can you help me with that?"

---

## Claude — wired chosenLineNumberColor

Three edits:
- Added `var chosenLineNumberColor: NSColor = .labelColor` property to `LineNumberGutterView`.
- Changed `currentAttrs` foreground from `lineNumberColor` to `chosenLineNumberColor` in the draw loop.
- Pushed `palette.chosenLineNumberColor` into the gutter in both `makeNSView` and `updateNSView`.

Build succeeded. Relaunched app.

---

## Levi — revert teal experiment

"Whoops. I didn't mean to keep the teal as the normal label color."

---

## Claude — reverted dark theme lineNumberColor

_Read context around the dark theme palette to locate the line._

Reverted dark theme's `lineNumberColor` from the calibratedRed/green/blue teal back to `NSColor(white: 0.50, alpha: 1)`. `chosenLineNumberColor: 0.80 white` (the brighter color for current line) stays.

---

## Levi — repackage app

"repackage app"

---

## Claude — rebuilt and relaunched

`** BUILD SUCCEEDED **`. Killed any running instance and `open`ed the built .app.

---

## Levi — what next?

"what next?"

---

## Claude — recommended committing tuning

Laid out state: two commits done (aa10dd4 code, 53303c1 spec), three uncommitted tuning improvements that match AC21. Recommended committing the tuning before handing back to orchestrator, then orchestrator runs `/spec implement` audit and `/spec verify`.

---

## Levi — commit

"commit"

---

## Claude — committed tuning

_Staged `ContentView.swift` + `markthisdownApp.swift`. Created commit `26ffe88`: "tune gutter: 12pt right inset + chosenLineNumberColor for current line"._

Phase 3 re-run complete. Ready for orchestrator re-audit and verify.

---

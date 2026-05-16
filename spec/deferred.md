# Deferred items

<!-- Items deferred from the spec interview/review process. Revisited at each iteration's interview triage. -->

---

## D-001 — In-document search

**Category:** feature
**Deferred since:** iteration 1
**Last touched:** iteration 1 (revised 2026-05-08)
**Defer count:** 1
**Description:** Replace the removed sidebar search bar with real in-document search (highlights matches in the main text view). Scope: must search document content, not just comment bodies — the comment-body-only filter was removed as useless. Flag for next iteration consideration.
**Source:** via /spec interview Phase A ambiguity 3 (iteration 1)

---

## D-002 — Code fence edge cases

**Category:** correctness
**Deferred since:** iteration 1
**Last touched:** iteration 1
**Defer count:** 1
**Description:** Three unspecified edge cases in triple-backtick fence exclusion: (1) indented fences, (2) backtick characters inside a comment body, (3) comment delimiters as literal content inside a code block teaching HTML syntax. Current rule: exclude everything inside triple-backtick fences.
**Source:** via /spec interview Phase A ambiguity 10 (iteration 1)

---

## D-003 — Comment parse debouncing

**Category:** performance
**Deferred since:** iteration 1
**Last touched:** iteration 1
**Defer count:** 1
**Description:** After promoting `comments` to `@State` (iteration 1 fix), investigate whether a debounce on the parse `onChange` handler is needed. Main lag source is likely `applyHighlighting`, not the parse. Add debounce only if lag persists post-fix.
**Source:** via /spec interview Phase A ambiguity 2 (iteration 1)

---

## D-005 — Comment anchoring metadata (relative-line tuple inside `<!-- -->`)

**Category:** feature
**Deferred since:** iteration 1
**Last touched:** iteration 1
**Defer count:** 1
**Description:** Embed a parsing-behavior notation at the end of each comment, immediately before the closing `-->`, that records the selection or anchor the comment applies to. Working format proposal: a 4-tuple `[startRelLine; startPos; endRelLine; endPos]` where the line components are relative to the comment's own position in the document (e.g., `0` = same line as the comment, `+1` = next line, `-2` = two lines above). The comment moves with the document as text shifts, so absolute line tracking is unnecessary — only within-line column drift remains as a smaller anchor-stability problem.

Optional fifth-and-later parameters (deferred-within-deferred): a stable hex ID (`a3f`, `2b1`, …) to serve as a comment identifier for cross-references and a positional counter (e.g., the Nth comment attached to the same anchor span) for ordering.

**Format details (tentative, non-binding):**
- Placement: end of the comment body, immediately before `-->`, separated by a space. E.g., `<!-- a note here [0;5;0;12] -->`. End-of-comment placement helps with comment-in-comment delimiting and keeps the human-readable comment text up front.
- Bracket choice: square brackets `[...]`. Markdown does not parse inside HTML comments, and `[...]` does not collide with Pandoc/Jekyll attribute braces or with `@`-sigil syntax (which is explicitly out-of-scope per spec.md:100). Bracket choice should be re-confirmed if a markdown-extension namespace ever uses `[...]` inside comments.

**Use-cases this enables (the consumer set):**
- Selection highlighting: hovering a comment card highlights the original selection in the editor.
- Click-to-jump precision: card click moves the cursor to the anchored selection, not just the comment's line.
- Stable comment identity across edits: hex ID survives even when the comment text is edited or moved.
- Cross-references: one comment can reference another by ID.
- Comment ordering at a shared anchor (the Nth-counter parameter).

**Open design questions (must resolve before implementation):**
- **Within-line drift handling.** Even with relative-line anchoring, `startPos` / `endPos` can stale when the user edits the anchored line. Options:
  - *Rebase on every keystroke* — diff the line on each `text` change and shift anchor offsets accordingly. Cheap but fragile around multi-line edits and undo.
  - *Best-effort approximation* — store positions, clamp to line bounds on resolve, accept occasional drift after large edits.
  - *Fuzzy/fingerprint-based* — store a short snippet of the anchored text and refind on each open. More robust but adds storage cost per comment.
- **Backwards compatibility.** Existing `<!-- ... -->` comments have no anchor tuple. Policy: treat absent tuples as "anchored to the comment's own line, no selection" — no migration write-back, no nag.
- **Edit-the-anchor UX.** When the user changes the selection a comment applies to, the tuple updates — but should the user ever see/edit the tuple text directly? Default proposal: hidden in the rendered comment-card view; surfaced in raw mode where the comment is plain text anyway.
- **Multi-line selection semantics.** `[0;5;+2;3]` means "from same-line col 5 to two-lines-down col 3." Confirm that this matches the user's mental model and that the parser tolerates `+`-prefixed positive offsets cleanly.
- **Hex-ID generation/uniqueness.** When is the ID minted (insert time? first edit?), how is uniqueness enforced, and does the ID survive copy-paste of a comment within the document?

**Why deferred:** Substantial feature with multiple sub-decisions; the anchor-drift fork in particular deserves a dedicated `/spec interview` rather than a single `/spec decide`. Belongs in a later iteration once iteration 1's stability+surface scope is closed.

**Source:** raised by user during iteration-1 post-verify hand-testing (2026-05-15).

---

## D-006 — Font parity between raw and rendered modes

**Category:** polish
**Deferred since:** iteration 1
**Last touched:** iteration 1
**Defer count:** 1
**Description:** Tighten visual similarity between raw and rendered modes so the document's text layout and spacing match more closely across the toggle. Current state: `rawBody` is 14pt monospaced; `renderedBody` is 15pt system. Goal: minimize the layout shift when toggling modes — text should occupy nearly the same area in both views. Open: pick one font family for both modes, OR align line heights/spacing explicitly, OR scale rendered body down to 14pt.
**Source:** via /spec reconcile bucket: defer (iteration 1) — raised by user during post-verify hand-testing.

---

## D-007 — Highlight comment icon when sidebar card is clicked

**Category:** feature
**Deferred since:** iteration 1
**Last touched:** iteration 1
**Defer count:** 1
**Description:** When a comment card in the sidebar is clicked (which already scrolls the editor to the comment per AC8), also visually highlight or color-shift the corresponding margin icon so the user can see which icon corresponds to the focused card. Pairs naturally with the inverse hover behavior (hovering an icon could highlight the corresponding card).
**Source:** via /spec reconcile bucket: defer (iteration 1) — raised by user during post-verify hand-testing.

---

## D-008 — Detect and surface multiple comments on the same line

**Category:** correctness
**Deferred since:** iteration 1
**Last touched:** iteration 1
**Defer count:** 1
**Description:** Currently when multiple comments live on the same line, the margin-icon rendering deduplicates by Y coordinate — only one icon is drawn. The app has no way to detect or indicate that multiple comments share a location. Needs design: stacked icon, badge with count, expandable cluster on hover, etc.
**Source:** via /spec reconcile bucket: defer (iteration 1) — raised by user during post-verify hand-testing.

---

## D-004 — List item comment insertion semantics — RESOLVED 2026-05-15

**Category:** design
**Deferred since:** iteration 1
**Resolved:** 2026-05-15 by DEC-002
**Resolution:** Comment placement on structural lines is now cursor-position-aware: marker-zone cursor → EOL insertion; text-zone cursor → inline at cursor. See `decisions.log` DEC-002.
**Original description:** Block-above insertion on list items may break list continuity (blank line mid-list ends the list in most renderers). Inline insertion may be preferable for list items. Needs a design decision: resolve as `/spec decide` during seed or implementation phase.
**Source:** via /spec interview Phase A ambiguity 6 (iteration 1)

---

## D-009 — True cell-based table rendering (proportional layout, padding, reflow)

**Category:** feature
**Deferred since:** iteration 1
**Last touched:** iteration 1 (2026-05-16)
**Defer count:** 0
**Description:** Replace the current attribute-overlay table rendering (monospace + drawn column/row rules over source text) with a true cell-based layout: per-cell padding, proportional column widths sized to content, body-font (non-monospace) text, and per-cell content reflow on wrap. Requires moving away from source-faithful character-position rendering — likely via NSTextAttachments, a custom table view embedded as an attachment, or a custom NSLayoutManager pass that consumes the pipe-table source and lays out cells independently. Affects AC9.3 (raw mode unchanged) only in that the underlying storage may need a parallel non-source rendering pass while keeping source intact for raw mode.
**Source:** via /spec defer (standalone, iteration 1 — ad-hoc table polish discussion 2026-05-16)

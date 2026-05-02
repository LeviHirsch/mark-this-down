# MarkThisDown v2 — Comments

## Goal

A right-side comments sidebar that surfaces every HTML comment in the document, plus margin icons next to commented lines, plus a smart "add comment" shortcut.

Storage stays plain markdown: `<!-- text here -->`. No proprietary format, no companion files, no metadata. An LLM reading the `.md` sees comments as text in context — that's the entire feature working as designed for AI workflows.

v1.3 archived at `~/dev/mtd_mark-this-down/markthisdown-v1.3/`. Active development continues in `~/dev/mtd_mark-this-down/markthisdown/`.

## Comment convention

Plain HTML comments. No sigil required. Multi-line supported.

```
<!-- a quick note -->
<!-- TODO: refactor this -->
<!-- multi-line
     comments work too -->
```

Future v2.1 may type-discriminate via prefix (`TODO:`, `CITE:`, `[author]:`) for filtering. Not in v2 scope.

## Adding a comment — three entry points

| Entry | Trigger |
|---|---|
| Keyboard | ⌘' |
| Toolbar | 💬 button (right group) |
| Sidebar | "+" button at top of sidebar |

All three call the same insertion logic.

## Insertion behavior (selection-aware)

| Selection state | Where the comment goes | Cursor lands |
|---|---|---|
| Empty, cursor mid-line | inline at cursor: `<!--  -->` | between `--` and ` -->` |
| Empty, cursor on blank/whitespace line | block on own line at cursor | inside the comment |
| Selection contains no `\n` | inline, immediately after selection's end | inside the comment |
| Selection spans `\n` (paragraph/block) | block on its own line **before** the selection | inside the comment |

In all cases the original selection is preserved (not deleted). The comment template is `<!--  -->` with one space inside on each side; cursor lands centered between the spaces.

## Sidebar

- **Toggle**: ⌘\ or toolbar button (collapsible side icon).
- **Default**: closed for all documents (regardless of comment count).
- **Position**: right side of editor; ~300pt wide; collapsible to 0.
- **Content**: list of cards, one per comment, sorted by document position.

Each card shows:
- Comment body (3-line truncation, click to expand)
- Surrounding context: 1-line preview of the line the comment is on or attached to
- Position label: "Line 42"
- Hover affordance: faint background highlight

Card interactions:
- **Click** → editor cursor jumps to the comment range; brief flash on the corresponding margin icon
- **Hover** → editor briefly highlights the comment's line
- **"…" menu** → Delete

Top of sidebar: "+" button (insert comment at current cursor) and a search field (filter comments by text content).

## Margin icon (always visible, independent of sidebar)

A small SF Symbol comment icon (`text.bubble`) drawn in the right margin next to any line containing a comment.

Interactions:
- **Click** → opens sidebar (if closed) and scrolls/focuses that comment's card
- Pure navigation; no popover, no inline edit affordance

## Editing

- **Sidebar (primary)**: each card has an editable text field that writes back to the document on every keystroke.
- **Raw mode**: comments are plain text — edit directly.

The sidebar is the "comments interface" — add, browse, edit, delete all happen there. Margin icon click opens-and-focuses the relevant card.

When ⌘' inserts a new comment, the sidebar auto-opens (if closed) and the new card is focused with its text field active, ready to type into.

## Deletion

- Margin icon popover → Delete button → removes the entire `<!-- ... -->` range.
- Sidebar card "…" menu → Delete.
- Manually deleting `<!-- -->` text in raw mode → comment vanishes from sidebar on next refresh.

## Anchoring

Anchored only by literal position. Comments are embedded in the document text; if surrounding text moves, the comment moves with it. No persistent IDs, no shadow store, no stable refs needed.

Sidebar reparses comments on every text change (debounced ~150ms for performance).

## Things to skip in render hiding

Comments inside fenced code blocks (` ``` … <!-- … --> … ``` `) must NOT be hidden — they're literal code, not annotations. The hiding rule will check whether the match falls inside a code-fence range and skip it.

## Implementation phases

1. **Comment detection & data model** — regex scan for `<!--[\s\S]*?-->`, build a `[Comment]` array (range, body, line). Ignore matches inside fenced code blocks.

2. **Sidebar UI** — SwiftUI right-side panel; toggle via `@State`. List of cards. No interactivity yet.

3. **Margin icon** — extend `ReadingTextView.draw` to paint the icon at right edge of commented lines. Use the same custom attribute pattern.

4. **Margin click + popover** — override `mouseDown(with:)` in ReadingTextView, hit-test against the icon's rect, present a popover anchored to that location.

5. **Add-comment shortcut & smart placement** — implement the selection-aware logic; bind ⌘' via `.commands`; add toolbar button.

6. **Edit / Delete** — wire up popover and sidebar card actions to mutate the document text.

7. **Sidebar interactions** — click-jump, hover-highlight, search filter.

8. **Code-fence exclusion** — make sure comments inside ``` blocks aren't hidden, listed, or icon-marked.

9. **Polish** — animation on jump, debounced sidebar refresh, keyboard nav (arrow keys to navigate cards).

## Out of scope (v2)

- Typed comments / filtering by type — v2.1
- Threaded discussions, replies — v3
- Stored authorship / timestamps — v3
- Resolving / archiving comments — v3
- Sidebar drag-resize — v2.1
- Cross-document comment search — n/a (single-doc app)

## Known limitations

- Multi-line block comments leave blank vertical space in rendered mode (we collapse line height but it's imperfect). Acceptable.
- A `<!-- -->` literal that the user intends as content (e.g. teaching markdown about HTML comments) will still be hidden. Workaround: escape with backticks (`` `<!-- -->` ``) or put inside a code block.
- Sidebar performance is fine for typical docs; very large notebooks (>500 comments) may want pagination. Defer until measured.

## Version

This work targets `MARKETING_VERSION = 2.0`. Bump in `.pbxproj` when first v2 code lands.

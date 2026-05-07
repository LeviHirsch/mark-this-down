# Deferred items

<!-- Items deferred from the spec interview/review process. Revisited at each iteration's interview triage. -->

---

## D-001 — In-document search

**Category:** feature
**Deferred since:** iteration 1
**Last touched:** iteration 1
**Defer count:** 1
**Description:** Replace or supplement the sidebar search bar with real in-document search (highlights matches in the main text view). The current comment-filter-only search was removed as useless. Full document search is desirable but not a core feature for iteration 1.
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

## D-004 — List item comment insertion semantics

**Category:** design
**Deferred since:** iteration 1
**Last touched:** iteration 1
**Defer count:** 1
**Description:** Block-above insertion on list items may break list continuity (blank line mid-list ends the list in most renderers). Inline insertion may be preferable for list items. Needs a design decision: resolve as `/spec decide` during seed or implementation phase.
**Source:** via /spec interview Phase A ambiguity 6 (iteration 1)

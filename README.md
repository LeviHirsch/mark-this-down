# Mark This Down

A small, fast, native macOS markdown editor. Opens any `.md` file from terminal or Finder, edits it in a live-styled view, toggles to raw on demand. Theme catalog, frontmatter helper, auto-bullets.

## What it does

- Edit markdown directly in the rendered view (not a preview pane).
- `⌘E` to flip between rendered and raw monospace.
- `⌘L` cycles through built-in themes (Follow System, Default Dark, Default Light, GitHub, Retro Mono).
- Auto-saves on edit. Status indicator under the title (`Auto-saved` / `Auto-saving…` / `Not yet saved`).
- Multi-window. ⌘N for a new untitled doc.
- Inline marker hiding: the `**`, `*`, `` ` `` characters are invisible until your cursor is on the styled span.
- Auto-continues `-`, `*`, `+`, and numbered (`1.` → `2.`) lists on Enter; empty marker line exits the list.
- Insert Frontmatter button — drops a `---\ntitle: …\ndate: …\ntags: []\n---` block at the top.
- Click any link (markdown `[text](url)` or bare `tryhaptic.com`) to open in your default browser.

## Install

The app lives at `~/Applications/Mark This Down.app`. To install / reinstall after pulling source updates:

```bash
cd ~/dev/mtd_mark-this-down/markthisdown
xcodebuild -project markthisdown.xcodeproj \
           -scheme markthisdown \
           -configuration Release \
           -destination 'platform=macOS' \
           clean build

killall markthisdown 2>/dev/null
rm -rf "$HOME/Applications/Mark This Down.app"
cp -R ~/Library/Developer/Xcode/DerivedData/markthisdown-*/Build/Products/Release/markthisdown.app \
      "$HOME/Applications/Mark This Down.app"

/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "$HOME/Applications/Mark This Down.app"
```

The `lsregister` line forces LaunchServices to re-read the bundle's `Info.plist` so `open -a` picks up changes immediately.

## Daily use from terminal

```bash
open -a "Mark This Down" notes.md       # open a file
open -a "Mark This Down"                # untitled window
open -a "Mark This Down" a.md b.md      # two windows

# optional alias — add to ~/.zshrc
alias mtd='open -a "Mark This Down"'
```

## Set as default `.md` opener in Finder

The app is *registered* as a `.md` handler but Finder will still open .md files in your prior default (TextEdit / VS Code / etc.). To switch:

1. In Finder, right-click any `.md` file → **Get Info**.
2. Under **Open with:** pick "Mark This Down".
3. Click **Change All…** to apply to every `.md` file system-wide.

## Toolbar

| Position | Button | Shortcut | Notes |
|---|---|---|---|
| Left | Save | ⌘S | Manual save (auto-save runs anyway) |
| Left | Raw / Rendered | ⌘E | Flips display mode |
| Left | Theme | ⌘L | Menu of themes; ⌘L cycles |
| Right | Insert Frontmatter | — | Skipped if doc already has frontmatter |
| Right | New | ⌘N | New untitled window |

## Project structure

```
markthisdown/                       # Xcode project root
├── markthisdown.xcodeproj/
└── markthisdown/
    ├── markthisdownApp.swift       # @main, themes, menu commands
    ├── markthisdownDocument.swift  # FileDocument (read/write .md)
    ├── ContentView.swift           # Toolbar, NSTextView wrapper, syntax highlighter
    ├── Info.plist                  # Bundle metadata, .md UTType handler
    └── Assets.xcassets/            # AppIcon, accent color
```

## Sharing with a friend

1. Build Release as above.
2. Zip the `.app`:
   ```
   cd ~/Applications && zip -r ~/Desktop/MarkThisDown.zip "Mark This Down.app"
   ```
3. Send them the zip.
4. They unzip and drag to **/Applications** (or `~/Applications`).
5. **First launch only**: right-click the app in Finder → **Open** → click **Open** in the Gatekeeper warning dialog. (We're unsigned because we don't have a paid Apple Developer account; this one-time bypass is normal.)
6. After that they can launch it like any app.

## Roadmap (future v2 work)

- Block-element marker hiding (`#`, ``` ``` ```, `>` markers also hide based on cursor).
- Frontmatter collapse/expand toggle.
- Custom user themes via `~/Library/Application Support/MarkThisDown/themes/*.json`.
- More built-in themes (LaTeX serif, Solarized, Sakura).
- Code-block syntax highlighting (Splash or tree-sitter).
- Tables — at minimum styled, ideally column-aligned.

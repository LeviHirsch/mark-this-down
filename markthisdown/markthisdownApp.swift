import SwiftUI

// MARK: - Theme

struct ThemePalette {
    let background: NSColor
    let bodyColor: NSColor
    let secondaryColor: NSColor
    let markerColor: NSColor
    let linkColor: NSColor
    let codeBackground: NSColor
    let codeFenceColor: NSColor
    let blockquoteBackground: NSColor
    let hrColor: NSColor
    let frontmatterColor: NSColor

    let renderedBodyFont: NSFont
    let rawBodyFont: NSFont
    let codeFont: NSFont
    let headingSizes: [CGFloat]   // h1...h6

    let isDark: Bool
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Follow System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    func palette(systemIsDark: Bool) -> ThemePalette {
        let dark: Bool
        switch self {
        case .system: dark = systemIsDark
        case .light:  dark = false
        case .dark:   dark = true
        }
        return dark ? Self.darkPalette : Self.lightPalette
    }

    var next: AppTheme {
        let all = AppTheme.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }

    private static let renderedBody = NSFont.systemFont(ofSize: 15, weight: .regular)
    private static let rawBody = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private static let codeFont = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
    private static let headingSizes: [CGFloat] = [28, 24, 20, 18, 16, 15]

    static let lightPalette = ThemePalette(
        background: NSColor.white,
        bodyColor: NSColor(white: 0.13, alpha: 1),
        secondaryColor: NSColor(white: 0.40, alpha: 1),
        markerColor: NSColor(white: 0.70, alpha: 1),
        linkColor: NSColor(calibratedRed: 0.0, green: 0.42, blue: 0.93, alpha: 1),
        codeBackground: NSColor(white: 0.0, alpha: 0.05),
        codeFenceColor: NSColor(white: 0.55, alpha: 1),
        blockquoteBackground: NSColor(white: 0.0, alpha: 0.04),
        hrColor: NSColor(white: 0.78, alpha: 1),
        frontmatterColor: NSColor(white: 0.50, alpha: 1),
        renderedBodyFont: renderedBody,
        rawBodyFont: rawBody,
        codeFont: codeFont,
        headingSizes: headingSizes,
        isDark: false
    )

    static let darkPalette = ThemePalette(
        background: NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.14, alpha: 1),
        bodyColor: NSColor(white: 0.92, alpha: 1),
        secondaryColor: NSColor(white: 0.65, alpha: 1),
        markerColor: NSColor(white: 0.45, alpha: 1),
        linkColor: NSColor(calibratedRed: 0.42, green: 0.74, blue: 1.0, alpha: 1),
        codeBackground: NSColor(white: 1.0, alpha: 0.06),
        codeFenceColor: NSColor(white: 0.55, alpha: 1),
        blockquoteBackground: NSColor(white: 1.0, alpha: 0.04),
        hrColor: NSColor(white: 0.40, alpha: 1),
        frontmatterColor: NSColor(white: 0.55, alpha: 1),
        renderedBodyFont: renderedBody,
        rawBodyFont: rawBody,
        codeFont: codeFont,
        headingSizes: headingSizes,
        isDark: true
    )
}

// MARK: - App

@main
struct MarkThisDownApp: App {
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.system.rawValue
    @AppStorage("fontScale") private var fontScale: Double = 1.0

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .system }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
                .preferredColorScheme(theme.preferredColorScheme)
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 820, height: 920)
        .commands {
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Toggle Raw / Rendered") {
                    NotificationCenter.default.post(name: .mtdToggleMode, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Cycle Theme") {
                    let current = AppTheme(rawValue: themeRaw) ?? .system
                    themeRaw = current.next.rawValue
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Insert Frontmatter") {
                    NotificationCenter.default.post(name: .mtdInsertFrontmatter, object: nil)
                }

                Divider()

                Button("Zoom In") {
                    fontScale = min(2.5, fontScale * 1.10)
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Zoom Out") {
                    fontScale = max(0.6, fontScale / 1.10)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    fontScale = 1.0
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Add Comment at Cursor") {
                    NSApp.sendAction(Selector(("mtdInsertCommentAction:")),
                                     to: nil, from: nil)
                }
                .keyboardShortcut("'", modifiers: .command)

                Button("Toggle Comments Sidebar") {
                    NotificationCenter.default.post(name: .mtdToggleSidebar, object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let mtdToggleMode = Notification.Name("mtdToggleMode")
    static let mtdInsertFrontmatter = Notification.Name("mtdInsertFrontmatter")
    static let mtdToggleSidebar = Notification.Name("mtdToggleSidebar")
    static let mtdCommentAdded = Notification.Name("mtdCommentAdded")
}

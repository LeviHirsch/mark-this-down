import SwiftUI

// MARK: - Theme palette

struct ThemePalette {
    let background: NSColor
    let bodyColor: NSColor
    let bodyFont: NSFont
    let headingSizes: [CGFloat]      // h1...h6
    let headingColor: NSColor
    let markerColor: NSColor
    let linkColor: NSColor
    let codeFont: NSFont
    let codeBackground: NSColor
    let codeFenceColor: NSColor
    let blockquoteColor: NSColor
    let blockquoteBackground: NSColor
    let hrColor: NSColor
    let frontmatterColor: NSColor
    let isDark: Bool
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case darkClassic
    case lightClassic
    case github
    case retroMono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:        return "Follow System"
        case .darkClassic:   return "Default Dark"
        case .lightClassic:  return "Default Light"
        case .github:        return "GitHub"
        case .retroMono:     return "Retro Mono"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:                        return nil
        case .darkClassic, .retroMono:       return .dark
        case .lightClassic, .github:         return .light
        }
    }

    func palette(systemIsDark: Bool) -> ThemePalette {
        switch self {
        case .system:
            return (systemIsDark ? AppTheme.darkClassic : AppTheme.lightClassic)
                .palette(systemIsDark: systemIsDark)

        case .darkClassic:
            return ThemePalette(
                background: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1),
                bodyColor: NSColor(white: 0.92, alpha: 1),
                bodyFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                headingSizes: [26, 22, 19, 17, 15, 14],
                headingColor: NSColor(white: 0.97, alpha: 1),
                markerColor: NSColor(white: 0.45, alpha: 1),
                linkColor: NSColor(calibratedRed: 0.42, green: 0.74, blue: 1.0, alpha: 1),
                codeFont: NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular),
                codeBackground: NSColor(white: 1.0, alpha: 0.07),
                codeFenceColor: NSColor(white: 0.55, alpha: 1),
                blockquoteColor: NSColor(white: 0.7, alpha: 1),
                blockquoteBackground: NSColor(white: 1.0, alpha: 0.05),
                hrColor: NSColor(white: 0.4, alpha: 1),
                frontmatterColor: NSColor(white: 0.55, alpha: 1),
                isDark: true
            )

        case .lightClassic:
            return ThemePalette(
                background: NSColor.white,
                bodyColor: NSColor(white: 0.13, alpha: 1),
                bodyFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                headingSizes: [26, 22, 19, 17, 15, 14],
                headingColor: NSColor.black,
                markerColor: NSColor(white: 0.65, alpha: 1),
                linkColor: NSColor(calibratedRed: 0.0, green: 0.42, blue: 0.93, alpha: 1),
                codeFont: NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular),
                codeBackground: NSColor(white: 0.0, alpha: 0.05),
                codeFenceColor: NSColor(white: 0.45, alpha: 1),
                blockquoteColor: NSColor(white: 0.35, alpha: 1),
                blockquoteBackground: NSColor(white: 0.0, alpha: 0.04),
                hrColor: NSColor(white: 0.7, alpha: 1),
                frontmatterColor: NSColor(white: 0.45, alpha: 1),
                isDark: false
            )

        case .github:
            return ThemePalette(
                background: NSColor.white,
                bodyColor: NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.14, alpha: 1),
                bodyFont: NSFont.systemFont(ofSize: 15, weight: .regular),
                headingSizes: [30, 24, 20, 17, 15, 13],
                headingColor: NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.12, alpha: 1),
                markerColor: NSColor(calibratedRed: 0.55, green: 0.6, blue: 0.66, alpha: 1),
                linkColor: NSColor(calibratedRed: 0.04, green: 0.36, blue: 0.79, alpha: 1),
                codeFont: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                codeBackground: NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.97, alpha: 1),
                codeFenceColor: NSColor(calibratedRed: 0.4, green: 0.45, blue: 0.5, alpha: 1),
                blockquoteColor: NSColor(calibratedRed: 0.42, green: 0.46, blue: 0.51, alpha: 1),
                blockquoteBackground: NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.97, alpha: 1),
                hrColor: NSColor(calibratedRed: 0.84, green: 0.86, blue: 0.89, alpha: 1),
                frontmatterColor: NSColor(calibratedRed: 0.4, green: 0.45, blue: 0.5, alpha: 1),
                isDark: false
            )

        case .retroMono:
            return ThemePalette(
                background: NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.05, alpha: 1),
                bodyColor: NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.4, alpha: 1),
                bodyFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                headingSizes: [22, 20, 18, 16, 15, 14],
                headingColor: NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.55, alpha: 1),
                markerColor: NSColor(calibratedRed: 0.55, green: 0.4, blue: 0.2, alpha: 1),
                linkColor: NSColor(calibratedRed: 0.6, green: 0.95, blue: 0.95, alpha: 1),
                codeFont: NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular),
                codeBackground: NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.4, alpha: 0.10),
                codeFenceColor: NSColor(calibratedRed: 0.6, green: 0.45, blue: 0.25, alpha: 1),
                blockquoteColor: NSColor(calibratedRed: 0.85, green: 0.65, blue: 0.3, alpha: 1),
                blockquoteBackground: NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.4, alpha: 0.07),
                hrColor: NSColor(calibratedRed: 0.55, green: 0.4, blue: 0.2, alpha: 1),
                frontmatterColor: NSColor(calibratedRed: 0.65, green: 0.5, blue: 0.25, alpha: 1),
                isDark: true
            )
        }
    }

    var next: AppTheme {
        let all = AppTheme.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}

// MARK: - App

@main
struct MarkThisDownApp: App {
    @AppStorage("appTheme") private var themeRaw: String = AppTheme.system.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .system
    }

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
            }
        }
    }
}

extension Notification.Name {
    static let mtdToggleMode = Notification.Name("mtdToggleMode")
    static let mtdInsertFrontmatter = Notification.Name("mtdInsertFrontmatter")
}

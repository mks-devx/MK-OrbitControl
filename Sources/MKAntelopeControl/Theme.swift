import SwiftUI

// MARK: - App Font

enum AppFont: String, CaseIterable, Identifiable {
    case system = "System"
    case mono = "SF Mono"
    case hack = "Hack"
    case firaCode = "Fira Code"
    case jetbrains = "JetBrains Mono"
    case dotMatrix = "DotMatrix"
    case menlo = "Menlo"
    case monaco = "Monaco"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dotMatrix: return "Dot Matrix"
        default: return rawValue
        }
    }

    private var familyName: String {
        switch self {
        case .system, .mono: return ""
        case .hack: return "Hack"
        case .firaCode: return "FiraCode-Regular"
        case .jetbrains: return "JetBrainsMono-Regular"
        case .dotMatrix: return "DotMatrix"
        case .menlo: return "Menlo"
        case .monaco: return "Monaco"
        }
    }

    private var boldFamilyName: String {
        switch self {
        case .system, .mono: return ""
        case .hack: return "Hack-Bold"
        case .firaCode: return "FiraCode-Bold"
        case .jetbrains: return "JetBrainsMono-Bold"
        case .dotMatrix: return "DotMatrix"
        case .menlo: return "Menlo-Bold"
        case .monaco: return "Monaco"
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system:
            return .system(size: size, weight: weight)
        case .mono:
            return .system(size: size, weight: weight, design: .monospaced)
        default:
            return Font.custom(weight == .bold ? boldFamilyName : familyName, size: size)
        }
    }

    func dbFont(size: CGFloat) -> Font {
        switch self {
        case .system:
            return .system(size: size, weight: .bold).monospacedDigit()
        case .mono:
            return .system(size: size, weight: .bold, design: .monospaced)
        default:
            return Font.custom(boldFamilyName, size: size)
        }
    }
}

// MARK: - Menu Bar Icon

enum MenuBarIcon: String, CaseIterable, Identifiable {
    case atom = "atom"
    case pulsar = "dot.radiowaves.right"
    case speaker = "speaker.wave.2.fill"
    case waveform = "waveform"
    case dial = "dial.low.fill"
    case headphones = "headphones"
    case antenna = "antenna.radiowaves.left.and.right"
    case bolt = "bolt.fill"
    case music = "music.note"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .atom: return "Atom"
        case .pulsar: return "Pulsar"
        case .speaker: return "Speaker"
        case .waveform: return "Waveform"
        case .dial: return "Dial"
        case .headphones: return "Headphones"
        case .antenna: return "Antenna"
        case .bolt: return "Bolt"
        case .music: return "Music"
        }
    }
}

// MARK: - Theme

struct AppTheme: Identifiable {
    let id: String
    let name: String
    let background: Color
    let backgroundOpacity: Double
    let useMaterial: Bool
    let accent: Color
    let knobOuter: Color
    let knobInner: [Color] // gradient
    let knobRing: Color
    let textPrimary: Color
    let textSecondary: Color
    let textDim: Color
    let meterGradient: [Color]
    let isDark: Bool
}

// MARK: - All Themes

let allThemes: [AppTheme] = [
    // Crimson (current default)
    AppTheme(
        id: "crimson", name: "Crimson",
        background: Color(red: 0.07, green: 0.07, blue: 0.09),
        backgroundOpacity: 0.7, useMaterial: true,
        accent: Color(red: 0.85, green: 0.15, blue: 0.15),
        knobOuter: Color.white.opacity(0.06),
        knobInner: [Color(red: 0.16, green: 0.16, blue: 0.18), Color(red: 0.09, green: 0.09, blue: 0.11)],
        knobRing: Color.white.opacity(0.08),
        textPrimary: .white, textSecondary: .white.opacity(0.8), textDim: .white.opacity(0.35),
        meterGradient: [Color(red: 0.1, green: 0.7, blue: 0.3), Color(red: 0.8, green: 0.7, blue: 0.1), Color(red: 0.9, green: 0.15, blue: 0.1)],
        isDark: true
    ),
    // Midnight
    AppTheme(
        id: "midnight", name: "Midnight",
        background: Color(red: 0.02, green: 0.02, blue: 0.04),
        backgroundOpacity: 0.9, useMaterial: false,
        accent: .white,
        knobOuter: Color.white.opacity(0.05),
        knobInner: [Color(red: 0.08, green: 0.08, blue: 0.10), Color(red: 0.03, green: 0.03, blue: 0.05)],
        knobRing: Color.white.opacity(0.06),
        textPrimary: .white, textSecondary: .white.opacity(0.7), textDim: .white.opacity(0.25),
        meterGradient: [.white.opacity(0.3), .white.opacity(0.5), .white],
        isDark: true
    ),
    // Antelope
    AppTheme(
        id: "amber", name: "Amber",
        background: Color(red: 0.10, green: 0.10, blue: 0.11),
        backgroundOpacity: 0.85, useMaterial: true,
        accent: Color(red: 0.9, green: 0.6, blue: 0.1),
        knobOuter: Color.white.opacity(0.07),
        knobInner: [Color(red: 0.15, green: 0.14, blue: 0.13), Color(red: 0.08, green: 0.08, blue: 0.07)],
        knobRing: Color(red: 0.9, green: 0.6, blue: 0.1).opacity(0.15),
        textPrimary: .white, textSecondary: Color(red: 0.9, green: 0.8, blue: 0.6), textDim: .white.opacity(0.3),
        meterGradient: [Color(red: 0.1, green: 0.7, blue: 0.3), Color(red: 0.9, green: 0.6, blue: 0.1), Color(red: 0.9, green: 0.15, blue: 0.1)],
        isDark: true
    ),
    // Cyber / Hacker
    AppTheme(
        id: "cyber", name: "Cyber",
        background: Color(red: 0.01, green: 0.03, blue: 0.01),
        backgroundOpacity: 0.9, useMaterial: false,
        accent: Color(red: 0.0, green: 0.95, blue: 0.3),
        knobOuter: Color(red: 0.0, green: 0.95, blue: 0.3).opacity(0.1),
        knobInner: [Color(red: 0.04, green: 0.06, blue: 0.04), Color(red: 0.01, green: 0.02, blue: 0.01)],
        knobRing: Color(red: 0.0, green: 0.95, blue: 0.3).opacity(0.12),
        textPrimary: Color(red: 0.0, green: 0.95, blue: 0.3), textSecondary: Color(red: 0.0, green: 0.7, blue: 0.2), textDim: Color(red: 0.0, green: 0.4, blue: 0.1),
        meterGradient: [Color(red: 0.0, green: 0.4, blue: 0.1), Color(red: 0.0, green: 0.8, blue: 0.2), Color(red: 0.0, green: 1.0, blue: 0.3)],
        isDark: true
    ),
    // Cobalt
    AppTheme(
        id: "cobalt", name: "Cobalt",
        background: Color(red: 0.05, green: 0.06, blue: 0.12),
        backgroundOpacity: 0.85, useMaterial: true,
        accent: Color(red: 0.3, green: 0.5, blue: 1.0),
        knobOuter: Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.08),
        knobInner: [Color(red: 0.10, green: 0.11, blue: 0.18), Color(red: 0.05, green: 0.05, blue: 0.10)],
        knobRing: Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.1),
        textPrimary: .white, textSecondary: Color(red: 0.6, green: 0.75, blue: 1.0), textDim: .white.opacity(0.3),
        meterGradient: [Color(red: 0.2, green: 0.4, blue: 0.8), Color(red: 0.4, green: 0.6, blue: 1.0), Color(red: 0.9, green: 0.2, blue: 0.2)],
        isDark: true
    ),
    // Purple Haze
    AppTheme(
        id: "purple", name: "Purple Haze",
        background: Color(red: 0.06, green: 0.03, blue: 0.10),
        backgroundOpacity: 0.85, useMaterial: true,
        accent: Color(red: 0.7, green: 0.3, blue: 1.0),
        knobOuter: Color(red: 0.7, green: 0.3, blue: 1.0).opacity(0.08),
        knobInner: [Color(red: 0.12, green: 0.08, blue: 0.16), Color(red: 0.05, green: 0.03, blue: 0.08)],
        knobRing: Color(red: 0.7, green: 0.3, blue: 1.0).opacity(0.12),
        textPrimary: .white, textSecondary: Color(red: 0.85, green: 0.7, blue: 1.0), textDim: .white.opacity(0.3),
        meterGradient: [Color(red: 0.4, green: 0.2, blue: 0.7), Color(red: 0.7, green: 0.3, blue: 1.0), Color(red: 1.0, green: 0.2, blue: 0.4)],
        isDark: true
    ),
    // Diablo — blood red on pure black
    AppTheme(
        id: "diablo", name: "Diablo",
        background: Color(red: 0.02, green: 0.0, blue: 0.0),
        backgroundOpacity: 0.95, useMaterial: false,
        accent: Color(red: 0.9, green: 0.05, blue: 0.05),
        knobOuter: Color(red: 0.9, green: 0.05, blue: 0.05).opacity(0.12),
        knobInner: [Color(red: 0.10, green: 0.02, blue: 0.02), Color(red: 0.03, green: 0.0, blue: 0.0)],
        knobRing: Color(red: 0.9, green: 0.05, blue: 0.05).opacity(0.15),
        textPrimary: Color(red: 1.0, green: 0.1, blue: 0.1), textSecondary: Color(red: 0.8, green: 0.08, blue: 0.08), textDim: Color(red: 0.4, green: 0.03, blue: 0.03),
        meterGradient: [Color(red: 0.3, green: 0.0, blue: 0.0), Color(red: 0.7, green: 0.0, blue: 0.0), Color(red: 1.0, green: 0.1, blue: 0.05)],
        isDark: true
    ),
    // Nova — warm white/gold on dark
    AppTheme(
        id: "nova", name: "Nova",
        background: Color(red: 0.06, green: 0.05, blue: 0.04),
        backgroundOpacity: 0.9, useMaterial: false,
        accent: Color(red: 1.0, green: 0.85, blue: 0.4),
        knobOuter: Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.08),
        knobInner: [Color(red: 0.12, green: 0.10, blue: 0.08), Color(red: 0.05, green: 0.04, blue: 0.03)],
        knobRing: Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.1),
        textPrimary: Color(red: 1.0, green: 0.95, blue: 0.8), textSecondary: Color(red: 0.9, green: 0.8, blue: 0.5), textDim: Color(red: 0.5, green: 0.4, blue: 0.2),
        meterGradient: [Color(red: 0.4, green: 0.3, blue: 0.1), Color(red: 0.8, green: 0.7, blue: 0.2), Color(red: 1.0, green: 0.4, blue: 0.1)],
        isDark: true
    ),
    // Aether — subtle silver/ice on deep dark
    AppTheme(
        id: "aether", name: "Aether",
        background: Color(red: 0.04, green: 0.05, blue: 0.07),
        backgroundOpacity: 0.9, useMaterial: true,
        accent: Color(red: 0.7, green: 0.8, blue: 0.9),
        knobOuter: Color(red: 0.7, green: 0.8, blue: 0.9).opacity(0.06),
        knobInner: [Color(red: 0.10, green: 0.11, blue: 0.14), Color(red: 0.04, green: 0.05, blue: 0.07)],
        knobRing: Color(red: 0.7, green: 0.8, blue: 0.9).opacity(0.08),
        textPrimary: Color(red: 0.85, green: 0.9, blue: 0.95), textSecondary: Color(red: 0.6, green: 0.7, blue: 0.8), textDim: Color(red: 0.3, green: 0.35, blue: 0.4),
        meterGradient: [Color(red: 0.3, green: 0.5, blue: 0.6), Color(red: 0.5, green: 0.7, blue: 0.8), Color(red: 0.9, green: 0.3, blue: 0.3)],
        isDark: true
    ),
    // Flux — teal/cyan on dark
    AppTheme(
        id: "flux", name: "Flux",
        background: Color(red: 0.03, green: 0.06, blue: 0.07),
        backgroundOpacity: 0.9, useMaterial: false,
        accent: Color(red: 0.0, green: 0.85, blue: 0.8),
        knobOuter: Color(red: 0.0, green: 0.85, blue: 0.8).opacity(0.08),
        knobInner: [Color(red: 0.06, green: 0.10, blue: 0.11), Color(red: 0.02, green: 0.04, blue: 0.05)],
        knobRing: Color(red: 0.0, green: 0.85, blue: 0.8).opacity(0.1),
        textPrimary: Color(red: 0.8, green: 1.0, blue: 0.98), textSecondary: Color(red: 0.4, green: 0.8, blue: 0.75), textDim: Color(red: 0.2, green: 0.4, blue: 0.38),
        meterGradient: [Color(red: 0.0, green: 0.4, blue: 0.4), Color(red: 0.0, green: 0.7, blue: 0.65), Color(red: 0.9, green: 0.2, blue: 0.2)],
        isDark: true
    ),
    // Nexus — pink/magenta on dark
    AppTheme(
        id: "nexus", name: "Nexus",
        background: Color(red: 0.05, green: 0.03, blue: 0.06),
        backgroundOpacity: 0.9, useMaterial: false,
        accent: Color(red: 1.0, green: 0.2, blue: 0.6),
        knobOuter: Color(red: 1.0, green: 0.2, blue: 0.6).opacity(0.1),
        knobInner: [Color(red: 0.12, green: 0.06, blue: 0.10), Color(red: 0.04, green: 0.02, blue: 0.04)],
        knobRing: Color(red: 1.0, green: 0.2, blue: 0.6).opacity(0.12),
        textPrimary: Color(red: 1.0, green: 0.8, blue: 0.9), textSecondary: Color(red: 0.9, green: 0.4, blue: 0.65), textDim: Color(red: 0.5, green: 0.2, blue: 0.35),
        meterGradient: [Color(red: 0.5, green: 0.1, blue: 0.3), Color(red: 0.9, green: 0.2, blue: 0.5), Color(red: 1.0, green: 0.3, blue: 0.3)],
        isDark: true
    ),
    // Light
    AppTheme(
        id: "light", name: "Light",
        background: Color(red: 0.95, green: 0.95, blue: 0.96),
        backgroundOpacity: 0.9, useMaterial: true,
        accent: Color(red: 0.85, green: 0.15, blue: 0.15),
        knobOuter: Color.black.opacity(0.08),
        knobInner: [Color(red: 0.92, green: 0.92, blue: 0.93), Color(red: 0.85, green: 0.85, blue: 0.86)],
        knobRing: Color.black.opacity(0.1),
        textPrimary: .black, textSecondary: Color.black.opacity(0.7), textDim: Color.black.opacity(0.3),
        meterGradient: [Color(red: 0.1, green: 0.7, blue: 0.3), Color(red: 0.8, green: 0.7, blue: 0.1), Color(red: 0.9, green: 0.15, blue: 0.1)],
        isDark: false
    ),
]

// MARK: - Theme Manager

class ThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme
    @Published var currentFont: AppFont
    @Published var currentIcon: MenuBarIcon

    private static let themeKey = "MKSelectedTheme"
    private static let fontKey = "MKSelectedFont"
    private static let iconKey = "MKSelectedIcon"

    init() {
        let savedThemeId = UserDefaults.standard.string(forKey: Self.themeKey) ?? "crimson"
        currentTheme = allThemes.first { $0.id == savedThemeId } ?? allThemes[0]

        let savedFontId = UserDefaults.standard.string(forKey: Self.fontKey) ?? "system"
        currentFont = AppFont(rawValue: savedFontId) ?? .system

        let savedIconId = UserDefaults.standard.string(forKey: Self.iconKey) ?? "atom"
        currentIcon = MenuBarIcon(rawValue: savedIconId) ?? .atom
    }

    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.id, forKey: Self.themeKey)
    }

    func setFont(_ font: AppFont) {
        currentFont = font
        UserDefaults.standard.set(font.rawValue, forKey: Self.fontKey)
    }

    func setIcon(_ icon: MenuBarIcon) {
        currentIcon = icon
        UserDefaults.standard.set(icon.rawValue, forKey: Self.iconKey)
    }
}

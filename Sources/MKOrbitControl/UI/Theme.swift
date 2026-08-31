import SwiftUI
import AppKit

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

    var isAvailable: Bool {
        switch self {
        case .system, .mono, .menlo, .monaco:
            return true
        default:
            return NSFont(name: familyName, size: 12) != nil
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
    let accent: Color
    let knobOuter: Color
    let knobRing: Color
    let textPrimary: Color
    let textSecondary: Color
    let textDim: Color
    let meterGradient: [Color]
    let isDark: Bool
}

enum InterfaceSurfaceStyle: String, CaseIterable, Identifiable, Hashable {
    case solid = "Solid"
    case translucent = "Translucent"
    case liquidGlass = "Liquid Glass"

    var id: String { rawValue }

    var isAvailable: Bool {
        switch self {
        case .solid, .translucent:
            return true
        case .liquidGlass:
            if #available(macOS 26.0, *) { return true }
            return false
        }
    }
}

// MARK: - All Themes

let allThemes: [AppTheme] = [
    // Crimson (current default)
    AppTheme(
        id: "crimson", name: "Crimson",
        background: Color(red: 0.07, green: 0.07, blue: 0.09),
        accent: Color(red: 0.85, green: 0.15, blue: 0.15),
        knobOuter: Color.white.opacity(0.06),
        knobRing: Color.white.opacity(0.08),
        textPrimary: .white, textSecondary: .white.opacity(0.84), textDim: .white.opacity(0.62),
        meterGradient: [Color(red: 0.1, green: 0.7, blue: 0.3), Color(red: 0.8, green: 0.7, blue: 0.1), Color(red: 0.9, green: 0.15, blue: 0.1)],
        isDark: true
    ),
    // Midnight
    AppTheme(
        id: "midnight", name: "Midnight",
        background: Color(red: 0.02, green: 0.02, blue: 0.04),
        accent: .white,
        knobOuter: Color.white.opacity(0.05),
        knobRing: Color.white.opacity(0.06),
        textPrimary: .white, textSecondary: .white.opacity(0.82), textDim: .white.opacity(0.60),
        meterGradient: [.white.opacity(0.3), .white.opacity(0.5), .white],
        isDark: true
    ),
    // Antelope
    AppTheme(
        id: "amber", name: "Amber",
        background: Color(red: 0.10, green: 0.10, blue: 0.11),
        accent: Color(red: 0.9, green: 0.6, blue: 0.1),
        knobOuter: Color.white.opacity(0.07),
        knobRing: Color(red: 0.9, green: 0.6, blue: 0.1).opacity(0.15),
        textPrimary: .white, textSecondary: Color(red: 0.95, green: 0.86, blue: 0.70), textDim: .white.opacity(0.62),
        meterGradient: [Color(red: 0.1, green: 0.7, blue: 0.3), Color(red: 0.9, green: 0.6, blue: 0.1), Color(red: 0.9, green: 0.15, blue: 0.1)],
        isDark: true
    ),
    // Cyber / Hacker
    AppTheme(
        id: "cyber", name: "Cyber",
        background: Color(red: 0.01, green: 0.03, blue: 0.01),
        accent: Color(red: 0.0, green: 0.95, blue: 0.3),
        knobOuter: Color(red: 0.0, green: 0.95, blue: 0.3).opacity(0.1),
        knobRing: Color(red: 0.0, green: 0.95, blue: 0.3).opacity(0.12),
        textPrimary: Color(red: 0.50, green: 1.0, blue: 0.66), textSecondary: Color(red: 0.38, green: 0.90, blue: 0.53), textDim: Color(red: 0.46, green: 0.74, blue: 0.53),
        meterGradient: [Color(red: 0.0, green: 0.4, blue: 0.1), Color(red: 0.0, green: 0.8, blue: 0.2), Color(red: 0.0, green: 1.0, blue: 0.3)],
        isDark: true
    ),
    // Cobalt
    AppTheme(
        id: "cobalt", name: "Cobalt",
        background: Color(red: 0.05, green: 0.06, blue: 0.12),
        accent: Color(red: 0.3, green: 0.5, blue: 1.0),
        knobOuter: Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.08),
        knobRing: Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.1),
        textPrimary: .white, textSecondary: Color(red: 0.72, green: 0.82, blue: 1.0), textDim: .white.opacity(0.62),
        meterGradient: [Color(red: 0.2, green: 0.4, blue: 0.8), Color(red: 0.4, green: 0.6, blue: 1.0), Color(red: 0.9, green: 0.2, blue: 0.2)],
        isDark: true
    ),
    // Purple Haze
    AppTheme(
        id: "purple", name: "Purple Haze",
        background: Color(red: 0.06, green: 0.03, blue: 0.10),
        accent: Color(red: 0.7, green: 0.3, blue: 1.0),
        knobOuter: Color(red: 0.7, green: 0.3, blue: 1.0).opacity(0.08),
        knobRing: Color(red: 0.7, green: 0.3, blue: 1.0).opacity(0.12),
        textPrimary: .white, textSecondary: Color(red: 0.90, green: 0.80, blue: 1.0), textDim: .white.opacity(0.62),
        meterGradient: [Color(red: 0.4, green: 0.2, blue: 0.7), Color(red: 0.7, green: 0.3, blue: 1.0), Color(red: 1.0, green: 0.2, blue: 0.4)],
        isDark: true
    ),
    // Diablo — blood red on pure black
    AppTheme(
        id: "diablo", name: "Diablo",
        background: Color(red: 0.02, green: 0.0, blue: 0.0),
        accent: Color(red: 0.9, green: 0.05, blue: 0.05),
        knobOuter: Color(red: 0.9, green: 0.05, blue: 0.05).opacity(0.12),
        knobRing: Color(red: 0.9, green: 0.05, blue: 0.05).opacity(0.15),
        textPrimary: Color(red: 1.0, green: 0.62, blue: 0.62), textSecondary: Color(red: 0.95, green: 0.48, blue: 0.48), textDim: Color(red: 0.78, green: 0.46, blue: 0.46),
        meterGradient: [Color(red: 0.3, green: 0.0, blue: 0.0), Color(red: 0.7, green: 0.0, blue: 0.0), Color(red: 1.0, green: 0.1, blue: 0.05)],
        isDark: true
    ),
    // Nova — warm white/gold on dark
    AppTheme(
        id: "nova", name: "Nova",
        background: Color(red: 0.06, green: 0.05, blue: 0.04),
        accent: Color(red: 1.0, green: 0.85, blue: 0.4),
        knobOuter: Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.08),
        knobRing: Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.1),
        textPrimary: Color(red: 1.0, green: 0.95, blue: 0.8), textSecondary: Color(red: 0.96, green: 0.87, blue: 0.62), textDim: Color(red: 0.72, green: 0.65, blue: 0.50),
        meterGradient: [Color(red: 0.4, green: 0.3, blue: 0.1), Color(red: 0.8, green: 0.7, blue: 0.2), Color(red: 1.0, green: 0.4, blue: 0.1)],
        isDark: true
    ),
    // Aether — subtle silver/ice on deep dark
    AppTheme(
        id: "aether", name: "Aether",
        background: Color(red: 0.04, green: 0.05, blue: 0.07),
        accent: Color(red: 0.7, green: 0.8, blue: 0.9),
        knobOuter: Color(red: 0.7, green: 0.8, blue: 0.9).opacity(0.06),
        knobRing: Color(red: 0.7, green: 0.8, blue: 0.9).opacity(0.08),
        textPrimary: Color(red: 0.90, green: 0.94, blue: 0.98), textSecondary: Color(red: 0.70, green: 0.79, blue: 0.88), textDim: Color(red: 0.55, green: 0.62, blue: 0.70),
        meterGradient: [Color(red: 0.3, green: 0.5, blue: 0.6), Color(red: 0.5, green: 0.7, blue: 0.8), Color(red: 0.9, green: 0.3, blue: 0.3)],
        isDark: true
    ),
    // Flux — teal/cyan on dark
    AppTheme(
        id: "flux", name: "Flux",
        background: Color(red: 0.03, green: 0.06, blue: 0.07),
        accent: Color(red: 0.0, green: 0.85, blue: 0.8),
        knobOuter: Color(red: 0.0, green: 0.85, blue: 0.8).opacity(0.08),
        knobRing: Color(red: 0.0, green: 0.85, blue: 0.8).opacity(0.1),
        textPrimary: Color(red: 0.84, green: 1.0, blue: 0.98), textSecondary: Color(red: 0.58, green: 0.88, blue: 0.84), textDim: Color(red: 0.50, green: 0.70, blue: 0.68),
        meterGradient: [Color(red: 0.0, green: 0.4, blue: 0.4), Color(red: 0.0, green: 0.7, blue: 0.65), Color(red: 0.9, green: 0.2, blue: 0.2)],
        isDark: true
    ),
    // Nexus — pink/magenta on dark
    AppTheme(
        id: "nexus", name: "Nexus",
        background: Color(red: 0.05, green: 0.03, blue: 0.06),
        accent: Color(red: 1.0, green: 0.2, blue: 0.6),
        knobOuter: Color(red: 1.0, green: 0.2, blue: 0.6).opacity(0.1),
        knobRing: Color(red: 1.0, green: 0.2, blue: 0.6).opacity(0.12),
        textPrimary: Color(red: 1.0, green: 0.84, blue: 0.92), textSecondary: Color(red: 0.96, green: 0.62, blue: 0.78), textDim: Color(red: 0.74, green: 0.52, blue: 0.64),
        meterGradient: [Color(red: 0.5, green: 0.1, blue: 0.3), Color(red: 0.9, green: 0.2, blue: 0.5), Color(red: 1.0, green: 0.3, blue: 0.3)],
        isDark: true
    ),
    // Light
    AppTheme(
        id: "light", name: "Light",
        background: Color(red: 0.95, green: 0.95, blue: 0.96),
        accent: Color(red: 0.85, green: 0.15, blue: 0.15),
        knobOuter: Color.black.opacity(0.08),
        knobRing: Color.black.opacity(0.1),
        textPrimary: Color(red: 0.04, green: 0.04, blue: 0.06), textSecondary: Color.black.opacity(0.78), textDim: Color.black.opacity(0.62),
        meterGradient: [Color(red: 0.1, green: 0.7, blue: 0.3), Color(red: 0.8, green: 0.7, blue: 0.1), Color(red: 0.9, green: 0.15, blue: 0.1)],
        isDark: false
    ),
]

// MARK: - Theme Manager

class ThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme
    @Published var currentFont: AppFont
    @Published var currentIcon: MenuBarIcon
    @Published var surfaceStyle: InterfaceSurfaceStyle
    @Published var backgroundTransparency: Double

    private static let themeKey = "MKSelectedTheme"
    private static let fontKey = "MKSelectedFont"
    private static let iconKey = "MKSelectedIcon"
    private static let surfaceStyleKey = "MKInterfaceSurfaceStyle"
    private static let backgroundTransparencyKey = "MKBackgroundTransparency"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedThemeId = defaults.string(forKey: Self.themeKey) ?? "crimson"
        currentTheme = allThemes.first { $0.id == savedThemeId } ?? allThemes[0]

        let savedFontId = defaults.string(forKey: Self.fontKey) ?? "system"
        let savedFont = AppFont(rawValue: savedFontId) ?? .system
        currentFont = savedFont.isAvailable ? savedFont : .system

        let savedIconId = defaults.string(forKey: Self.iconKey) ?? MenuBarIcon.dial.rawValue
        currentIcon = MenuBarIcon(rawValue: savedIconId) ?? .dial

        let defaultStyle: InterfaceSurfaceStyle
        if #available(macOS 26.0, *) {
            defaultStyle = .liquidGlass
        } else {
            defaultStyle = .translucent
        }
        let savedStyle = defaults.string(forKey: Self.surfaceStyleKey)
            .flatMap(InterfaceSurfaceStyle.init(rawValue:)) ?? defaultStyle
        surfaceStyle = savedStyle.isAvailable ? savedStyle : .translucent

        let savedTransparency = defaults.object(forKey: Self.backgroundTransparencyKey) as? Double
        backgroundTransparency = min(0.75, max(0, savedTransparency ?? 0.28))
    }

    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        defaults.set(theme.id, forKey: Self.themeKey)
    }

    func setFont(_ font: AppFont) {
        currentFont = font
        defaults.set(font.rawValue, forKey: Self.fontKey)
    }

    func setIcon(_ icon: MenuBarIcon) {
        currentIcon = icon
        defaults.set(icon.rawValue, forKey: Self.iconKey)
    }

    func setSurfaceStyle(_ style: InterfaceSurfaceStyle) {
        guard style.isAvailable else { return }
        surfaceStyle = style
        defaults.set(style.rawValue, forKey: Self.surfaceStyleKey)
    }

    func setBackgroundTransparency(_ transparency: Double) {
        backgroundTransparency = min(0.75, max(0, transparency))
        defaults.set(backgroundTransparency, forKey: Self.backgroundTransparencyKey)
    }
}

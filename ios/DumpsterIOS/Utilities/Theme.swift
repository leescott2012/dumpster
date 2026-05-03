import SwiftUI

/// Design tokens for the native UI. All colors are mode + system-color-scheme aware:
/// `dark` and `day` are user overrides; `system` follows the device's dark/light setting.
struct Theme {

    // MARK: - Primary Backgrounds

    static func bg(_ mode: ColorMode, _ cs: ColorScheme) -> Color {
        isDark(mode, cs) ? Color(hex: "#0A0A0A") : Color(hex: "#F0EBE0")
    }
    static func bg1(_ mode: ColorMode, _ cs: ColorScheme) -> Color {
        isDark(mode, cs) ? Color(hex: "#111111") : Color(hex: "#E8E2D5")
    }
    static func bg2(_ mode: ColorMode, _ cs: ColorScheme) -> Color {
        isDark(mode, cs) ? Color(hex: "#181818") : Color(hex: "#DFD8C8")
    }
    static func bg3(_ mode: ColorMode, _ cs: ColorScheme) -> Color {
        isDark(mode, cs) ? Color(hex: "#222222") : Color(hex: "#D4CCBA")
    }

    // MARK: - Borders

    static func border(_ mode: ColorMode, _ cs: ColorScheme) -> Color {
        isDark(mode, cs) ? Color(hex: "#1E1E1E") : Color(hex: "#C8BFA8")
    }
    static func border2(_ mode: ColorMode, _ cs: ColorScheme) -> Color {
        isDark(mode, cs) ? Color(hex: "#2A2A2A") : Color(hex: "#B8AE98")
    }

    // MARK: - Text

    static func text(_ mode: ColorMode, _ cs: ColorScheme) -> Color {
        isDark(mode, cs) ? Color(hex: "#E8E8E8") : Color(hex: "#1A1610")
    }
    static func text2(_ mode: ColorMode, _ cs: ColorScheme) -> Color {
        isDark(mode, cs) ? Color(hex: "#999999") : Color(hex: "#5A5040")
    }
    static func text3(_ mode: ColorMode, _ cs: ColorScheme) -> Color {
        isDark(mode, cs) ? Color(hex: "#555555") : Color(hex: "#8A7A60")
    }

    // MARK: - Accent Colors

    static let gold        = Color(hex: "#C8A96E")
    static let goldDim     = Color(hex: "#C8A96E").opacity(0.15)
    static let hujiOutline = Color.red
    static let starBadge   = Color(hex: "#C8A96E")
    static let removeText  = Color.red

    // MARK: - Helper

    static func isDark(_ mode: ColorMode, _ cs: ColorScheme) -> Bool {
        mode == .dark || (mode == .system && cs == .dark)
    }
}

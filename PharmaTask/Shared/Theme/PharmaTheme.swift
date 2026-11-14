import SwiftUI
import UIKit

/// Shared semantic tokens. SVG sources and Android-ready values are in DesignAssets.
public enum HopeTheme {
    public static let background = adaptive(0xF6F7F2, 0x101C19)
    public static let surface = adaptive(0xFFFFFF, 0x192925)
    public static let surfaceMuted = adaptive(0xEDF2EB, 0x233832)
    public static let ink = adaptive(0x173C32, 0xEDF4EE)
    public static let secondary = adaptive(0x5D7169, 0xB2C2B8)
    public static let border = adaptive(0xDFE8E0, 0x334C42)
    public static let accent = adaptive(0x216754, 0xA1DDBC)
    public static let onAccent = adaptive(0xFFFFFF, 0x153F32)
    public static let hero = Color(uiColor: uiColor(0x184F41))
    public static let onHero = Color(uiColor: uiColor(0xF6F5E9))
    public static let mint = Color(uiColor: uiColor(0xA8D8B5))
    public static let apricot = Color(uiColor: uiColor(0xEDC69A))
    public static let urgent = adaptive(0xA8473E, 0xFFB4A7)
    public static let urgentSurface = adaptive(0xFCECE7, 0x482D2A)
    public static let amber = adaptive(0x87591F, 0xF4CE8B)
    public static let amberSurface = adaptive(0xFFF1D8, 0x3C3526)
    public static let blue = adaptive(0x456B82, 0xB2D5E8)
    public static let blueSurface = adaptive(0xEBF2F6, 0x243640)
    public static let purple = adaptive(0x74608B, 0xD7BDEB)
    public static let purpleSurface = adaptive(0xF1ECF6, 0x342B40)

    public static let cardRadius: CGFloat = 24
    public static let controlRadius: CGFloat = 16
    public static let pageInset: CGFloat = 20

    public static func shiftColor(_ tag: String) -> Color {
        switch tag {
        case "amber": return amber
        case "rose": return urgent
        case "blue": return blue
        case "purple": return purple
        default: return accent
        }
    }

    public static func shiftSymbol(_ name: String) -> String {
        let name = name.lowercased()
        if name.contains("nghỉ") { return "leaf" }
        if name.contains("đêm") || name.contains("tối") { return "moon.stars" }
        if name.contains("chiều") { return "sun.haze" }
        if name.contains("gãy") { return "sun.max" }
        return "sunrise"
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in uiColor(traits.userInterfaceStyle == .dark ? dark : light) })
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    // Compatibility for the existing service-facing and widget components.
    public static let brandTeal = accent
    public static let brandTealLight = surfaceMuted
    public static let brandTealBorder = border
    public static let brandRose = urgent
    public static let brandRoseLight = urgentSurface
    public static let brandRoseBorder = border
    public static let brandAmber = amber
    public static let brandAmberLight = amberSurface
    public static let brandAmberBorder = border
    public static let brandBlue = blue
    public static let brandBlueLight = blueSurface
    public static let brandBlueBorder = border
    public static let brandPurple = purple
    public static let brandPurpleLight = purpleSurface
    public static let brandPurpleBorder = border
    public static let slate900 = ink
    public static let slate800 = ink
    public static let slate700 = ink
    public static let slate600 = secondary
    public static let slate500 = secondary
    public static let slate400 = secondary
    public static let slate200 = border
    public static let slate100 = surfaceMuted
    public static let slate50 = background
}

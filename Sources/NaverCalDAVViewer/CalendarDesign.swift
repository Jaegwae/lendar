import AppKit
import SwiftUI

enum CalendarDesign {
    static let calendarCanvas = adaptiveColor(
        light: NSColor.white,
        dark: NSColor(red: 0.045, green: 0.047, blue: 0.052, alpha: 1.0)
    )
    static let lightGray = adaptiveColor(
        light: NSColor(red: 0.945, green: 0.949, blue: 0.957, alpha: 1.0),
        dark: NSColor(red: 0.045, green: 0.047, blue: 0.052, alpha: 1.0)
    )
    static let nearBlack = Color.primary
    static let appleBlue = Color(red: 0.0, green: 0.443, blue: 0.890) // #0071e3
    static let linkBlue = adaptiveColor(
        light: NSColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 1.0),
        dark: NSColor(red: 0.40, green: 0.68, blue: 1.0, alpha: 1.0)
    )
    static let textSecondary = Color.secondary
    static let textTertiary = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.48),
        dark: NSColor.white.withAlphaComponent(0.46)
    )
    static let whiteSurface = adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.72),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    static let divider = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.075),
        dark: NSColor.white.withAlphaComponent(0.105)
    )
    static let glassHighlight = adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.72),
        dark: NSColor.white.withAlphaComponent(0.18)
    )
    static let glassTint = adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.34),
        dark: NSColor.white.withAlphaComponent(0.07)
    )
    static let glassHairline = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.055),
        dark: NSColor.white.withAlphaComponent(0.06)
    )
    static let selectedDayFill = adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.42),
        dark: NSColor(red: 0.10, green: 0.18, blue: 0.28, alpha: 0.78)
    )
    static let selectedDayShadow = adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.86),
        dark: NSColor(red: 0.0, green: 0.443, blue: 0.890, alpha: 0.34)
    )
    static let subtleRowFill = adaptiveColor(
        light: NSColor.white.withAlphaComponent(0.26),
        dark: NSColor.white.withAlphaComponent(0.055)
    )
    static let controlHoverOverlay = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.045),
        dark: NSColor.white.withAlphaComponent(0.10)
    )
    static let controlPressedOverlay = adaptiveColor(
        light: NSColor.black.withAlphaComponent(0.085),
        dark: NSColor.white.withAlphaComponent(0.16)
    )

    static let cardShadow = Color.black.opacity(0.12)

    static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }

    static func displayFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func textFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

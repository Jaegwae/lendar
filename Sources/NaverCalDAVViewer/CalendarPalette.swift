import AppKit
import SwiftUI

enum CalendarPalette {
    static let customColorPrefix = CalendarColorCatalog.customColorPrefix

    static let choices: [(name: String, color: Color)] = [
        ("Blue", Color(red: 0.15, green: 0.56, blue: 0.96)),
        ("Green", Color(red: 0.11, green: 0.72, blue: 0.41)),
        ("Orange", Color(red: 0.96, green: 0.49, blue: 0.18)),
        ("Pink", Color(red: 0.93, green: 0.28, blue: 0.43)),
        ("Purple", Color(red: 0.47, green: 0.35, blue: 0.93)),
        ("Yellow", Color(red: 0.94, green: 0.77, blue: 0.18)),
        ("Teal", Color(red: 0.02, green: 0.65, blue: 0.68)),
        ("Mint", Color(red: 0.00, green: 0.78, blue: 0.62)),
        ("Red", Color(red: 0.91, green: 0.20, blue: 0.20)),
        ("Indigo", Color(red: 0.22, green: 0.34, blue: 0.88)),
    ]

    static func color(for sourceName: String, code: String) -> Color {
        if code.hasPrefix(customColorPrefix) || ["0", "1", "2", "3", "4"].contains(code) {
            return color(from: CalendarColorCatalog.rgb(for: code))
        }

        let palette = choices.map(\.color)
        return palette[abs(sourceName.hashValue) % palette.count]
    }

    static func customCode(for color: Color) -> String {
        customColorPrefix + hex(for: color)
    }

    static func eventTint(for item: CalendarItem) -> Color {
        if item.isCompleted {
            return Color(red: 0.26, green: 0.28, blue: 0.32)
        }
        return color(for: item.sourceCalendar, code: item.sourceColorCode)
    }

    static func eventFill(for item: CalendarItem) -> Color {
        if item.isCompleted {
            return Color(red: 0.78, green: 0.80, blue: 0.84)
        }
        return color(for: item.sourceCalendar, code: item.sourceColorCode).opacity(0.18)
    }

    private static func color(from rgb: CalendarRGB) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private static func hex(for color: Color) -> String {
        #if os(macOS)
            let nsColor = NSColor(color)
            guard let rgb = nsColor.usingColorSpace(.sRGB) else {
                return "268FF5"
            }
            let red = Int(round(rgb.redComponent * 255))
            let green = Int(round(rgb.greenComponent * 255))
            let blue = Int(round(rgb.blueComponent * 255))
            return String(format: "%02X%02X%02X", red, green, blue)
        #else
            return "268FF5"
        #endif
    }
}

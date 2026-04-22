import Foundation
import SwiftUI
import AppKit

// Shared design system, date formatting, palette conversion, and icon animation
// helpers. Keep global UI constants here so future visual changes are centralized.
enum CalendarDesign {
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

    static let cardShadow = Color.black.opacity(0.12)

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
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

extension View {
    func calendarAnimatedIcon(
        rotation: Double = 0,
        scale: CGFloat = 1.10,
        yOffset: CGFloat = 0
    ) -> some View {
        modifier(CalendarAnimatedIconModifier(rotation: rotation, scale: scale, yOffset: yOffset))
    }

    func calendarHoverLift(scale: CGFloat = 1.06) -> some View {
        modifier(CalendarHoverLiftModifier(scale: scale))
    }

    @ViewBuilder
    func calendarGlassSurface(
        cornerRadius: CGFloat = 12,
        material: Material = .thinMaterial,
        tintOpacity: Double = 0.30,
        shadowOpacity: Double = 0.10
    ) -> some View {
        modifier(
            CalendarGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                material: material,
                tintOpacity: tintOpacity,
                shadowOpacity: shadowOpacity
            )
        )
    }
}

private struct CalendarGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let material: Material
    let tintOpacity: Double
    let shadowOpacity: Double

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Group {
            if #available(macOS 26.0, *), colorScheme == .light {
                content
                    .glassEffect(.regular, in: shape)
            } else {
                content
                    .background(material, in: shape)
                    .background(
                        shape.fill(CalendarDesign.glassTint.opacity(max(tintOpacity, 0.01) / 0.34))
                    )
                    .overlay(
                        shape.stroke(CalendarDesign.glassHighlight, lineWidth: 1)
                    )
                    .overlay(
                        shape.stroke(CalendarDesign.glassHairline, lineWidth: 1)
                    )
                    .clipShape(shape)
            }
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? shadowOpacity * 0.75 : shadowOpacity), radius: 24, x: 0, y: 12)
    }
}

private struct CalendarAnimatedIconModifier: ViewModifier {
    let rotation: Double
    let scale: CGFloat
    let yOffset: CGFloat

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? scale : 1)
            .rotationEffect(.degrees(isHovering ? rotation : 0))
            .offset(y: isHovering ? yOffset : 0)
            .animation(.snappy(duration: 0.22, extraBounce: 0.06), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

private struct CalendarHoverLiftModifier: ViewModifier {
    let scale: CGFloat

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? scale : 1)
            .animation(.snappy(duration: 0.20, extraBounce: 0.05), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

struct CalendarAnimatedIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.16, extraBounce: 0.04), value: configuration.isPressed)
    }
}

enum CalendarValueParser {
    static func parseDateValue(_ raw: String) -> (date: Date?, isAllDay: Bool) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return (nil, false)
        }

        let normalized = trimmed.uppercased()
        let calendarTimeZone = TimeZone.current
        let allDayFormats = ["yyyyMMdd"]
        for format in allDayFormats {
            let formatter = formatter(format: format, timeZone: calendarTimeZone)
            if let date = formatter.date(from: normalized) {
                return (date, true)
            }
        }

        // Naver CalDAV values are consumed as calendar wall-clock times in this app.
        // Some timed values arrive with a trailing "Z" even when they represent the
        // local Naver Calendar time, so keep them in the calendar timezone instead
        // of shifting them as UTC instants.
        let timedFormats = [
            ("yyyyMMdd'T'HHmmss'Z'", calendarTimeZone),
            ("yyyyMMdd'T'HHmm'Z'", calendarTimeZone),
            ("yyyyMMdd'T'HHmmss", calendarTimeZone),
            ("yyyyMMdd'T'HHmm", calendarTimeZone)
        ]

        for (format, timeZone) in timedFormats {
            let formatter = formatter(format: format, timeZone: timeZone)
            if let date = formatter.date(from: normalized) {
                return (date, false)
            }
        }

        return (nil, false)
    }

    private static func formatter(format: String, timeZone: TimeZone?) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}

enum CalendarFormatting {
    static let toolbarToday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter
    }()

    static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter
    }()

    static let dayHeader: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter
    }()

    static let dayNumber: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "d"
        return formatter
    }()

    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d"
        return formatter
    }()

    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter
    }()

    static let fullDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd a h:mm"
        return formatter
    }()

    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    static let filterDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. MM. dd"
        return formatter
    }()

    static let compactMonthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. M"
        return formatter
    }()

    static func eventTimeText(for item: CalendarItem) -> String {
        guard let startDate = item.startDate else {
            return item.startOrDue
        }
        if item.isAllDay {
            if let endDate = item.endDate,
               !Calendar.current.isDate(startDate, inSameDayAs: endDate) {
                return "\(monthDay.string(from: startDate)) - \(monthDay.string(from: endDate))"
            }
            return "종일"
        }
        if let endDate = item.endDate {
            return "\(timeOnly.string(from: startDate)) - \(timeOnly.string(from: endDate))"
        }
        return timeOnly.string(from: startDate)
    }

    static func detailedEventRangeText(for item: CalendarItem) -> String {
        guard let startDate = item.startDate else {
            return item.startOrDue
        }

        if item.isAllDay {
            if let endDate = item.displayEndDay, endDate != Calendar.current.startOfDay(for: startDate) {
                return "\(fullDate.string(from: startDate)) ~ \(fullDate.string(from: endDate))"
            }
            return "\(fullDate.string(from: startDate)) 종일"
        }

        if let endDate = item.endDate {
            return "\(fullDateTime.string(from: startDate)) ~ \(fullDateTime.string(from: endDate))"
        }

        return fullDateTime.string(from: startDate)
    }
}

enum CalendarPalette {
    static let customColorPrefix = "custom:"

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
        ("Indigo", Color(red: 0.22, green: 0.34, blue: 0.88))
    ]

    static func color(for sourceName: String, code: String) -> Color {
        if code.hasPrefix(customColorPrefix) {
            return color(hex: String(code.dropFirst(customColorPrefix.count)))
        }

        switch code {
        case "0":
            return Color(red: 0.15, green: 0.56, blue: 0.96)
        case "1":
            return Color(red: 0.11, green: 0.72, blue: 0.41)
        case "2":
            return Color(red: 0.96, green: 0.49, blue: 0.18)
        case "3":
            return Color(red: 0.93, green: 0.28, blue: 0.43)
        case "4":
            return Color(red: 0.47, green: 0.35, blue: 0.93)
        default:
            let palette: [Color] = [
                Color(red: 0.15, green: 0.56, blue: 0.96),
                Color(red: 0.11, green: 0.72, blue: 0.41),
                Color(red: 0.96, green: 0.49, blue: 0.18),
                Color(red: 0.93, green: 0.28, blue: 0.43),
                Color(red: 0.47, green: 0.35, blue: 0.93),
                Color(red: 0.94, green: 0.77, blue: 0.18)
            ]
            return palette[abs(sourceName.hashValue) % palette.count]
        }
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

    private static func color(hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return choices.first?.color ?? Color(red: 0.15, green: 0.56, blue: 0.96)
        }

        let red = Double((value >> 16) & 0xff) / 255.0
        let green = Double((value >> 8) & 0xff) / 255.0
        let blue = Double(value & 0xff) / 255.0
        return Color(red: red, green: green, blue: blue)
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

enum CalendarText {
    static let calendarSourceDelimiter = "||"

    static func cleanName(_ value: String) -> String {
        value.replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
    }

    static func calendarKey(source: String, calendar: String) -> String {
        "\(source)\(calendarSourceDelimiter)\(calendar)"
    }

    static func calendarSourceName(_ key: String) -> String {
        let parts = key.components(separatedBy: calendarSourceDelimiter)
        return cleanName(parts.count > 1 ? parts[0] : "caldav.calendar.naver.com")
    }

    static func calendarDisplayName(_ key: String) -> String {
        let parts = key.components(separatedBy: calendarSourceDelimiter)
        return cleanName(parts.count > 1 ? parts.dropFirst().joined(separator: calendarSourceDelimiter) : key)
    }
}

extension Notification.Name {
    static let openSyncSettings = Notification.Name("openSyncSettings")
}

import Foundation

struct CalendarRGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double
}

enum CalendarColorCatalog {
    static let customColorPrefix = "custom:"
    static let fallback = CalendarRGB(red: 0.15, green: 0.56, blue: 0.96)

    static func rgb(for code: String) -> CalendarRGB {
        if code.hasPrefix(customColorPrefix),
           let custom = rgb(hex: String(code.dropFirst(customColorPrefix.count)))
        {
            return custom
        }

        switch code {
        case "0":
            return fallback
        case "1":
            return CalendarRGB(red: 0.11, green: 0.72, blue: 0.41)
        case "2":
            return CalendarRGB(red: 0.96, green: 0.49, blue: 0.18)
        case "3":
            return CalendarRGB(red: 0.93, green: 0.28, blue: 0.43)
        case "4":
            return CalendarRGB(red: 0.47, green: 0.35, blue: 0.93)
        case "5":
            return CalendarRGB(red: 0.94, green: 0.73, blue: 0.16)
        case "6":
            return CalendarRGB(red: 0.0, green: 0.65, blue: 0.72)
        case "7":
            return CalendarRGB(red: 0.18, green: 0.74, blue: 0.64)
        case "8":
            return CalendarRGB(red: 0.93, green: 0.20, blue: 0.20)
        case "9":
            return CalendarRGB(red: 0.28, green: 0.39, blue: 0.95)
        default:
            return fallback
        }
    }

    static func rgb(hex: String) -> CalendarRGB? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }

        return CalendarRGB(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

import SwiftUI

/// Visual tokens for the widget extension.
///
/// Keep this file free of AppKit color bridging. WidgetKit Simulator has shown
/// instability around hosting-view teardown, so colors stay simple SwiftUI values.
enum WidgetDesign {
    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.92) : Color(red: 0.114, green: 0.114, blue: 0.122)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62)
    }

    static func eventText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.88) : Color(red: 0.13, green: 0.24, blue: 0.39)
    }

    static func eventCardBackground(_ scheme: ColorScheme, accent: Color) -> Color {
        if scheme == .dark {
            return accent.opacity(0.18)
        }
        return accent.opacity(0.10)
    }

    static func eventCardStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.clear : Color.black.opacity(0.055)
    }

    static func eventCardShadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.clear : Color.black.opacity(0.045)
    }

    static func surfaceFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.22) : Color.white.opacity(0.22)
    }

    static let textTertiary = Color.secondary
}

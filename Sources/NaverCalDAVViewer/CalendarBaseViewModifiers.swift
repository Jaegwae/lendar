import SwiftUI

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
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? shadowOpacity * 0.75 : shadowOpacity),
            radius: 24,
            x: 0,
            y: 12
        )
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
            .modifier(CalendarButtonFeedbackModifier(isPressed: configuration.isPressed))
    }
}

private struct CalendarButtonFeedbackModifier: ViewModifier {
    let isPressed: Bool

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.92 : (isHovering ? 1.025 : 1))
            .brightness(isPressed ? -0.035 : 0)
            .overlay {
                Capsule(style: .continuous)
                    .fill(feedbackOverlay)
                    .allowsHitTesting(false)
            }
            .animation(.snappy(duration: 0.16, extraBounce: 0.04), value: isPressed)
            .animation(.snappy(duration: 0.20, extraBounce: 0.04), value: isHovering)
            .onHover { isHovering = $0 }
    }

    private var feedbackOverlay: Color {
        if isPressed {
            return CalendarDesign.controlPressedOverlay
        }
        if isHovering {
            return CalendarDesign.controlHoverOverlay
        }
        return .clear
    }
}

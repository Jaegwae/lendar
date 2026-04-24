import SwiftUI

extension View {
    func calendarModalContainer() -> some View {
        calendarGlassSurface(cornerRadius: 16, material: .regularMaterial, tintOpacity: 0.28, shadowOpacity: 0.18)
    }

    func calendarModalSectionSurface() -> some View {
        calendarGlassSurface(cornerRadius: 12, material: .thinMaterial, tintOpacity: 0.18, shadowOpacity: 0.035)
    }

    func calendarInputSurface() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 9)
            .calendarGlassSurface(cornerRadius: 10, material: .ultraThinMaterial, tintOpacity: 0.26, shadowOpacity: 0.02)
    }

    func calendarHeaderButtonStyle() -> some View {
        buttonStyle(CalendarAnimatedIconButtonStyle())
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .background(CalendarDesign.subtleRowFill, in: Circle())
            .overlay(
                Circle()
                    .stroke(CalendarDesign.glassHairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
            .calendarHoverLift(scale: 1.04)
    }

    func calendarNavigationGlass(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.46))
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    func calendarNavigationSurface() -> some View {
        background(.regularMaterial)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(CalendarDesign.divider)
                    .frame(height: 1)
            }
    }

    func calendarTopChrome() -> some View {
        background(CalendarDesign.calendarCanvas)
    }
}

extension Color {
    static let calendarAppleBlue = CalendarDesign.appleBlue
}

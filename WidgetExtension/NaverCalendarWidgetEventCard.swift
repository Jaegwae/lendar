import SwiftUI

/// Single event row in the widget timeline.
///
/// The row deliberately receives a snapshot value, not a full CalendarItem, because
/// widgets should only render app-written data and must not know about sync/auth.
struct NaverCalendarWidgetEventCard: View {
    let item: WidgetEventSnapshot
    let compact: Bool
    let colorScheme: ColorScheme

    private var accent: Color {
        WidgetPalette.color(for: item.colorCode)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accent)
                .frame(width: 4, height: compact ? 27 : 31)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .tracking(-0.12)
                    .foregroundStyle(WidgetDesign.eventText(colorScheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(WidgetDateFormatting.dateRangeText(item))
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .tracking(-0.12)
                    .foregroundStyle(WidgetDesign.secondaryText(colorScheme))
                    .lineLimit(1)

                Text(WidgetDateFormatting.timeRangeText(item))
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .tracking(-0.08)
                    .foregroundStyle(WidgetDesign.secondaryText(colorScheme))
                    .lineLimit(1)
            }
            .frame(width: compact ? 92 : 106, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, compact ? 6 : 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .shadow(
            color: WidgetDesign.eventCardShadow(colorScheme),
            radius: colorScheme == .dark ? 0 : 8,
            x: 0,
            y: colorScheme == .dark ? 0 : 2
        )
    }

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        shape
            .fill(WidgetDesign.eventCardBackground(colorScheme, accent: accent))
            .overlay(
                shape.stroke(WidgetDesign.eventCardStroke(colorScheme), lineWidth: 1)
            )
    }
}

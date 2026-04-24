import SwiftUI
import WidgetKit

/// Root widget view.
///
/// This type chooses between empty, small, and timeline layouts. Rendering details
/// for individual rows live in `NaverCalendarWidgetEventCard` so the root view stays
/// focused on widget-family layout decisions.
struct NaverCalendarWidgetView: View {
    var entry: NaverCalendarEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let content = widgetContent
            .padding(widgetPadding)

        if #available(macOS 14.0, *) {
            content.containerBackground(widgetBackground, for: .widget)
        } else {
            content.background(widgetBackground)
        }
    }

    @ViewBuilder
    private var widgetContent: some View {
        if entry.items.isEmpty {
            emptyState
        } else if family == .systemSmall {
            smallLayout
        } else {
            timelineLayout()
        }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader

            Spacer(minLength: 0)

            if let item = entry.items.first {
                NaverCalendarWidgetEventCard(item: item, compact: false, colorScheme: colorScheme)
            }

            Spacer(minLength: 0)
        }
    }

    private func timelineLayout() -> some View {
        let compact = family == .systemLarge
        let visibleItems = Array(entry.items.prefix(maxVisibleItemCount))
        let hiddenCount = max(entry.items.count - visibleItems.count, 0)

        return VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            widgetHeader

            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                ForEach(visibleItems) { item in
                    NaverCalendarWidgetEventCard(item: item, compact: compact, colorScheme: colorScheme)
                }

                if hiddenCount > 0 {
                    Text("일정 \(hiddenCount)개 더 있음")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(-0.08)
                        .foregroundStyle(WidgetDesign.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 1)
                }
            }
        }
    }

    private var widgetHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(WidgetDateFormatting.headerText(for: entry.date))
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.12)
                .foregroundStyle(WidgetDesign.primaryText(colorScheme))
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text("일정 없음")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.224)
                    .foregroundStyle(WidgetDesign.primaryText(colorScheme))
                Text("앱에서 동기화하면 다가오는 일정이 표시됩니다.")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(-0.12)
                    .foregroundStyle(WidgetDesign.secondaryText(colorScheme))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private var widgetBackground: Color {
        WidgetDesign.surfaceFill(colorScheme)
    }

    private var widgetPadding: CGFloat {
        switch family {
        case .systemSmall:
            12
        case .systemLarge:
            8
        default:
            10
        }
    }

    private var maxVisibleItemCount: Int {
        switch family {
        case .systemLarge:
            6
        case .systemMedium:
            5
        default:
            1
        }
    }
}

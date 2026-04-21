import SwiftUI
import WidgetKit

struct NaverCalendarEntry: TimelineEntry {
    let date: Date
    let items: [WidgetEventSnapshot]
}

struct NaverCalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> NaverCalendarEntry {
        NaverCalendarEntry(date: Date(), items: WidgetEventSnapshot.samples)
    }

    func getSnapshot(in context: Context, completion: @escaping (NaverCalendarEntry) -> Void) {
        Task {
            let items = await WidgetCalendarLoader.load()
            completion(NaverCalendarEntry(date: Date(), items: items))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NaverCalendarEntry>) -> Void) {
        Task {
            let items = await WidgetCalendarLoader.load()
            let entry = NaverCalendarEntry(date: Date(), items: items)
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct NaverCalendarWidgetView: View {
    var entry: NaverCalendarProvider.Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let content = widgetContent
            .padding(widgetPadding)

        if #available(macOS 14.0, *) {
            content.containerBackground(.thinMaterial, for: .widget)
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
                eventCard(item, compact: false)
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
                    eventCard(item, compact: compact)
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
            Text(widgetDate)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.12)
                .foregroundStyle(WidgetDesign.primaryText(colorScheme))
            Spacer()
        }
    }

    private func eventCard(_ item: WidgetEventSnapshot, compact: Bool) -> some View {
        let color = WidgetPalette.color(for: item.colorCode)
        let radius: CGFloat = 8

        return HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 4, height: compact ? 27 : 31)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .tracking(-0.12)
                    .foregroundStyle(WidgetDesign.eventText(colorScheme, accent: color))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(dateRangeText(item))
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .tracking(-0.12)
                    .foregroundStyle(WidgetDesign.secondaryText(colorScheme))
                    .lineLimit(1)

                Text(timeRangeText(item))
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
        .background(
            widgetCardBackground(accent: color, radius: radius)
        )
        .shadow(
            color: WidgetDesign.eventCardShadow(colorScheme),
            radius: colorScheme == .dark ? 0 : 8,
            x: 0,
            y: colorScheme == .dark ? 0 : 2
        )
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

    private var widgetDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: entry.date)
    }

    private func timeRangeText(_ item: WidgetEventSnapshot) -> String {
        if item.isAllDay {
            return "하루 종일"
        }
        let start = Date(timeIntervalSince1970: item.startTimestamp)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        guard let endTimestamp = item.endTimestamp else {
            return formatter.string(from: start)
        }
        let end = Date(timeIntervalSince1970: endTimestamp)
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func dateRangeText(_ item: WidgetEventSnapshot) -> String {
        let start = Date(timeIntervalSince1970: item.startTimestamp)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M/d"
        guard let endTimestamp = item.endTimestamp else {
            return formatter.string(from: start)
        }
        let end = Date(timeIntervalSince1970: endTimestamp)
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return formatter.string(from: start)
        }
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private var widgetBackground: Color {
        WidgetDesign.surfaceFill(colorScheme)
    }

    private var widgetPadding: CGFloat {
        switch family {
        case .systemSmall:
            return 12
        case .systemLarge:
            return 8
        default:
            return 10
        }
    }

    private var maxVisibleItemCount: Int {
        switch family {
        case .systemLarge:
            return 6
        case .systemMedium:
            return 5
        default:
            return 1
        }
    }

    @ViewBuilder
    private func widgetCardBackground(accent: Color, radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        shape
            .fill(WidgetDesign.eventCardBackground(colorScheme, accent: accent))
            .overlay(
                shape.stroke(WidgetDesign.eventCardStroke(colorScheme), lineWidth: 1)
            )
    }
}

private enum WidgetDesign {
    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.92) : Color(red: 0.114, green: 0.114, blue: 0.122)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62)
    }

    static func eventText(_ scheme: ColorScheme, accent: Color) -> Color {
        scheme == .dark ? accent.lighterForWidgetDarkMode() : Color(red: 0.13, green: 0.24, blue: 0.39)
    }

    static func eventCardBackground(_ scheme: ColorScheme, accent: Color) -> Color {
        if scheme == .dark {
            return Color(red: 0.07, green: 0.09, blue: 0.13).opacity(0.70)
                .mix(with: accent, opacity: 0.20)
        }
        return Color.white.opacity(0.58)
            .mix(with: accent, opacity: 0.08)
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

private extension Color {
    func mix(with overlay: Color, opacity: Double) -> Color {
        #if os(macOS)
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .clear
        let top = NSColor(overlay).usingColorSpace(.sRGB) ?? .clear
        let amount = max(0, min(1, opacity))
        return Color(
            red: base.redComponent * (1 - amount) + top.redComponent * amount,
            green: base.greenComponent * (1 - amount) + top.greenComponent * amount,
            blue: base.blueComponent * (1 - amount) + top.blueComponent * amount,
            opacity: base.alphaComponent
        )
        #else
        return self
        #endif
    }

    func lighterForWidgetDarkMode() -> Color {
        #if os(macOS)
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return Color(
            red: min(1, color.redComponent * 0.72 + 0.28),
            green: min(1, color.greenComponent * 0.72 + 0.28),
            blue: min(1, color.blueComponent * 0.72 + 0.28)
        )
        #else
        return self
        #endif
    }
}

struct NaverCalendarWidget: Widget {
    let kind = "NaverCalendarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NaverCalendarProvider()) { entry in
            NaverCalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("lendar")
        .description("다가오는 일정을 바탕화면 위젯으로 보여줍니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

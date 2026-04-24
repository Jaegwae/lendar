import AppKit
import SwiftUI

/// Scrolling month calendar. Handles week-level event lane layout, selected-date glow,
/// and compact-window scaling for dates, event bars, and row height.
struct MonthGridView: View {
    @ObservedObject var store: CalendarStore

    @State private var sections: [MonthSectionModel] = []
    /// Button-driven month jumps also change the scroll position. While that
    /// animation is running, ignore visible-month preference updates so the scroll
    /// detector does not fight the requested month.
    @State private var isProgrammaticMonthScroll = false
    // Fast repeated chevron taps should land on the final requested month instead
    // of queuing several overlapping ScrollViewReader animations.
    @State private var pendingProgrammaticScroll: DispatchWorkItem?
    private let layoutBuilder = MonthLayoutBuilder()
    private let anchorMonth = MonthLayoutBuilder().monthStart(for: Date())

    private let weekdayLabels = ["일", "월", "화", "수", "목", "금", "토"]
    private let visibleLaneCount = 4

    var body: some View {
        GeometryReader { outer in
            let scale = layoutScale(for: outer.size.width)
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    weekdayHeader(scale: scale)

                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: []) {
                            ForEach(sections) { section in
                                MonthSectionView(
                                    section: section,
                                    selectedDate: store.selectedDate,
                                    visibleLaneCount: visibleLaneCount,
                                    scale: scale,
                                    openDay: store.openDay
                                )
                                .id(section.monthStart)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: VisibleMonthPreferenceKey.self,
                                            value: [
                                                VisibleMonthInfo(
                                                    monthStart: section.monthStart,
                                                    minY: geo.frame(in: .named("calendar-scroll")).minY
                                                ),
                                            ]
                                        )
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 24 * scale)
                    }
                    .coordinateSpace(name: "calendar-scroll")
                }
                .background(calendarTableBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(CalendarDesign.divider, lineWidth: 1)
                )
                .onPreferenceChange(VisibleMonthPreferenceKey.self) { values in
                    guard !isProgrammaticMonthScroll else { return }
                    guard let closest = values.min(by: { abs($0.minY) < abs($1.minY) }) else { return }
                    let distance = abs(closest.minY)
                    if distance < 180,
                       !Calendar.current.isDate(closest.monthStart, equalTo: store.displayedMonth, toGranularity: .month)
                    {
                        expandSectionsIfNeeded(around: closest.monthStart)
                        store.updateDisplayedMonthFromScroll(closest.monthStart)
                    }
                }
                .onChange(of: store.displayedMonth) { month in
                    expandSectionsIfNeeded(around: month)
                }
                .onAppear {
                    rebuildSections()
                    DispatchQueue.main.async {
                        let target = store.requestedVisibleMonth ?? todayMonthStart
                        proxy.scrollTo(target, anchor: .top)
                        store.updateDisplayedMonthFromScroll(target)
                    }
                }
                .onChange(of: store.layoutRevision) { _ in
                    rebuildSections()
                    DispatchQueue.main.async {
                        let target = store.requestedVisibleMonth ?? store.displayedMonth
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
                .onChange(of: store.requestedVisibleMonth) { requested in
                    guard let requested else { return }
                    // Rebuild only when the target month is outside the existing
                    // section window. Most adjacent month taps can reuse the current
                    // lazy stack and avoid event lane recalculation.
                    ensureSectionExists(for: requested)
                    pendingProgrammaticScroll?.cancel()

                    let workItem = DispatchWorkItem {
                        isProgrammaticMonthScroll = true
                        withAnimation(.snappy(duration: 0.32, extraBounce: 0.02)) {
                            proxy.scrollTo(requested, anchor: .top)
                        }
                        store.updateDisplayedMonthFromScroll(requested)
                        if let currentRequest = store.requestedVisibleMonth,
                           Calendar.current.isDate(currentRequest, equalTo: requested, toGranularity: .month)
                        {
                            store.requestedVisibleMonth = nil
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                            isProgrammaticMonthScroll = false
                        }
                    }
                    pendingProgrammaticScroll = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
                }
            }
        }
    }

    private var todayMonthStart: Date {
        layoutBuilder.monthStart(for: Date())
    }

    private func weekdayHeader(scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(CalendarDesign.textFont(size: 12 * scale, weight: .semibold))
                    .tracking(-0.12)
                    .foregroundStyle(weekdayColor(index))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 7 * scale)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CalendarDesign.divider)
                .frame(height: 1)
        }
    }

    private var calendarTableBackground: Color {
        CalendarDesign.adaptiveColor(
            light: NSColor.white.withAlphaComponent(0.86),
            dark: NSColor(red: 0.10, green: 0.105, blue: 0.115, alpha: 0.92)
        )
    }

    private func layoutScale(for width: CGFloat) -> CGFloat {
        min(1.0, max(0.82, width / 760.0))
    }

    private func weekdayColor(_ index: Int) -> Color {
        if index == 0 { return Color.red.opacity(0.72) }
        if index == 6 { return CalendarDesign.appleBlue.opacity(0.78) }
        return CalendarDesign.textTertiary
    }

    private func rebuildSections() {
        sections = layoutBuilder.buildSections(
            anchorMonth: anchorMonth,
            displayedMonth: store.displayedMonth,
            requestedVisibleMonth: store.requestedVisibleMonth,
            items: store.orderedFilteredItems
        )
    }

    private func ensureSectionExists(for month: Date) {
        let target = layoutBuilder.monthStart(for: month)
        guard !sections.contains(where: { Calendar.current.isDate($0.monthStart, equalTo: target, toGranularity: .month) }) else {
            return
        }
        rebuildSections()
    }

    private func expandSectionsIfNeeded(around month: Date) {
        guard let first = sections.first?.monthStart, let last = sections.last?.monthStart else {
            rebuildSections()
            return
        }

        let target = layoutBuilder.monthStart(for: month)
        let monthsFromStart = layoutBuilder.monthOffset(from: first, to: target)
        let monthsToEnd = layoutBuilder.monthOffset(from: target, to: last)

        // While scrolling, extend the lazy month stack before the user hits the
        // current edge so continuous wheel/trackpad scrolling can keep going.
        if monthsFromStart <= 2 || monthsToEnd <= 2 {
            rebuildSections()
        }
    }
}

private struct MonthSectionView: View {
    let section: MonthSectionModel
    let selectedDate: Date
    let visibleLaneCount: Int
    let scale: CGFloat
    let openDay: (Date) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(section.rows) { row in
                MonthWeekRow(
                    week: row.week,
                    displayedMonth: section.monthStart,
                    segments: row.segments,
                    hiddenCount: row.hiddenCount,
                    hiddenCountByColumn: row.hiddenCountByColumn,
                    visibleLaneCount: visibleLaneCount,
                    selectedDate: selectedDate,
                    scale: scale,
                    openDay: openDay
                )
            }
        }
    }
}

private struct MonthWeekRow: View {
    let week: [Date?]
    let displayedMonth: Date
    let segments: [WeekEventSegment]
    let hiddenCount: Int
    let hiddenCountByColumn: [Int]
    let visibleLaneCount: Int
    let selectedDate: Date
    let scale: CGFloat
    let openDay: (Date) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let columnWidth = geo.size.width / 7.0

                ZStack(alignment: .topLeading) {
                    dayHitAreas(columnWidth: columnWidth)
                    gridLines(height: rowHeight, columnWidth: columnWidth)
                    selectedDayGlow(columnWidth: columnWidth)
                    dayHeaders(columnWidth: columnWidth)
                    eventBars(columnWidth: columnWidth)
                }
            }
            .frame(height: rowHeight)
            Rectangle()
                .fill(CalendarDesign.divider)
                .frame(height: 1)
        }
    }

    private var rowHeight: CGFloat {
        172 * scale
    }

    private func dayHitAreas(columnWidth: CGFloat) -> some View {
        ForEach(Array(week.enumerated()), id: \.offset) { index, date in
            if let date {
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: columnWidth, height: rowHeight)
                    .contentShape(Rectangle())
                    .offset(x: CGFloat(index) * columnWidth)
                    .onTapGesture {
                        openDay(date)
                    }
            }
        }
    }

    private func gridLines(height: CGFloat, columnWidth: CGFloat) -> some View {
        ForEach(1 ..< 7, id: \.self) { index in
            Rectangle()
                .fill(CalendarDesign.divider)
                .frame(width: 1, height: height)
                .offset(x: CGFloat(index) * columnWidth)
        }
    }

    private func selectedDayGlow(columnWidth: CGFloat) -> some View {
        ForEach(Array(week.enumerated()), id: \.offset) { index, date in
            if let date, isSelected(date) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CalendarDesign.selectedDayFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(CalendarDesign.appleBlue.opacity(colorScheme == .dark ? 0.54 : 0.28), lineWidth: 1)
                    )
                    .shadow(color: CalendarDesign.selectedDayShadow, radius: 18 * scale, x: 0, y: 0)
                    .shadow(color: CalendarDesign.appleBlue.opacity(colorScheme == .dark ? 0.38 : 0.22), radius: 22 * scale, x: 0, y: 0)
                    .frame(width: columnWidth - 8 * scale, height: rowHeight - 8 * scale)
                    .offset(x: CGFloat(index) * columnWidth + 4 * scale, y: 4 * scale)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private func dayHeaders(columnWidth: CGFloat) -> some View {
        ForEach(Array(week.enumerated()), id: \.offset) { index, date in
            Group {
                if let date {
                    let isToday = Calendar.current.isDateInToday(date)
                    Text(CalendarFormatting.dayNumber.string(from: date))
                        .font(CalendarDesign.displayFont(size: 21 * scale, weight: .semibold))
                        .tracking(-0.28)
                        .padding(.horizontal, isToday ? 10 * scale : 0)
                        .padding(.vertical, isToday ? 2 * scale : 0)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isToday ? CalendarDesign.appleBlue : .clear)
                        )
                        .foregroundStyle(isToday ? Color.white : dayColor(index: index))
                        .animation(.snappy(duration: 0.24), value: selectedDate)
                } else {
                    Text("")
                }
            }
            .frame(width: columnWidth, alignment: .topLeading)
            .padding(.leading, 10 * scale)
            .padding(.top, 8 * scale)
            .allowsHitTesting(false)
            .offset(x: CGFloat(index) * columnWidth)
        }
    }

    @ViewBuilder
    private func eventBars(columnWidth: CGFloat) -> some View {
        ForEach(segments.filter { $0.lane < visibleLaneCount }) { segment in
            let xOffset = CGFloat(segment.startColumn) * columnWidth + 4
            let width = CGFloat(segment.endColumn - segment.startColumn + 1) * columnWidth - 8
            let yOffset = (54 + CGFloat(segment.lane) * 21) * scale

            MonthBarEventView(
                item: segment.item,
                position: segment.position,
                isInDisplayedMonth: true,
                scale: scale
            )
            .frame(width: width, height: 17 * scale)
            .offset(x: xOffset, y: yOffset)
            .allowsHitTesting(false)
        }

        if hiddenCount > 0 {
            ForEach(Array(hiddenCountByColumn.enumerated()), id: \.offset) { index, count in
                if count > 0 {
                    Text("+\(count)")
                        .font(.system(size: 12 * scale, weight: .semibold))
                        .foregroundStyle(CalendarDesign.linkBlue)
                        .frame(width: columnWidth, alignment: .topLeading)
                        .offset(x: CGFloat(index) * columnWidth + 8 * scale, y: (54 + CGFloat(visibleLaneCount) * 21 + 4) * scale)
                }
            }
        }
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func dayColor(index: Int) -> Color {
        if index == 0 { return Color.red.opacity(0.76) }
        if index == 6 { return CalendarDesign.appleBlue.opacity(0.86) }
        return CalendarDesign.nearBlack
    }
}

private struct MonthBarEventView: View {
    let item: CalendarItem
    let position: CalendarSpanPosition
    let isInDisplayedMonth: Bool
    let scale: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .leading) {
            ContinuousEventPill(position: position)
                .fill(itemColor)

            HStack(spacing: 4) {
                Text(CalendarText.cleanName(item.summary))
                    .font(CalendarDesign.textFont(size: 10 * scale, weight: item.isCompleted ? .medium : .semibold))
                    .tracking(-0.08)
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .padding(.leading, (position == .middle ? 3 : 6) * scale)

                Spacer(minLength: 0)

                if item.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7 * scale, weight: .bold))
                        .foregroundStyle(labelColor.opacity(0.9))
                        .calendarAnimatedIcon(scale: 1.18)
                        .padding(.trailing, 5 * scale)
                }
            }
        }
    }

    private var itemColor: Color {
        if !isInDisplayedMonth {
            return CalendarPalette.eventTint(for: item).opacity(item.isCompleted ? 0.08 : (colorScheme == .dark ? 0.18 : 0.10))
        }
        if item.isCompleted {
            return CalendarPalette.eventTint(for: item).opacity(colorScheme == .dark ? 0.20 : 0.16)
        }
        if item.isAllDay {
            return CalendarPalette.eventTint(for: item)
        }
        return CalendarPalette.eventTint(for: item).opacity(colorScheme == .dark ? 0.24 : 0.14)
    }

    private var labelColor: Color {
        if !isInDisplayedMonth {
            return CalendarDesign.textTertiary.opacity(0.55)
        }
        if item.isCompleted {
            return CalendarDesign.textTertiary
        }
        if item.isAllDay {
            return .white
        }
        return colorScheme == .dark ? Color.white.opacity(0.88) : CalendarPalette.eventTint(for: item)
    }
}

private struct ContinuousEventPill: Shape {
    let position: CalendarSpanPosition

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 5
        switch position {
        case .single:
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        case .start:
            return customPath(in: rect, roundLeft: true, roundRight: false, radius: radius)
        case .middle:
            return Rectangle().path(in: rect)
        case .end:
            return customPath(in: rect, roundLeft: false, roundRight: true, radius: radius)
        }
    }

    private func customPath(in rect: CGRect, roundLeft: Bool, roundRight: Bool, radius: CGFloat) -> Path {
        var path = Path()
        let leftRadius = roundLeft ? radius : 0
        let rightRadius = roundRight ? radius : 0

        path.move(to: CGPoint(x: rect.minX + leftRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rightRadius, y: rect.minY))
        if roundRight {
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rightRadius), control: CGPoint(x: rect.maxX, y: rect.minY))
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rightRadius))
        if roundRight {
            path.addQuadCurve(to: CGPoint(x: rect.maxX - rightRadius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }

        path.addLine(to: CGPoint(x: rect.minX + leftRadius, y: rect.maxY))
        if roundLeft {
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - leftRadius), control: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + leftRadius))
        if roundLeft {
            path.addQuadCurve(to: CGPoint(x: rect.minX + leftRadius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        path.closeSubpath()
        return path
    }
}

private struct VisibleMonthInfo: Equatable {
    let monthStart: Date
    let minY: CGFloat
}

private struct VisibleMonthPreferenceKey: PreferenceKey {
    static let defaultValue: [VisibleMonthInfo] = []

    static func reduce(value: inout [VisibleMonthInfo], nextValue: () -> [VisibleMonthInfo]) {
        value.append(contentsOf: nextValue())
    }
}

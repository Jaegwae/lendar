import SwiftUI

struct MonthGridView: View {
    @ObservedObject var store: CalendarStore

    @State private var sections: [MonthSectionModel] = []
    private let anchorMonth = Self.monthStart(for: Date())

    private let weekdayLabels = ["일", "월", "화", "수", "목", "금", "토"]
    private let visibleLaneCount = 4

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                weekdayHeader
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ForEach(sections) { section in
                            MonthSectionView(
                                section: section,
                                selectedDate: store.selectedDate,
                                visibleLaneCount: visibleLaneCount,
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
                                            )
                                        ]
                                    )
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 24)
                }
                .coordinateSpace(name: "calendar-scroll")
            }
            .calendarGlassSurface(cornerRadius: 14, material: .regularMaterial, tintOpacity: 0.20, shadowOpacity: 0.10)
            .onPreferenceChange(VisibleMonthPreferenceKey.self) { values in
                guard let closest = values.min(by: { abs($0.minY) < abs($1.minY) }) else { return }
                let distance = abs(closest.minY)
                if distance < 180,
                   !Calendar.current.isDate(closest.monthStart, equalTo: store.displayedMonth, toGranularity: .month) {
                    store.displayedMonth = closest.monthStart
                }
            }
            .onAppear {
                rebuildSections()
                DispatchQueue.main.async {
                    let target = store.requestedVisibleMonth ?? todayMonthStart
                    proxy.scrollTo(target, anchor: .top)
                    store.displayedMonth = target
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
                rebuildSections()
                DispatchQueue.main.async {
                    withAnimation(.snappy(duration: 0.32, extraBounce: 0.02)) {
                        proxy.scrollTo(requested, anchor: .top)
                    }
                    store.displayedMonth = requested
                    store.requestedVisibleMonth = nil
                }
            }
        }
    }

    private var todayMonthStart: Date {
        Self.monthStart(for: Date())
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { index, label in
                Text(label)
                    .font(CalendarDesign.textFont(size: 12, weight: .semibold))
                    .tracking(-0.12)
                    .foregroundStyle(weekdayColor(index))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CalendarDesign.glassHighlight.opacity(0.72), lineWidth: 1)
        )
    }

    private func weekdayColor(_ index: Int) -> Color {
        if index == 0 { return Color.red.opacity(0.72) }
        if index == 6 { return CalendarDesign.appleBlue.opacity(0.78) }
        return CalendarDesign.textTertiary
    }

    private func rebuildSections() {
        let defaultStart = month(byAdding: -6, to: anchorMonth)
        let defaultEnd = month(byAdding: 12, to: anchorMonth)
        let requested = store.requestedVisibleMonth.map(Self.monthStart(for:))
        let focused = Self.monthStart(for: store.displayedMonth)

        let targetStart = [defaultStart, requested.map { month(byAdding: -6, to: $0) }, month(byAdding: -6, to: focused)]
            .compactMap { $0 }
            .min() ?? defaultStart
        let targetEnd = [defaultEnd, requested.map { month(byAdding: 6, to: $0) }, month(byAdding: 6, to: focused)]
            .compactMap { $0 }
            .max() ?? defaultEnd
        let startOffset = monthOffset(from: anchorMonth, to: targetStart)
        let endOffset = monthOffset(from: anchorMonth, to: targetEnd)

        let months = (startOffset...endOffset).compactMap { offset -> Date? in
            month(byAdding: offset, to: anchorMonth)
        }

        sections = months.map { monthStart in
            buildSection(monthStart: monthStart)
        }
    }

    private func buildSection(monthStart: Date) -> MonthSectionModel {
        let weeks = makeWeeks(for: monthStart)
        let filteredItems = store.orderedFilteredItems

        let rows: [MonthWeekRowModel] = weeks.enumerated().map { index, week in
            let segments = buildSegments(week: week, monthStart: monthStart, items: filteredItems)
            let visibleCount = segments.filter { $0.lane < visibleLaneCount }.count
            let hiddenCount = max(0, segments.count - visibleCount)
            let hiddenCountByColumn = hiddenCountsByColumn(segments: segments)
            let rowID = "\(monthStart.timeIntervalSinceReferenceDate)-\(index)"
            return MonthWeekRowModel(
                id: rowID,
                week: week,
                segments: segments,
                hiddenCount: hiddenCount,
                hiddenCountByColumn: hiddenCountByColumn
            )
        }

        return MonthSectionModel(monthStart: monthStart, rows: rows)
    }

    private func makeWeeks(for monthStart: Date) -> [[Date?]] {
        let calendar = Calendar.current
        let startWeekday = calendar.component(.weekday, from: monthStart) - 1
        let totalDays = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let totalCellCount = startWeekday + totalDays
        let weekCount = Int(ceil(Double(totalCellCount) / 7.0))

        let cells: [Date?] = (0..<(weekCount * 7)).map { index in
            let dayNumber = index - startWeekday + 1
            guard dayNumber >= 1, dayNumber <= totalDays else { return nil }
            return calendar.date(byAdding: .day, value: dayNumber - 1, to: monthStart)
        }

        return stride(from: 0, to: weekCount * 7, by: 7).map { offset in
            Array(cells[offset..<offset + 7])
        }
    }

    private func buildSegments(week: [Date?], monthStart: Date, items: [CalendarItem]) -> [WeekEventSegment] {
        let activeDates = week.compactMap { $0 }
        guard let firstDate = activeDates.first, let lastDate = activeDates.last else { return [] }

        let relevantItems = items.filter { item in
            guard let itemStart = item.displayStartDay, let itemEnd = item.displayEndDay else { return false }
            return itemStart <= lastDate && itemEnd >= firstDate
        }

        var occupied: [[ClosedRange<Int>]] = Array(repeating: [], count: visibleLaneCount + 20)
        var results: [WeekEventSegment] = []

        for item in relevantItems {
            let visibleIndices = week.enumerated().compactMap { index, date -> Int? in
                guard let date, item.occurs(on: date) else { return nil }
                return index
            }
            guard let startCol = visibleIndices.first, let endCol = visibleIndices.last else { continue }
            let range = startCol...endCol

            var lane = 0
            while lane < occupied.count {
                let hasConflict = occupied[lane].contains { existing in
                    !(range.upperBound < existing.lowerBound || range.lowerBound > existing.upperBound)
                }
                if !hasConflict {
                    occupied[lane].append(range)
                    break
                }
                lane += 1
            }

            results.append(
                WeekEventSegment(
                    item: item,
                    startColumn: startCol,
                    endColumn: endCol,
                    lane: lane,
                    monthStart: monthStart
                )
            )
        }

        return results
    }

    private func hiddenCountsByColumn(segments: [WeekEventSegment]) -> [Int] {
        var counts = Array(repeating: 0, count: 7)
        for segment in segments where segment.lane >= visibleLaneCount {
            for column in segment.startColumn...segment.endColumn {
                if column >= 0 && column < counts.count {
                    counts[column] += 1
                }
            }
        }
        return counts
    }

    private static func monthStart(for date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }

    private func month(byAdding offset: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .month, value: offset, to: date)
            .map(Self.monthStart(for:)) ?? Self.monthStart(for: date)
    }

    private func monthOffset(from start: Date, to end: Date) -> Int {
        Calendar.current.dateComponents([.month], from: Self.monthStart(for: start), to: Self.monthStart(for: end)).month ?? 0
    }
}

private struct MonthSectionView: View {
    let section: MonthSectionModel
    let selectedDate: Date
    let visibleLaneCount: Int
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
        172
    }

    @ViewBuilder
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

    @ViewBuilder
    private func gridLines(height: CGFloat, columnWidth: CGFloat) -> some View {
        ForEach(1..<7, id: \.self) { index in
            Rectangle()
                .fill(CalendarDesign.divider)
                .frame(width: 1, height: height)
                .offset(x: CGFloat(index) * columnWidth)
        }
    }

    @ViewBuilder
    private func selectedDayGlow(columnWidth: CGFloat) -> some View {
        ForEach(Array(week.enumerated()), id: \.offset) { index, date in
            if let date, isSelected(date) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CalendarDesign.selectedDayFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(CalendarDesign.appleBlue.opacity(colorScheme == .dark ? 0.54 : 0.28), lineWidth: 1)
                    )
                    .shadow(color: CalendarDesign.selectedDayShadow, radius: 18, x: 0, y: 0)
                    .shadow(color: CalendarDesign.appleBlue.opacity(colorScheme == .dark ? 0.38 : 0.22), radius: 22, x: 0, y: 0)
                    .frame(width: columnWidth - 8, height: rowHeight - 8)
                    .offset(x: CGFloat(index) * columnWidth + 4, y: 4)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func dayHeaders(columnWidth: CGFloat) -> some View {
        ForEach(Array(week.enumerated()), id: \.offset) { index, date in
            Group {
                if let date {
                    let isToday = Calendar.current.isDateInToday(date)
                    Text(CalendarFormatting.dayNumber.string(from: date))
                        .font(CalendarDesign.displayFont(size: 21, weight: .semibold))
                        .tracking(-0.28)
                        .padding(.horizontal, isToday ? 10 : 0)
                        .padding(.vertical, isToday ? 2 : 0)
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
            .padding(.leading, 10)
            .padding(.top, 8)
            .allowsHitTesting(false)
            .offset(x: CGFloat(index) * columnWidth)
        }
    }

    @ViewBuilder
    private func eventBars(columnWidth: CGFloat) -> some View {
        ForEach(segments.filter { $0.lane < visibleLaneCount }) { segment in
            let x = CGFloat(segment.startColumn) * columnWidth + 4
            let width = CGFloat(segment.endColumn - segment.startColumn + 1) * columnWidth - 8
            let y = 54 + CGFloat(segment.lane) * 21

            MonthBarEventView(
                item: segment.item,
                position: segment.position,
                isInDisplayedMonth: true
            )
            .frame(width: width, height: 17)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
        }

        if hiddenCount > 0 {
            ForEach(Array(hiddenCountByColumn.enumerated()), id: \.offset) { index, count in
                if count > 0 {
                    Text("+\(count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CalendarDesign.linkBlue)
                        .frame(width: columnWidth, alignment: .topLeading)
                        .offset(x: CGFloat(index) * columnWidth + 8, y: 54 + CGFloat(visibleLaneCount) * 21 + 4)
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .leading) {
            ContinuousEventPill(position: position)
                .fill(itemColor)

            HStack(spacing: 4) {
                Text(CalendarText.cleanName(item.summary))
                    .font(CalendarDesign.textFont(size: 10, weight: item.isCompleted ? .medium : .semibold))
                    .tracking(-0.08)
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .padding(.leading, position == .middle ? 3 : 6)

                Spacer(minLength: 0)

                if item.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(labelColor.opacity(0.9))
                        .calendarAnimatedIcon(scale: 1.18)
                        .padding(.trailing, 5)
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

private struct WeekEventSegment: Identifiable {
    var id: String {
        "\(item.uid)|\(monthStart.timeIntervalSinceReferenceDate)|\(startColumn)|\(endColumn)|\(lane)"
    }
    let item: CalendarItem
    let startColumn: Int
    let endColumn: Int
    let lane: Int
    let monthStart: Date

    var position: CalendarSpanPosition {
        let calendar = Calendar.current
        let monthEnd = calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart) ?? monthStart
        let startsBeforeMonth = (item.displayStartDay ?? monthStart) < monthStart
        let endsAfterMonth = (item.displayEndDay ?? monthEnd) > monthEnd

        if !startsBeforeMonth && !endsAfterMonth && startColumn == endColumn {
            return .single
        }
        if startsBeforeMonth && endsAfterMonth {
            return .middle
        }
        if startsBeforeMonth {
            return .end
        }
        if endsAfterMonth {
            return .start
        }
        return startColumn == endColumn ? .single : .start
    }
}

private struct MonthSectionModel: Identifiable {
    var id: Date { monthStart }
    let monthStart: Date
    let rows: [MonthWeekRowModel]
}

private struct MonthWeekRowModel: Identifiable {
    let id: String
    let week: [Date?]
    let segments: [WeekEventSegment]
    let hiddenCount: Int
    let hiddenCountByColumn: [Int]
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

import Foundation

struct MonthLayoutBuilder {
    let calendar: Calendar
    let visibleLaneCount: Int

    init(calendar: Calendar = .current, visibleLaneCount: Int = 4) {
        self.calendar = calendar
        self.visibleLaneCount = visibleLaneCount
    }

    func buildSections(
        anchorMonth: Date,
        displayedMonth: Date,
        requestedVisibleMonth: Date?,
        items: [CalendarItem]
    ) -> [MonthSectionModel] {
        let anchor = monthStart(for: anchorMonth)
        let defaultStart = month(byAdding: -6, to: anchor)
        let defaultEnd = month(byAdding: 12, to: anchor)
        let requested = requestedVisibleMonth.map(monthStart(for:))
        let focused = monthStart(for: displayedMonth)

        let targetStart = [defaultStart, requested.map { month(byAdding: -6, to: $0) }, month(byAdding: -6, to: focused)]
            .compactMap(\.self)
            .min() ?? defaultStart
        let targetEnd = [defaultEnd, requested.map { month(byAdding: 6, to: $0) }, month(byAdding: 6, to: focused)]
            .compactMap(\.self)
            .max() ?? defaultEnd
        let startOffset = monthOffset(from: anchor, to: targetStart)
        let endOffset = monthOffset(from: anchor, to: targetEnd)

        let months = (startOffset ... endOffset).compactMap { offset -> Date? in
            month(byAdding: offset, to: anchor)
        }

        return months.map { monthStart in
            buildSection(monthStart: monthStart, items: items)
        }
    }

    func buildSection(monthStart: Date, items: [CalendarItem]) -> MonthSectionModel {
        let normalizedMonth = self.monthStart(for: monthStart)
        let weeks = makeWeeks(for: normalizedMonth)

        let rows: [MonthWeekRowModel] = weeks.enumerated().map { index, week in
            let segments = buildSegments(week: week, monthStart: normalizedMonth, items: items)
            let visibleCount = segments.count(where: { $0.lane < visibleLaneCount })
            let hiddenCount = max(0, segments.count - visibleCount)
            let hiddenCountByColumn = hiddenCountsByColumn(segments: segments)
            let rowID = "\(normalizedMonth.timeIntervalSinceReferenceDate)-\(index)"
            return MonthWeekRowModel(
                id: rowID,
                week: week,
                segments: segments,
                hiddenCount: hiddenCount,
                hiddenCountByColumn: hiddenCountByColumn
            )
        }

        return MonthSectionModel(monthStart: normalizedMonth, rows: rows)
    }

    func makeWeeks(for monthStart: Date) -> [[Date?]] {
        let normalizedMonth = self.monthStart(for: monthStart)
        let startWeekday = calendar.component(.weekday, from: normalizedMonth) - 1
        let totalDays = calendar.range(of: .day, in: .month, for: normalizedMonth)?.count ?? 30
        let totalCellCount = startWeekday + totalDays
        let weekCount = Int(ceil(Double(totalCellCount) / 7.0))

        let cells: [Date?] = (0 ..< (weekCount * 7)).map { index in
            let dayNumber = index - startWeekday + 1
            guard dayNumber >= 1, dayNumber <= totalDays else { return nil }
            return calendar.date(byAdding: .day, value: dayNumber - 1, to: normalizedMonth)
        }

        return stride(from: 0, to: weekCount * 7, by: 7).map { offset in
            Array(cells[offset ..< offset + 7])
        }
    }

    func buildSegments(week: [Date?], monthStart: Date, items: [CalendarItem]) -> [WeekEventSegment] {
        let activeDates = week.compactMap(\.self)
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
            let range = startCol ... endCol

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
                    monthStart: self.monthStart(for: monthStart),
                    calendar: calendar
                )
            )
        }

        return results
    }

    func hiddenCountsByColumn(segments: [WeekEventSegment]) -> [Int] {
        var counts = Array(repeating: 0, count: 7)
        for segment in segments where segment.lane >= visibleLaneCount {
            for column in segment.startColumn ... segment.endColumn {
                if column >= 0, column < counts.count {
                    counts[column] += 1
                }
            }
        }
        return counts
    }

    func monthStart(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    func month(byAdding offset: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: offset, to: date)
            .map(monthStart(for:)) ?? monthStart(for: date)
    }

    func monthOffset(from start: Date, to end: Date) -> Int {
        calendar.dateComponents([.month], from: monthStart(for: start), to: monthStart(for: end)).month ?? 0
    }
}

struct WeekEventSegment: Identifiable {
    var id: String {
        "\(item.uid)|\(monthStart.timeIntervalSinceReferenceDate)|\(startColumn)|\(endColumn)|\(lane)"
    }

    let item: CalendarItem
    let startColumn: Int
    let endColumn: Int
    let lane: Int
    let monthStart: Date
    private let calendar: Calendar

    init(
        item: CalendarItem,
        startColumn: Int,
        endColumn: Int,
        lane: Int,
        monthStart: Date,
        calendar: Calendar = .current
    ) {
        self.item = item
        self.startColumn = startColumn
        self.endColumn = endColumn
        self.lane = lane
        self.monthStart = monthStart
        self.calendar = calendar
    }

    var position: CalendarSpanPosition {
        let monthEnd = calendar.date(
            byAdding: .day,
            value: -1,
            to: calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        ) ?? monthStart
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

struct MonthSectionModel: Identifiable {
    var id: Date {
        monthStart
    }

    let monthStart: Date
    let rows: [MonthWeekRowModel]
}

struct MonthWeekRowModel: Identifiable {
    let id: String
    let week: [Date?]
    let segments: [WeekEventSegment]
    let hiddenCount: Int
    let hiddenCountByColumn: [Int]
}

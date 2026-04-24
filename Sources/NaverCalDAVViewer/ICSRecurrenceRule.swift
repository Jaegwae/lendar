import Foundation

/// Expands the subset of iCalendar RRULEs that users commonly create in
/// calendar apps, while keeping generation bounded for UI safety.
struct RecurrenceRule {
    private let frequency: String
    private let count: Int?
    private let until: Date?
    private let interval: Int
    private let byWeekdays: [WeekdaySpecifier]
    private let byMonthDays: [Int]
    private let byMonths: [Int]
    private let byYearDays: [Int]
    private let byWeekNumbers: [Int]
    private let bySetPositions: [Int]
    private let weekStart: Int

    init?(raw: String?) {
        guard let raw else { return nil }
        let values = Dictionary(
            uniqueKeysWithValues: raw
                .split(separator: ";")
                .compactMap { component -> (String, String)? in
                    guard let equals = component.firstIndex(of: "=") else {
                        return nil
                    }
                    let key = String(component[..<equals]).uppercased()
                    let value = String(component[component.index(after: equals)...]).uppercased()
                    return (key, value)
                }
        )

        frequency = values["FREQ"] ?? ""
        count = values["COUNT"].flatMap(Int.init)
        until = values["UNTIL"].flatMap { CalendarValueParser.parseDateValue($0).date }
        interval = max(values["INTERVAL"].flatMap(Int.init) ?? 1, 1)
        byWeekdays = values["BYDAY"]?
            .split(separator: ",")
            .compactMap { WeekdaySpecifier(raw: String($0)) } ?? []
        byMonthDays = Self.intList(values["BYMONTHDAY"]).filter { $0 != 0 && abs($0) <= 31 }
        byMonths = Self.intList(values["BYMONTH"]).filter { (1 ... 12).contains($0) }
        byYearDays = Self.intList(values["BYYEARDAY"]).filter { $0 != 0 && abs($0) <= 366 }
        byWeekNumbers = Self.intList(values["BYWEEKNO"]).filter { $0 != 0 && abs($0) <= 53 }
        bySetPositions = Self.intList(values["BYSETPOS"]).filter { $0 != 0 }
        weekStart = values["WKST"].flatMap(Self.weekday) ?? 2

        guard ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].contains(frequency) else {
            return nil
        }
    }

    func occurrences(startingAt start: Date, rangeStart: Date? = nil, rangeEnd: Date? = nil) -> [Date] {
        let scanStart = scanStart(originalStart: start, rangeStart: rangeStart)
        let scanDays = maxScannedDays(from: scanStart, rangeEnd: rangeEnd)
        return switch frequency {
        case "DAILY":
            occurrences(startingAt: start, scanStart: scanStart, maxScannedDays: scanDays, rangeStart: rangeStart, rangeEnd: rangeEnd)
        case "WEEKLY":
            occurrences(startingAt: start, scanStart: scanStart, maxScannedDays: scanDays, rangeStart: rangeStart, rangeEnd: rangeEnd)
        case "MONTHLY":
            occurrences(startingAt: start, scanStart: scanStart, maxScannedDays: scanDays, rangeStart: rangeStart, rangeEnd: rangeEnd)
        case "YEARLY":
            occurrences(startingAt: start, scanStart: scanStart, maxScannedDays: scanDays, rangeStart: rangeStart, rangeEnd: rangeEnd)
        default:
            []
        }
    }

    private func occurrences(
        startingAt start: Date,
        scanStart: Date,
        maxScannedDays: Int,
        rangeStart: Date?,
        rangeEnd: Date?
    ) -> [Date] {
        let calendar = Calendar.current
        var dates: [Date] = []
        var positionCache: [String: [Date]] = [:]

        for offset in 0 ..< maxScannedDays {
            guard dates.count < cappedOccurrenceCount,
                  let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: scanStart)),
                  let occurrence = calendar.date(onSameDayAs: day, preservingTimeFrom: start)
            else {
                break
            }

            if let until, occurrence > until {
                break
            }
            if let rangeEnd, occurrence > rangeEnd {
                break
            }

            guard occurrence >= start,
                  rangeStart.map({ occurrence >= $0 }) ?? true,
                  matches(day: day, start: start, calendar: calendar, positionCache: &positionCache)
            else {
                continue
            }
            dates.append(occurrence)
        }

        return dates
    }

    private func scanStart(originalStart: Date, rangeStart: Date?) -> Date {
        guard count == nil, let rangeStart, rangeStart > originalStart else {
            return originalStart
        }

        let calendar = Calendar.current
        switch frequency {
        case "WEEKLY":
            return calendar.startOfWeek(containing: rangeStart, firstWeekday: weekStart)
        case "MONTHLY":
            return calendar.startOfMonth(containing: rangeStart)
        case "YEARLY":
            return calendar.startOfYear(containing: rangeStart)
        default:
            return calendar.startOfDay(for: rangeStart)
        }
    }

    private func maxScannedDays(from scanStart: Date, rangeEnd: Date?) -> Int {
        guard let rangeEnd else {
            switch frequency {
            case "DAILY": return 370 * interval
            case "WEEKLY": return 370 * 7 * interval
            case "MONTHLY": return 370 * 31 * interval
            case "YEARLY": return 370 * 366 * interval
            default: return 370
            }
        }

        let days = Calendar.current.dateComponents([.day], from: scanStart, to: rangeEnd).day ?? 0
        return max(days + 2, 1)
    }

    private var cappedOccurrenceCount: Int {
        min(count ?? 370, 370)
    }

    private func matches(
        day: Date,
        start: Date,
        calendar: Calendar,
        positionCache: inout [String: [Date]]
    ) -> Bool {
        switch frequency {
        case "DAILY":
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: day).day ?? 0
            return days % interval == 0 && matchesCommonFilters(day: day, start: start, calendar: calendar)
        case "WEEKLY":
            let startWeek = calendar.startOfWeek(containing: start, firstWeekday: weekStart)
            let week = calendar.startOfWeek(containing: day, firstWeekday: weekStart)
            let weekOffset = calendar.dateComponents([.weekOfYear], from: startWeek, to: week).weekOfYear ?? 0
            let defaultWeekday = WeekdaySpecifier(weekday: calendar.component(.weekday, from: start))
            let selectedWeekdays = Set((byWeekdays.isEmpty ? [defaultWeekday] : byWeekdays).map(\.weekday))
            return weekOffset >= 0
                && weekOffset % interval == 0
                && selectedWeekdays.contains(calendar.component(.weekday, from: day))
                && matchesMonthFilter(day: day, calendar: calendar)
        case "MONTHLY":
            let startMonth = calendar.startOfMonth(containing: start)
            let month = calendar.startOfMonth(containing: day)
            let monthOffset = calendar.dateComponents([.month], from: startMonth, to: month).month ?? 0
            return monthOffset >= 0
                && monthOffset % interval == 0
                && matchesMonthlyDay(day: day, start: start, calendar: calendar, positionCache: &positionCache)
                && matchesMonthFilter(day: day, calendar: calendar)
        case "YEARLY":
            let yearOffset = calendar.component(.year, from: day) - calendar.component(.year, from: start)
            return yearOffset >= 0
                && yearOffset % interval == 0
                && matchesYearlyDay(day: day, start: start, calendar: calendar, positionCache: &positionCache)
        default:
            return false
        }
    }

    private func matchesCommonFilters(day: Date, start _: Date, calendar: Calendar) -> Bool {
        matchesMonthFilter(day: day, calendar: calendar)
            && matchesMonthDayFilter(day: day, calendar: calendar)
            && matchesYearDayFilter(day: day, calendar: calendar)
            && matchesWeekNumberFilter(day: day, calendar: calendar)
            && matchesWeekdayFilter(day: day, calendar: calendar)
    }

    private func matchesMonthlyDay(
        day: Date,
        start: Date,
        calendar: Calendar,
        positionCache: inout [String: [Date]]
    ) -> Bool {
        if !bySetPositions.isEmpty {
            return selectedPositionDays(
                in: calendar.startOfMonth(containing: day),
                component: .month,
                calendar: calendar,
                positionCache: &positionCache
            ).contains {
                calendar.isDate($0, inSameDayAs: day)
            }
        }

        if byWeekdays.contains(where: { $0.ordinal != nil }) {
            return byWeekdays.contains { specifier in
                specifier.matches(day: day, in: .month, calendar: calendar)
            }
        }

        if !byMonthDays.isEmpty {
            return matchesMonthDayFilter(day: day, calendar: calendar)
        }

        if !byWeekdays.isEmpty {
            return matchesWeekdayFilter(day: day, calendar: calendar)
        }

        return calendar.component(.day, from: day) == calendar.component(.day, from: start)
    }

    private func matchesYearlyDay(
        day: Date,
        start: Date,
        calendar: Calendar,
        positionCache: inout [String: [Date]]
    ) -> Bool {
        if !matchesMonthFilter(day: day, calendar: calendar) {
            return false
        }

        if !bySetPositions.isEmpty {
            return selectedPositionDays(
                in: calendar.startOfYear(containing: day),
                component: .year,
                calendar: calendar,
                positionCache: &positionCache
            ).contains {
                calendar.isDate($0, inSameDayAs: day)
            }
        }

        guard matchesYearDayFilter(day: day, calendar: calendar),
              matchesWeekNumberFilter(day: day, calendar: calendar)
        else {
            return false
        }

        if byWeekdays.contains(where: { $0.ordinal != nil }) {
            let scope: Calendar.Component = byMonths.isEmpty ? .year : .month
            return byWeekdays.contains { $0.matches(day: day, in: scope, calendar: calendar) }
                && matchesMonthDayFilter(day: day, calendar: calendar)
        }

        if hasExplicitYearlyDaySelectors {
            return matchesMonthDayFilter(day: day, calendar: calendar)
                && matchesWeekdayFilter(day: day, calendar: calendar)
        }

        return calendar.component(.month, from: day) == calendar.component(.month, from: start)
            && calendar.component(.day, from: day) == calendar.component(.day, from: start)
    }

    private var hasExplicitYearlyDaySelectors: Bool {
        !byMonthDays.isEmpty || !byWeekdays.isEmpty || !byYearDays.isEmpty || !byWeekNumbers.isEmpty
    }

    private func matchesMonthFilter(day: Date, calendar: Calendar) -> Bool {
        byMonths.isEmpty || byMonths.contains(calendar.component(.month, from: day))
    }

    private func matchesMonthDayFilter(day: Date, calendar: Calendar) -> Bool {
        guard !byMonthDays.isEmpty else {
            return true
        }
        let dayNumber = calendar.component(.day, from: day)
        let daysInMonth = calendar.range(of: .day, in: .month, for: day)?.count ?? 31
        return byMonthDays.contains { monthDay in
            monthDay > 0 ? dayNumber == monthDay : dayNumber == daysInMonth + monthDay + 1
        }
    }

    private func matchesYearDayFilter(day: Date, calendar: Calendar) -> Bool {
        guard !byYearDays.isEmpty else {
            return true
        }
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: day),
              let daysInYear = calendar.range(of: .day, in: .year, for: day)?.count
        else {
            return false
        }
        return byYearDays.contains { yearDay in
            yearDay > 0 ? dayOfYear == yearDay : dayOfYear == daysInYear + yearDay + 1
        }
    }

    private func matchesWeekNumberFilter(day: Date, calendar: Calendar) -> Bool {
        guard !byWeekNumbers.isEmpty else {
            return true
        }

        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = calendar.timeZone

        let calendarYear = calendar.component(.year, from: day)
        guard isoCalendar.component(.yearForWeekOfYear, from: day) == calendarYear else {
            return false
        }

        let weekNumber = isoCalendar.component(.weekOfYear, from: day)
        let weeksInYear = isoCalendar.range(of: .weekOfYear, in: .yearForWeekOfYear, for: day)?.count ?? 53
        return byWeekNumbers.contains { week in
            week > 0 ? weekNumber == week : weekNumber == weeksInYear + week + 1
        }
    }

    private func matchesWeekdayFilter(day: Date, calendar: Calendar) -> Bool {
        guard !byWeekdays.isEmpty else {
            return true
        }
        let selectedWeekdays = Set(byWeekdays.map(\.weekday))
        return selectedWeekdays.contains(calendar.component(.weekday, from: day))
    }

    private func selectedPositionDays(
        in periodStart: Date,
        component: Calendar.Component,
        calendar: Calendar,
        positionCache: inout [String: [Date]]
    ) -> [Date] {
        let cacheKey = "\(component)-\(periodStart.timeIntervalSinceReferenceDate)"
        if let cached = positionCache[cacheKey] {
            return cached
        }

        let candidates = candidateDays(in: periodStart, component: component, calendar: calendar)
        let selected = bySetPositions.compactMap { position in
            if position > 0 {
                return candidates[safe: position - 1]
            }
            return candidates[safe: candidates.count + position]
        }
        positionCache[cacheKey] = selected
        return selected
    }

    private func candidateDays(in periodStart: Date, component: Calendar.Component, calendar: Calendar) -> [Date] {
        let range = calendar.range(of: .day, in: component, for: periodStart) ?? 1 ..< 1
        return range.compactMap { dayNumber -> Date? in
            guard let day = calendar.date(byAdding: .day, value: dayNumber - 1, to: periodStart) else {
                return nil
            }
            let weekdayAllowed = byWeekdays.isEmpty || byWeekdays.contains { specifier in
                guard specifier.ordinal != nil else {
                    return specifier.weekday == calendar.component(.weekday, from: day)
                }
                let scope: Calendar.Component = component == .year && byMonths.isEmpty ? .year : .month
                return specifier.matches(day: day, in: scope, calendar: calendar)
            }
            let monthDayAllowed = byMonthDays.isEmpty || matchesMonthDayFilter(day: day, calendar: calendar)
            let allowed = matchesMonthFilter(day: day, calendar: calendar)
                && matchesYearDayFilter(day: day, calendar: calendar)
                && matchesWeekNumberFilter(day: day, calendar: calendar)
                && weekdayAllowed
                && monthDayAllowed
            return allowed ? day : nil
        }
    }

    private static func intList(_ value: String?) -> [Int] {
        value?
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? []
    }

    private static func weekday(for token: String) -> Int? {
        switch token.uppercased() {
        case "SU": 1
        case "MO": 2
        case "TU": 3
        case "WE": 4
        case "TH": 5
        case "FR": 6
        case "SA": 7
        default: nil
        }
    }
}

private struct WeekdaySpecifier {
    let ordinal: Int?
    let weekday: Int

    init(weekday: Int) {
        ordinal = nil
        self.weekday = weekday
    }

    init?(raw: String) {
        let normalized = raw.uppercased()
        guard normalized.count >= 2,
              let weekday = Self.weekday(for: String(normalized.suffix(2)))
        else {
            return nil
        }
        let prefix = normalized.dropLast(2)
        ordinal = prefix.isEmpty ? nil : Int(prefix)
        self.weekday = weekday
    }

    func matches(day: Date, in component: Calendar.Component, calendar: Calendar) -> Bool {
        guard calendar.component(.weekday, from: day) == weekday else {
            return false
        }
        guard let ordinal else {
            return true
        }

        let matchingDays = calendar.days(containing: day, in: component).filter {
            calendar.component(.weekday, from: $0) == weekday
        }

        if ordinal > 0 {
            return matchingDays[safe: ordinal - 1].map { calendar.isDate($0, inSameDayAs: day) } ?? false
        }
        return matchingDays[safe: matchingDays.count + ordinal].map { calendar.isDate($0, inSameDayAs: day) } ?? false
    }

    private static func weekday(for token: String) -> Int? {
        switch token {
        case "SU": 1
        case "MO": 2
        case "TU": 3
        case "WE": 4
        case "TH": 5
        case "FR": 6
        case "SA": 7
        default: nil
        }
    }
}

private extension Calendar {
    func startOfWeek(containing date: Date, firstWeekday: Int) -> Date {
        var calendar = self
        calendar.firstWeekday = firstWeekday
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    func startOfWeek(containing date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? startOfDay(for: date)
    }

    func startOfMonth(containing date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? startOfDay(for: date)
    }

    func startOfYear(containing date: Date) -> Date {
        let components = dateComponents([.year], from: date)
        return self.date(from: components) ?? startOfDay(for: date)
    }

    func days(containing date: Date, in component: Calendar.Component) -> [Date] {
        let start: Date
        let count: Int
        switch component {
        case .year:
            start = startOfYear(containing: date)
            count = range(of: .day, in: .year, for: date)?.count ?? 366
        default:
            start = startOfMonth(containing: date)
            count = range(of: .day, in: .month, for: date)?.count ?? 31
        }

        return (0 ..< count).compactMap { offset in
            self.date(byAdding: .day, value: offset, to: start)
        }
    }

    func date(onSameDayAs day: Date, preservingTimeFrom timeSource: Date) -> Date? {
        let dayParts = dateComponents([.year, .month, .day], from: day)
        let timeParts = dateComponents([.hour, .minute, .second], from: timeSource)
        return date(
            from: DateComponents(
                calendar: self,
                timeZone: timeZone,
                year: dayParts.year,
                month: dayParts.month,
                day: dayParts.day,
                hour: timeParts.hour,
                minute: timeParts.minute,
                second: timeParts.second
            )
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

import Foundation

struct ScheduleDateRange {
    let start: Date
    let end: Date
    private let calendar: Calendar

    init(start: Date, end: Date, calendar: Calendar = .current) {
        self.calendar = calendar
        let normalizedStart = calendar.startOfDay(for: start)
        let normalizedEnd = calendar.startOfDay(for: end)
        self.start = min(normalizedStart, normalizedEnd)
        self.end = max(normalizedStart, normalizedEnd)
    }

    static func today(now: Date = Date(), calendar: Calendar = .current) -> ScheduleDateRange {
        let today = calendar.startOfDay(for: now)
        return ScheduleDateRange(start: today, end: today, calendar: calendar)
    }

    static func thisWeek(now: Date = Date(), calendar: Calendar = .current) -> ScheduleDateRange {
        let today = calendar.startOfDay(for: now)
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? today
        return ScheduleDateRange(start: start, end: end, calendar: calendar)
    }

    static func thisMonth(now: Date = Date(), calendar: Calendar = .current) -> ScheduleDateRange {
        let today = calendar.startOfDay(for: now)
        let start = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? today
        let end = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? today
        return ScheduleDateRange(start: start, end: end, calendar: calendar)
    }

    func contains(_ item: CalendarItem) -> Bool {
        guard let itemStart = item.displayStartDay else { return false }
        let itemEnd = item.displayEndDay ?? itemStart
        return itemStart <= end && itemEnd >= start
    }
}

enum ScheduleSearchMatcher {
    static func filteredItems(
        _ items: [CalendarItem],
        query: String,
        range: ScheduleDateRange,
        limit: Int = 100
    ) -> [CalendarItem] {
        let base = items.filter(range.contains)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return Array(base.sorted(by: sortByDateThenTitle).prefix(limit))
        }

        return base
            .compactMap { item -> (item: CalendarItem, score: Int)? in
                guard let score = score(query: trimmed, target: CalendarText.cleanName(item.summary)) else {
                    return nil
                }
                return (item, score)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return sortByDateThenTitle(lhs.item, rhs.item)
                }
                return lhs.score < rhs.score
            }
            .prefix(limit)
            .map(\.item)
    }

    static func score(query: String, target: String) -> Int? {
        let normalizedQuery = normalize(query)
        let normalizedTarget = normalize(target)

        guard !normalizedQuery.isEmpty, !normalizedTarget.isEmpty else { return nil }

        if normalizedTarget == normalizedQuery { return 0 }
        if normalizedTarget.hasPrefix(normalizedQuery) { return 1 }
        if normalizedTarget.contains(normalizedQuery) { return 2 }
        if normalizedQuery.contains(normalizedTarget) { return 3 }
        if isSubsequence(normalizedQuery, in: normalizedTarget) { return 4 }

        let distance = levenshteinDistance(normalizedQuery, normalizedTarget)
        let threshold = max(1, normalizedQuery.count / 2 + (normalizedQuery.count >= 6 ? 1 : 0))
        guard distance <= threshold else { return nil }
        return 10 + distance
    }

    static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let scalars = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    static func isSubsequence(_ query: String, in target: String) -> Bool {
        var targetIndex = target.startIndex
        for character in query {
            guard let found = target[targetIndex...].firstIndex(of: character) else {
                return false
            }
            targetIndex = target.index(after: found)
        }
        return true
    }

    static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let leftCharacters = Array(lhs)
        let rightCharacters = Array(rhs)
        if leftCharacters.isEmpty { return rightCharacters.count }
        if rightCharacters.isEmpty { return leftCharacters.count }

        var previous = Array(0 ... rightCharacters.count)
        for (leftIndex, leftCharacter) in leftCharacters.enumerated() {
            var current = Array(repeating: 0, count: rightCharacters.count + 1)
            current[0] = leftIndex + 1

            for (rightIndex, rightCharacter) in rightCharacters.enumerated() {
                let cost = leftCharacter == rightCharacter ? 0 : 1
                current[rightIndex + 1] = min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    previous[rightIndex] + cost
                )
            }
            previous = current
        }
        return previous[rightCharacters.count]
    }

    private static func sortByDateThenTitle(_ lhs: CalendarItem, _ rhs: CalendarItem) -> Bool {
        let left = lhs.startDate ?? .distantFuture
        let right = rhs.startDate ?? .distantFuture
        if left == right {
            return CalendarText.cleanName(lhs.summary) < CalendarText.cleanName(rhs.summary)
        }
        return left < right
    }
}

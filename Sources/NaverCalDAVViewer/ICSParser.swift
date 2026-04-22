import Foundation

// Converts raw iCalendar VEVENT/VTODO text from CalDAV servers into CalendarItem.
// Google Calendar API responses bypass this parser and are mapped in CalendarStore.
enum ICSParser {
    static func parseItems(from ics: String, calendarName: String) -> [CalendarItem] {
        let unfolded = unfold(ics)
        let lines = unfolded.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var items: [CalendarItem] = []
        var currentType: CalendarItemType?
        var fields: [String: String] = [:]
        var nestedComponentDepth = 0

        for raw in lines {
            let line = raw.trimmingCharacters(in: .newlines)

            if line == "BEGIN:VEVENT" {
                currentType = .event
                fields = [:]
                continue
            }
            if line == "BEGIN:VTODO" {
                currentType = .todo
                fields = [:]
                continue
            }

            if line.hasPrefix("BEGIN:") {
                if currentType != nil {
                    nestedComponentDepth += 1
                }
                continue
            }

            if line == "END:VEVENT" || line == "END:VTODO" {
                if let type = currentType {
                    items.append(makeItem(type: type, fields: fields, calendarName: calendarName))
                }
                currentType = nil
                fields = [:]
                nestedComponentDepth = 0
                continue
            }

            if line.hasPrefix("END:") {
                if nestedComponentDepth > 0 {
                    nestedComponentDepth -= 1
                }
                continue
            }

            guard currentType != nil else { continue }
            guard nestedComponentDepth == 0 else { continue }
            guard let (name, value) = splitContentLine(line) else { continue }

            let key = name.uppercased()
            if fields[key] == nil {
                fields[key] = decodeText(value)
            }
        }

        return items
    }

    private static func makeItem(type: CalendarItemType, fields: [String: String], calendarName: String) -> CalendarItem {
        let uid = fields["UID"] ?? "(no uid)"
        let summary = fields["SUMMARY"] ?? "(no title)"

        let startOrDue: String
        let endOrCompleted: String
        let startParse: (date: Date?, isAllDay: Bool)
        let endParse: (date: Date?, isAllDay: Bool)

        if type == .event {
            startOrDue = fields["DTSTART"] ?? ""
            endOrCompleted = fields["DTEND"] ?? ""
            startParse = CalendarValueParser.parseDateValue(startOrDue)
            endParse = CalendarValueParser.parseDateValue(endOrCompleted)
        } else {
            startOrDue = fields["DUE"] ?? fields["DTSTART"] ?? ""
            endOrCompleted = fields["COMPLETED"] ?? ""
            startParse = CalendarValueParser.parseDateValue(startOrDue)
            endParse = CalendarValueParser.parseDateValue(endOrCompleted)
        }

        let location = fields["LOCATION"] ?? ""
        let note = fields["DESCRIPTION"] ?? ""
        let status = fields["STATUS"] ?? ""
        let colorCode = fields["X-NAVER-CATEGORY-COLOR"] ?? "0"

        return CalendarItem(
            type: type,
            uid: uid,
            summary: summary,
            startOrDue: startOrDue,
            endOrCompleted: endOrCompleted,
            location: location,
            note: note,
            status: status,
            sourceCalendar: calendarName,
            sourceColorCode: colorCode,
            rawFields: fields
            ,
            startDate: startParse.date,
            endDate: endParse.date,
            isAllDay: startParse.isAllDay
        )
    }

    private static func unfold(_ text: String) -> String {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\r", with: "\n")

        var result: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if let last = result.last, s.hasPrefix(" ") || s.hasPrefix("\t") {
                result[result.count - 1] = last + s.dropFirst()
            } else {
                result.append(s)
            }
        }
        return result.joined(separator: "\n")
    }

    private static func splitContentLine(_ line: String) -> (String, String)? {
        guard let colon = line.firstIndex(of: ":") else {
            return nil
        }
        let left = String(line[..<colon])
        let right = String(line[line.index(after: colon)...])
        let name = left.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? left
        if name.isEmpty { return nil }
        return (name, right)
    }

    private static func decodeText(_ value: String) -> String {
        var out = value
        out = out.replacingOccurrences(of: "\\n", with: "\n")
        out = out.replacingOccurrences(of: "\\N", with: "\n")
        out = out.replacingOccurrences(of: "\\,", with: ",")
        out = out.replacingOccurrences(of: "\\;", with: ";")
        out = out.replacingOccurrences(of: "\\\\", with: "\\")
        return out
    }
}

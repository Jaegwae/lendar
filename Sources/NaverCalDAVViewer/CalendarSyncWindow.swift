import Foundation

/// Bounds network sync to the range the app can show quickly on startup.
///
/// Google `singleEvents=true` expands recurring events on the server, so a very
/// wide range can turn one repeating event into thousands of rows before the app
/// even renders. Keep startup responsive and let future range expansion be added
/// explicitly when navigation/search needs it.
struct CalendarSyncWindow {
    var pastMonths = 12
    var futureMonths = 24
    var calendar = Calendar.current

    func range(around anchor: Date) -> (start: Date, end: Date) {
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor
        let start = calendar.date(byAdding: .month, value: -pastMonths, to: month) ?? month
        let end = calendar.date(byAdding: .month, value: futureMonths + 1, to: month) ?? month
        return (start, end)
    }
}

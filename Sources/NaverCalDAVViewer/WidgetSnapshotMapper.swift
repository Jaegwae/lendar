import Foundation

/// Converts app-owned `CalendarItem` values into widget-safe snapshots.
///
/// The widget extension must not perform network/auth work. The app writes these
/// already-flattened values after sync and color changes, and the widget only reads
/// the saved snapshot.
enum WidgetSnapshotMapper {
    static func snapshots(
        from items: [CalendarItem],
        colorCode: (CalendarItem) -> String
    ) -> [WidgetEventSnapshot] {
        items.map { item in
            WidgetEventSnapshot(
                id: item.uid,
                title: item.summary,
                calendarName: item.sourceCalendar,
                startTimestamp: item.startDate?.timeIntervalSince1970 ?? 0,
                endTimestamp: item.endDate?.timeIntervalSince1970,
                isAllDay: item.isAllDay,
                location: item.location,
                note: item.note,
                status: item.derivedStatus,
                colorCode: colorCode(item)
            )
        }
    }
}

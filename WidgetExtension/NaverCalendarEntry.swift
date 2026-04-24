import WidgetKit

/// Timeline entry rendered by the widget.
///
/// The entry carries only the current render date plus already-flattened snapshot
/// items written by the app. The widget never receives account credentials.
struct NaverCalendarEntry: TimelineEntry {
    let date: Date
    let items: [WidgetEventSnapshot]
}

/// Widget timeline provider.
///
/// WidgetKit calls these methods in a constrained extension process, so all work
/// stays local: load the app-written snapshot, build one entry, and ask WidgetKit
/// to refresh roughly every 30 minutes.
struct NaverCalendarProvider: TimelineProvider {
    func placeholder(in _: Context) -> NaverCalendarEntry {
        NaverCalendarEntry(date: Date(), items: WidgetEventSnapshot.samples)
    }

    func getSnapshot(in _: Context, completion: @escaping (NaverCalendarEntry) -> Void) {
        Task {
            let items = await WidgetCalendarLoader.load()
            completion(NaverCalendarEntry(date: Date(), items: items))
        }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<NaverCalendarEntry>) -> Void) {
        Task {
            let items = await WidgetCalendarLoader.load()
            let entry = NaverCalendarEntry(date: Date(), items: items)
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// App-side widget snapshot writer. The app owns network/auth and writes a flattened
// snapshot; the widget only reads this data for stable refreshes.
enum WidgetSnapshotStore {
    static let appGroupID = "group.calendar.naver.viewer"
    static let widgetKind = "NaverCalendarWidget"

    static func save(_ items: [WidgetEventSnapshot]) throws {
        let url = localSnapshotURL()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(items)
        try data.write(to: url, options: .atomic)
    }

    static func load() -> [WidgetEventSnapshot] {
        guard let data = try? Data(contentsOf: localSnapshotURL()),
              let items = try? JSONDecoder().decode([WidgetEventSnapshot].self, from: data) else {
            return []
        }
        return items
    }

    static func localSnapshotURL() -> URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("widget-snapshot.json")
    }

    static func refreshWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

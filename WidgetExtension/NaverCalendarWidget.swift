import SwiftUI
import WidgetKit

/// Widget declaration registered with WidgetKit.
///
/// Keep this file tiny so target registration is easy to inspect. Timeline
/// generation and rendering live in separate files.
struct NaverCalendarWidget: Widget {
    let kind = "NaverCalendarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NaverCalendarProvider()) { entry in
            NaverCalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("lendar")
        .description("다가오는 일정을 바탕화면 위젯으로 보여줍니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

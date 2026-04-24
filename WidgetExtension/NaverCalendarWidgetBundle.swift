import SwiftUI
import WidgetKit

/// Widget bundle declaration. Keep behavior in NaverCalendarWidget and data loading
/// in WidgetSharedSnapshot so this file remains a minimal WidgetKit entry point.
@main
struct NaverCalendarWidgetBundle: WidgetBundle {
    var body: some Widget {
        NaverCalendarWidget()
    }
}

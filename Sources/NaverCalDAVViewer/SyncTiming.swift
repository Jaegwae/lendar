import Foundation

/// Small timing helper for sync diagnostics.
///
/// Network sync can feel slow for very different reasons: OAuth token refresh,
/// calendar-list discovery, per-calendar event fetches, or CalDAV fallback. A
/// cheap wall-clock measurement per phase makes that visible without a profiler.
struct SyncTimer {
    private let startedAt = Date()

    var milliseconds: Int {
        Int(Date().timeIntervalSince(startedAt) * 1000)
    }

    func line(_ label: String) -> String {
        "\(label): \(milliseconds)ms"
    }
}

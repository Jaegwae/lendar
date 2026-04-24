import Foundation

/// Normalizes persisted connection identity and provider routing.
///
/// The app accepts user-friendly inputs such as bare Naver IDs or Google CalDAV
/// legacy URLs, but persistence and sync dispatch need canonical values.
enum ConnectionNormalizer {
    static func username(_ username: String) -> String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || trimmed.contains("@") {
            return trimmed
        }
        return "\(trimmed)@naver.com"
    }

    static func serverURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "https://caldav.calendar.naver.com"
        }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        let normalized = withScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: normalized),
              let host = url.host?.lowercased()
        else {
            return normalized
        }

        if host == "www.google.com", url.path.lowercased().hasPrefix("/calendar/dav") {
            return "https://apidata.googleusercontent.com/caldav/v2"
        }

        if host == "calendar.google.com", url.path.lowercased().contains("calendar/dav") {
            return "https://apidata.googleusercontent.com/caldav/v2"
        }

        return normalized
    }

    static func provider(for serverURL: String, explicit: String = "caldav") -> String {
        // The settings UI supports both manual CalDAV and Google OAuth. Provider must
        // survive persistence because Google's secret is a refresh token, not a CalDAV
        // password, and CalendarStore dispatches to different network clients.
        if explicit == "google" {
            return "google"
        }

        let lowercased = serverURL.lowercased()
        if lowercased.contains("googleusercontent.com") ||
            lowercased.contains("calendar.google.com") ||
            lowercased.contains("googleapis.com") ||
            lowercased.contains("www.google.com/calendar/dav")
        {
            return "google"
        }

        return "caldav"
    }
}

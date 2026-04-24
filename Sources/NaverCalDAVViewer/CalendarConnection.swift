import Foundation

/// Persisted account model. For provider == "google", password is a refresh token;
/// for provider == "caldav", password is the CalDAV/app password.
struct CalendarConnection: Identifiable, Codable, Equatable {
    var id: String
    var provider: String = "caldav"
    var email: String
    var password: String
    var serverURL: String

    var displayEmail: String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "CalDAV 계정"
        }
        return trimmed
    }

    var displayServer: String {
        if provider == "google" {
            return "calendar.google.com"
        }
        return serverURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

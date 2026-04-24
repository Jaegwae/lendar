import Foundation

/// Path and URL helpers for CalDAV discovery/report requests.
///
/// CalDAV servers return a mix of absolute URLs, encoded paths, and relative hrefs.
/// Centralizing normalization keeps request construction consistent across
/// discovery, calendar-query, and multiget fallback paths.
enum CalDAVPath {
    static func normalizedBaseURL(_ value: String) -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        let normalized = withScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let url = URL(string: normalized),
           let host = url.host?.lowercased(),
           host == "www.google.com" && url.path.lowercased().hasPrefix("/calendar/dav") ||
           host == "calendar.google.com" && url.path.lowercased().contains("calendar/dav")
        {
            return URL(string: "https://apidata.googleusercontent.com/caldav/v2")!
        }

        return URL(string: normalized) ??
            URL(string: "https://caldav.calendar.naver.com")!
    }

    static func url(from path: String, baseURL: URL) -> URL {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        let normalized = normalize(path)
        let basePath = normalize(baseURL.path)
        if basePath != "/", normalized.hasPrefix(basePath),
           var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        {
            components.path = normalized
            return components.url ?? baseURL
        }
        return baseURL.appendingPathComponent(String(normalized.dropFirst()))
    }

    static func normalize(_ input: String) -> String {
        if input.hasPrefix("http://") || input.hasPrefix("https://") {
            if let url = URL(string: input), let path = url.path.removingPercentEncoding {
                return path.hasPrefix("/") ? path : "/\(path)"
            }
        }

        let plain = input.removingPercentEncoding ?? input
        if plain.hasPrefix("/") {
            return plain
        }
        return "/\(plain)"
    }

    static func fallbackPrincipalPath(username: String) -> String {
        let idOnly = idOnlyUsername(username)
        return "/principals/users/\(encodedPathSegment(idOnly))"
    }

    static func fallbackCalendarHomePath(username: String) -> String {
        let idOnly = idOnlyUsername(username)
        return "/calendars/users/\(encodedPathSegment(idOnly))/"
    }

    static func encodedPathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    static func parentPath(of path: String) -> String? {
        let normalized = normalize(path)
        guard let slashIndex = normalized.lastIndex(of: "/"), slashIndex > normalized.startIndex else {
            return nil
        }
        return String(normalized[..<slashIndex]) + "/"
    }

    private static func idOnlyUsername(_ username: String) -> String {
        username.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? username
    }
}

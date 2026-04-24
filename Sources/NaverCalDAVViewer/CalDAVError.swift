import Foundation

/// Errors surfaced by CalDAV discovery, HTTP, parsing, and diagnostic paths.
///
/// Diagnostic errors intentionally carry the accumulated request log so the settings
/// UI can explain which discovery step failed.
enum CalDAVError: LocalizedError {
    case auth(String)
    case network(String)
    case parse(String)
    case http(Int, String)
    case diagnostic(String, [String])

    var errorDescription: String? {
        switch self {
        case let .auth(message):
            return "Auth error: \(message)"
        case let .network(message):
            return "Network error: \(message)"
        case let .parse(message):
            return "Parse error: \(message)"
        case let .http(status, body):
            if body.isEmpty {
                return "HTTP error: status=\(status)"
            }
            return "HTTP error: status=\(status), body=\(body.prefix(300))"
        case let .diagnostic(message, diagnostics):
            return ([message] + diagnostics).joined(separator: "\n")
        }
    }
}

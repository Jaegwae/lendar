import Foundation

/// Result of a full multi-account sync pass.
///
/// `CalendarStore` consumes this single value on the main actor to update UI state
/// atomically after background CalDAV/Google work completes.
struct CalendarSyncResult {
    let items: [CalendarItem]
    let diagnostics: [String]
    let connectionErrors: [String: String]
    let connectionCalendarCounts: [String: Int]
}

/// Account-level sync coordinator.
///
/// This service keeps network provider branching out of `CalendarStore`: Google
/// accounts route to `GoogleCalendarClient`, all other accounts route to
/// `CalDAVClient`. Per-account failures are captured in the result instead of
/// aborting the whole sync, which preserves successful calendars when one account
/// is broken.
enum CalendarSyncService {
    static func fetchItems(
        connections: [CalendarConnection],
        rangeStart: Date,
        rangeEnd: Date
    ) async -> CalendarSyncResult {
        var mergedItems: [CalendarItem] = []
        var mergedDiagnostics: [String] = []
        var connectionErrors: [String: String] = [:]
        var connectionCalendarCounts: [String: Int] = [:]

        let outcomes = await fetchAccountsInParallel(
            connections: connections,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )

        for outcome in outcomes.sorted(by: { $0.index < $1.index }) {
            mergedDiagnostics.append("[\(outcome.connection.displayEmail)]")
            mergedDiagnostics.append("Account sync total: \(outcome.elapsedMilliseconds)ms")

            switch outcome.value {
            case let .success(result):
                mergedDiagnostics.append(contentsOf: result.diagnostics)
                connectionCalendarCounts[outcome.connection.id] = result.items.count
                connectionErrors[outcome.connection.id] = nil

                let source = outcome.connection.displayServer
                mergedItems.append(contentsOf: result.items.map { item in
                    item.withSourceCalendar(
                        CalendarText.calendarKey(
                            source: source,
                            calendar: item.sourceCalendar
                        )
                    )
                })
            case let .failure(error):
                mergedDiagnostics.append("동기화 실패: \(error.localizedDescription)")
                connectionCalendarCounts[outcome.connection.id] = 0
                connectionErrors[outcome.connection.id] = error.localizedDescription

                if let diagnosticError = error as? CalDAVError,
                   case let .diagnostic(_, entries) = diagnosticError
                {
                    mergedDiagnostics.append(contentsOf: entries)
                }
            }
        }

        return CalendarSyncResult(
            items: mergedItems.sorted(by: CalendarItemOrdering.compareItems),
            diagnostics: mergedDiagnostics,
            connectionErrors: connectionErrors,
            connectionCalendarCounts: connectionCalendarCounts
        )
    }

    private static func fetchAccountsInParallel(
        connections: [CalendarConnection],
        rangeStart: Date,
        rangeEnd: Date
    ) async -> [AccountSyncOutcome] {
        await withTaskGroup(of: AccountSyncOutcome.self) { group in
            for (index, connection) in connections.enumerated() {
                group.addTask {
                    let timer = SyncTimer()
                    do {
                        let result = try await fetchConnection(connection, rangeStart: rangeStart, rangeEnd: rangeEnd)
                        return AccountSyncOutcome(
                            index: index,
                            connection: connection,
                            elapsedMilliseconds: timer.milliseconds,
                            value: .success(result)
                        )
                    } catch {
                        return AccountSyncOutcome(
                            index: index,
                            connection: connection,
                            elapsedMilliseconds: timer.milliseconds,
                            value: .failure(error)
                        )
                    }
                }
            }

            var outcomes: [AccountSyncOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }
    }

    private static func fetchConnection(
        _ connection: CalendarConnection,
        rangeStart: Date,
        rangeEnd: Date
    ) async throws -> FetchResult {
        let provider = ConnectionNormalizer.provider(
            for: connection.serverURL,
            explicit: connection.provider
        )
        if provider == "google" {
            return try await GoogleCalendarClient(
                email: connection.email,
                refreshToken: connection.password
            )
            .fetchCalendarItems(rangeStart: rangeStart, rangeEnd: rangeEnd)
        }

        return try await CalDAVClient(
            username: connection.email,
            appPassword: connection.password,
            serverURL: connection.serverURL
        )
        .fetchCalendarItems(rangeStart: rangeStart, rangeEnd: rangeEnd)
    }
}

private struct AccountSyncOutcome {
    let index: Int
    let connection: CalendarConnection
    let elapsedMilliseconds: Int
    let value: Result<FetchResult, Error>
}

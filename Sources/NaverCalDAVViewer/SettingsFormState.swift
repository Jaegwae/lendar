import Foundation

/// Local form state for the settings account editor.
///
/// The SwiftUI sheet owns one mutable value and binds fields to it. Keeping
/// validation and reset logic here prevents `SettingsSheet` from mixing layout
/// code with account-editing state rules.
struct SettingsFormState {
    static let defaultServerURL = "https://caldav.calendar.naver.com"

    var email = ""
    var password = ""
    var serverURL = defaultServerURL
    var mode: SettingsMode = .list
    var selectedConnectionID: String?
    var addMethod: AddMethod?

    var canSaveManualConnection: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !password.isEmpty &&
            !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isEditing: Bool {
        mode != .list
    }

    var shouldShowAddMethodChooser: Bool {
        mode == .add && addMethod == nil
    }

    mutating func prepareAdd() {
        selectedConnectionID = nil
        email = ""
        password = ""
        serverURL = Self.defaultServerURL
        addMethod = nil
        mode = .add
    }

    mutating func prepareEdit(_ connection: CalendarConnection) {
        selectedConnectionID = connection.id
        email = connection.email
        password = connection.password
        serverURL = connection.serverURL
        addMethod = .emailServer
        mode = .edit
    }

    mutating func reset(from connection: CalendarConnection?) {
        if let connection {
            email = connection.email
            password = connection.password
            serverURL = connection.serverURL
        } else {
            email = ""
            password = ""
            serverURL = Self.defaultServerURL
        }
    }

    mutating func closeEditor(selectedConnection: CalendarConnection?) {
        mode = .list
        selectedConnectionID = nil
        addMethod = nil
        reset(from: selectedConnection)
    }

    func manualConnection() -> CalendarConnection {
        CalendarConnection(
            id: mode == .edit ? (selectedConnectionID ?? UUID().uuidString) : UUID().uuidString,
            provider: "caldav",
            email: email,
            password: password,
            serverURL: serverURL
        )
    }
}

enum SettingsMode {
    case list
    case add
    case edit
}

enum AddMethod {
    case emailServer
}

@testable import NaverCalDAVViewer
import XCTest

final class SettingsFormStateTests: XCTestCase {
    func testPrepareAddResetsFieldsAndShowsMethodChooser() {
        var state = SettingsFormState(
            email: "old@example.com",
            password: "old",
            serverURL: "https://old.example.com",
            mode: .edit,
            selectedConnectionID: "old",
            addMethod: .emailServer
        )

        state.prepareAdd()

        XCTAssertEqual(state.email, "")
        XCTAssertEqual(state.password, "")
        XCTAssertEqual(state.serverURL, SettingsFormState.defaultServerURL)
        XCTAssertEqual(state.mode, .add)
        XCTAssertNil(state.selectedConnectionID)
        XCTAssertNil(state.addMethod)
        XCTAssertTrue(state.shouldShowAddMethodChooser)
    }

    func testPrepareEditCopiesConnectionIntoManualForm() {
        let connection = CalendarConnection(
            id: "account",
            provider: "caldav",
            email: "demo@example.com",
            password: "secret",
            serverURL: "https://caldav.example.com"
        )
        var state = SettingsFormState()

        state.prepareEdit(connection)

        XCTAssertEqual(state.selectedConnectionID, "account")
        XCTAssertEqual(state.email, "demo@example.com")
        XCTAssertEqual(state.password, "secret")
        XCTAssertEqual(state.serverURL, "https://caldav.example.com")
        XCTAssertEqual(state.mode, .edit)
        XCTAssertEqual(state.addMethod, .emailServer)
        XCTAssertFalse(state.shouldShowAddMethodChooser)
    }

    func testManualConnectionUsesExistingIDWhenEditing() {
        var state = SettingsFormState()
        state.mode = .edit
        state.selectedConnectionID = "existing"
        state.email = "demo@example.com"
        state.password = "secret"
        state.serverURL = "https://caldav.example.com"

        let connection = state.manualConnection()

        XCTAssertEqual(connection.id, "existing")
        XCTAssertEqual(connection.provider, "caldav")
        XCTAssertEqual(connection.email, "demo@example.com")
        XCTAssertEqual(connection.password, "secret")
        XCTAssertEqual(connection.serverURL, "https://caldav.example.com")
        XCTAssertTrue(state.canSaveManualConnection)
    }

    func testValidationRequiresEmailPasswordAndServer() {
        var state = SettingsFormState()

        state.email = "demo@example.com"
        state.password = "secret"
        state.serverURL = ""

        XCTAssertFalse(state.canSaveManualConnection)

        state.serverURL = "https://caldav.example.com"

        XCTAssertTrue(state.canSaveManualConnection)
    }
}

import XCTest

/// First launch against the local Supabase stack: name → new list → share the room with a password.
/// Opt-in: needs `supabase start`; run with `TEST_RUNNER_RUN_INTEGRATION=1 xcodebuild test …`.
final class WelcomeFlowTests: XCTestCase {
    @MainActor
    func testStartAListAndShareTheRoom() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_INTEGRATION"] != nil, "set TEST_RUNNER_RUN_INTEGRATION=1")

        let app = XCUIApplication()
        app.launchArguments = ["-signOutOnLaunch"]
        app.launch()

        let name = app.textFields["Your name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "welcome screen")
        name.tap()
        name.typeText("Gus")
        app.buttons["Start a new list"].tap()
        XCTAssertTrue(app.staticTexts["Nothing to buy"].waitForExistence(timeout: 15), "guest user created, list ready")

        app.buttons["People"].tap()
        app.buttons["Share room"].tap()
        let password = app.textFields["At least 4 characters"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("pao-de-queijo")
        app.buttons["Save password"].tap()

        // Selectable text isn't always a StaticText, so match by label regardless of element type.
        let shownPassword = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'pao-de-queijo'")).firstMatch
        XCTAssertTrue(shownPassword.waitForExistence(timeout: 10), "password shown for sharing")
        XCTAssertTrue(app.buttons["Send to partner"].exists)
    }

    @MainActor
    func testCreateAccountFromWelcome() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_INTEGRATION"] != nil, "set TEST_RUNNER_RUN_INTEGRATION=1")

        let app = XCUIApplication()
        app.launchArguments = ["-signOutOnLaunch"]
        app.launch()

        XCTAssertTrue(app.buttons["Create account"].waitForExistence(timeout: 10), "welcome screen")
        app.buttons["Create account"].tap()

        let email = "ui\(Int(Date().timeIntervalSince1970))@example.com"
        let name = app.textFields["account.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Ana")
        app.textFields["account.email"].tap()
        app.textFields["account.email"].typeText(email)
        let password = app.secureTextFields["account.password"]
        password.tap()
        password.typeText("secret123")
        app.buttons["Create"].tap()

        XCTAssertTrue(app.staticTexts["Nothing to buy"].waitForExistence(timeout: 15), "account created, list ready")

        // The first sync can re-render the list right after it appears, which closes an open menu.
        let settings = app.buttons["Settings"]
        for _ in 0..<3 where !settings.exists {
            app.buttons["People"].tap()
            _ = settings.waitForExistence(timeout: 3)
        }
        settings.tap()
        // LabeledContent rows are exposed as one combined element ("Signed in as, <email>").
        let emailRow = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", email)).firstMatch
        XCTAssertTrue(emailRow.waitForExistence(timeout: 5), "Settings shows the account email")
    }
}

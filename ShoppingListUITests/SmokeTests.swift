import XCTest

/// The core shopping loop, end to end, against the in-memory demo backend (`-uiTesting`).
final class SmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAddCheckAndClearCart() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Nothing to buy"].waitForExistence(timeout: 5), "starts empty")

        let field = app.textFields["Add an item"]
        field.tap()
        field.typeText("Milk\n")
        field.typeText("Bananas\n")
        field.typeText("Bread\n")

        let milk = item("Milk", in: app)
        XCTAssertTrue(milk.waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(item("Bananas", in: app).exists)
        XCTAssertTrue(item("Bread", in: app).exists)
        XCTAssertTrue(milk.label.contains("Dairy"), "category was guessed: \(milk.label)")

        // Dismiss the keyboard, then check Milk; it settles into "In cart".
        app.buttons["Done"].firstMatch.tap()
        milk.tap()
        let inCart = NSPredicate(format: "label CONTAINS 'in cart' AND NOT (label CONTAINS 'not in cart')")
        expectation(for: inCart, evaluatedWith: milk)
        waitForExpectations(timeout: 3)

        // Clear the cart: Milk goes away, the rest stays.
        app.buttons["Clear cart"].tap()
        XCTAssertTrue(milk.waitForNonExistence(timeout: 3))
        XCTAssertTrue(item("Bananas", in: app).exists)
    }

    @MainActor
    private func item(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "item.\(name)").firstMatch
    }
}

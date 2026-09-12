import XCTest

final class SmokeTests: XCTestCase {
    func testLaunchTabsAndDefaultPreferences() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Annonces"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Favoris"].tap()
        XCTAssertTrue(app.navigationBars["Favoris"].exists)
        app.tabBars.buttons["Réglages"].tap()
        XCTAssertTrue(app.textFields["Ville"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Ville"].value as? String, "Montmagny")
        XCTAssertEqual(app.textFields["Code postal"].value as? String, "95360")
        app.tabBars.buttons["Recherche"].tap()
        XCTAssertTrue(app.navigationBars["Recherche"].exists)
        app.tabBars.buttons["Annonces"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "ImmoFlux - Annonces"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

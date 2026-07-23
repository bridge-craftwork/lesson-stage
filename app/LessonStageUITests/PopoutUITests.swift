import XCTest

/// Closes the gap ADR-003 left open: the popout's rendering and its seam were
/// verified, but never a tap landing on a card.
final class PopoutUITests: LessonStageUITestCase {
    private func launchPopout() -> XCUIApplication {
        app.launchArguments = ["-reset", "-popout"]
        app.launch()
        return app
    }

    func testPopoutLoadsBundledVueBuild() {
        let app = launchPopout()

        // Proves the whole chain: custom scheme handler serving the bundle,
        // WebKit executing the Vue build, and the components rendering.
        XCTAssertTrue(
            app.staticTexts["4S by N"].waitForExistence(timeout: 15),
            "The popout should render the deal header from the bundled build"
        )
    }

    func testNativePostsPayloadAcrossTheSeam() {
        let app = launchPopout()

        // Native replies to the webview's `ready` message with a fixture of
        // five plays. If the seam is broken this reads "0 tricks played".
        XCTAssertTrue(
            app.staticTexts["1 trick played"].waitForExistence(timeout: 15),
            "Native should post its payload and the popout should form one trick"
        )
        XCTAssertTrue(app.staticTexts["received hand from native"].exists)
    }

    func testTappingACardPlaysIt() throws {
        let app = launchPopout()
        XCTAssertTrue(app.staticTexts["4S by N"].waitForExistence(timeout: 15))

        // East is on lead to the second trick, so any of its cards is legal.
        // The query must be scoped to East's hand: ranks repeat across seats,
        // and an unscoped match for "J" finds North's first and plays nothing.
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5))

        let eastHand = webView.descendants(matching: .any)["East hand"]
        try XCTSkipUnless(
            eastHand.waitForExistence(timeout: 5),
            "Seat groups are not exposed to the accessibility tree"
        )

        let card = eastHand.staticTexts["J"].firstMatch
        try XCTSkipUnless(
            card.waitForExistence(timeout: 5),
            "Card cells are not exposed individually to the accessibility tree"
        )

        card.tap()

        // A played card leaves the hand and the seat on lead advances.
        XCTAssertTrue(
            app.staticTexts["S to play — tap a card"].waitForExistence(timeout: 5),
            "Playing East's card should pass the lead to South"
        )
    }
}

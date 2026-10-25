import XCTest

/// Synthetic presentation data, rendered by the actual iOS views. No cloud requests or audio claims.
final class PromoCaptureTests:XCTestCase {
    func testCapturePresentationScreens() {
        let app=launchProduct(["--promo-capture"])
        recordScreen(app,"PromoNotesList")
        app.buttons["note.row.00000000-0000-0000-0000-000000000100"].tap()
        XCTAssertTrue(app.buttons["note.done"].waitForExistence(timeout:5))
        recordScreen(app,"PromoNoteEditor")
        app.buttons["note.back"].tap()
        tapProductTab("账本",in:app)
        XCTAssertTrue(app.staticTexts["本月结余"].waitForExistence(timeout:5))
        recordScreen(app,"PromoLedger")
        app.buttons["统计"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["支出分类"].waitForExistence(timeout:5))
        recordScreen(app,"PromoStatistics")
        tapProductTab("助理",in:app)
        XCTAssertTrue(app.buttons["chat.voiceCall"].waitForExistence(timeout:5))
        recordScreen(app,"PromoAssistant")
        app.buttons["chat.voiceCall"].tap()
        XCTAssertTrue(app.staticTexts["正在听"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["voice.call.fixtureUtterance"].exists)
        recordScreen(app,"PromoVoiceCall")
        app.buttons["voice.call.end"].tap()
    }
}

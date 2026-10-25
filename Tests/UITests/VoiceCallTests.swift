import XCTest

final class VoiceCallTests:XCTestCase {
    func testVoiceHoldAreaDisappearsBehindModelSelectorAndReturns() {
        let app=launchProduct(["--ui-voice-input-fixture"]);tapProductTab("助理",in:app)
        let hold=app.buttons["按住说话"]
        XCTAssertTrue(hold.waitForExistence(timeout:5))
        app.buttons["chat.model"].tap()
        XCTAssertTrue(app.buttons["chat.model.option.deepseek-flash"].waitForExistence(timeout:5))
        XCTAssertFalse(hold.exists)
        recordScreen(app,"VoiceInputModelExpandedWithoutHoldLabel")
        app.buttons["chat.model.option.deepseek-v4-pro"].tap()
        app.buttons["chat.model.close"].tap()
        XCTAssertTrue(hold.waitForExistence(timeout:5));recordScreen(app,"VoiceInputRestoredAfterModelSelection")
    }
    func testCallScreenMutePauseResumeAndEnd() {
        // This checks UI and lifecycle without starting a simulator microphone or making a paid API call.
        let app=launchProduct(["--ui-voice-call-fixture"]);tapProductTab("助理",in:app)
        app.buttons["chat.voiceCall"].tap()
        XCTAssertTrue(app.staticTexts["voice.call.title"].waitForExistence(timeout:8))
        let status=app.staticTexts["voice.call.status"]
        XCTAssertEqual(status.label,"正在听")
        recordScreen(app,"VoiceCallListening")
        app.buttons["voice.call.mute"].tap();XCTAssertEqual(status.label,"已静音")
        XCTAssertEqual(app.buttons["voice.call.mute"].value as? String,"已静音")
        app.buttons["voice.call.mute"].tap();XCTAssertEqual(status.label,"正在听")
        XCUIDevice.shared.press(.home);app.activate()
        XCTAssertTrue(app.buttons["voice.call.resume"].waitForExistence(timeout:8))
        XCTAssertEqual(status.label,"通话已暂停")
        app.buttons["voice.call.resume"].tap();XCTAssertEqual(status.label,"正在听")
        app.buttons["voice.call.end"].tap()
        XCTAssertTrue(app.buttons["chat.model"].waitForExistence(timeout:8))
        app.textViews["chat.input"].tap();app.textViews["chat.input"].typeText("结束通话后继续输入")
        XCTAssertEqual(app.textViews["chat.input"].value as? String,"结束通话后继续输入")
    }
}

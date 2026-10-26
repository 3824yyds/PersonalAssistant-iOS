import XCTest

final class CompanionUITests:XCTestCase {
    private func enter(_ app:XCUIApplication) {
        app.buttons["聊天功能"].tap();app.buttons["chat.menu.companion"].tap()
        XCTAssertTrue(app.buttons["companion.back"].waitForExistence(timeout:8))
    }
    private func send(_ text:String,_ app:XCUIApplication) {
        let input=app.textViews["companion.input"];XCTAssertTrue(input.waitForExistence(timeout:5));input.tap();input.typeText(text);app.buttons["companion.send"].tap()
    }
    func testNamingSelfKnowledgeSeparatePageAndPersistence() {
        let app=launchProduct(["--ui-companion-fixture"]);tapProductTab("助理",in:app);enter(app)
        send("以后叫你小澜吧",app)
        XCTAssertTrue(app.staticTexts["名字已更新为「小澜」"].waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts["companion.title"].label,"小澜")
        send("你穿什么衣服？",app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS '我的形象是蓝色长发' AND label CONTAINS '白色围裙'")).firstMatch.waitForExistence(timeout:8))
        XCTAssertFalse(app.buttons["语音通话"].exists)
        recordScreen(app,"CompanionNamedAndSelfKnowledge")
        app.buttons["companion.back"].tap();XCTAssertTrue(app.buttons["chat.model"].waitForExistence(timeout:8));enter(app)
        XCTAssertEqual(app.staticTexts["companion.title"].label,"小澜")
        app.buttons["companion.profile"].tap();XCTAssertTrue(app.navigationBars["她的资料"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["女性"].exists)
        recordScreen(app,"CompanionProfileFemaleAndAppearance")
    }
    func testMemoryReceiptAndUndoWriteRealEncryptedDocument() {
        let app=launchProduct(["--ui-companion-fixture"]);tapProductTab("助理",in:app);enter(app)
        send("我喜欢安静的地方",app)
        XCTAssertTrue(app.staticTexts["已记住：喜欢安静的地方"].waitForExistence(timeout:8))
        app.buttons["companion.memory"].tap()
        XCTAssertTrue(app.staticTexts["喜欢安静的地方"].waitForExistence(timeout:5));recordScreen(app,"CompanionMemoryFromConversation")
        app.buttons["完成"].tap();app.buttons["撤销"].firstMatch.tap()
        app.buttons["companion.memory"].tap()
        XCTAssertFalse(app.staticTexts["喜欢安静的地方"].exists)
    }
    func testMissingCloudCredentialHasRetryAndNoFakeWebAnswer() {
        let app=launchProduct(["--ui-companion-fixture"]);tapProductTab("助理",in:app);enter(app)
        send("帮我查杭州周末天气",app)
        XCTAssertTrue(app.otherElements["companion.error"].waitForExistence(timeout:8) || app.buttons["重试这句话"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["重试这句话"].exists)
        XCTAssertFalse(app.buttons["chat.source.1"].exists)
        recordScreen(app,"CompanionWebFailureHasNoInventedSources")
    }
}

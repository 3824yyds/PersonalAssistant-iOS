import XCTest

extension XCTestCase {
    func launchProduct(_ flags:[String]=[])->XCUIApplication {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","--ui-layout-fixture"]+flags;app.launch()
        if app.buttons["创建资料库"].waitForExistence(timeout:5) {
            app.secureTextFields.element(boundBy:0).tap();app.secureTextFields.element(boundBy:0).typeText("test-password-351")
            app.secureTextFields.element(boundBy:1).tap();app.secureTextFields.element(boundBy:1).typeText("test-password-351");app.buttons["创建资料库"].tap()
        }else {app.secureTextFields.firstMatch.tap();app.secureTextFields.firstMatch.typeText("test-password-351");app.buttons["解锁"].tap()}
        XCTAssertTrue(app.buttons["展开快捷操作"].waitForExistence(timeout:20));return app
    }
    func recordScreen(_ app:XCUIApplication,_ name:String) {let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    func fill(_ field:XCUIElement,_ value:String) {
        XCTAssertTrue(field.waitForExistence(timeout:5));field.tap()
        let old=(field.value as? String) ?? ""
        // Empty fields expose their placeholder as value; do not delete it.
        if old != field.placeholderValue {field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count))}
        field.typeText(value)
    }
    func sendChat(_ text:String,in app:XCUIApplication) {
        let input=app.textViews["chat.input"];XCTAssertTrue(input.waitForExistence(timeout:5));input.tap();input.typeText(text);app.buttons["发送"].tap()
    }
}
final class Build6Tests:XCTestCase {
    func testSavingPreviousResponseCreatesANoteWithoutCloudCredentials() {
        let app=launchProduct();app.buttons["助理"].firstMatch.tap();sendChat("你好",in:app)
        XCTAssertTrue(app.buttons["chat.saveNote"].waitForExistence(timeout:8))
        sendChat("帮我把上面的回答保存到备忘录",in:app)
        XCTAssertTrue(app.buttons["chat.created.note"].waitForExistence(timeout:8));recordScreen(app,"PreviousReplySavedLocallyAsNote")
    }
    func testPhotoCaptionIsHiddenAndYellowDoneSavesAndReturnsToList() {
        let app=launchProduct(["--ui-attachment-fixture"])
        app.buttons["note.row.00000000-0000-0000-0000-000000000100"].tap()
        XCTAssertTrue(app.buttons["查看照片"].waitForExistence(timeout:5));XCTAssertFalse(app.staticTexts["照片.jpg"].exists)
        recordScreen(app,"PhotoWithoutFilenameCaption")
        let body=app.textViews["note.body"];body.tap();body.typeText("\n黄色完成保存检查")
        app.buttons["note.done"].tap();XCTAssertTrue(app.buttons["展开快捷操作"].waitForExistence(timeout:8))
        app.buttons["note.row.00000000-0000-0000-0000-000000000100"].tap()
        XCTAssertTrue(((app.textViews["note.body"].value as? String) ?? "").contains("黄色完成保存检查"))
        app.buttons["关闭"].tap()
    }
    func testModelPopoverHasNoRefreshAndSelectedMarkFollowsModelName() {
        let app=launchProduct();app.buttons["助理"].firstMatch.tap();app.buttons["chat.model"].tap()
        let flash=app.buttons["DeepSeek Flash"]
        XCTAssertTrue(flash.waitForExistence(timeout:5));XCTAssertEqual(flash.value as? String,"已选择")
        XCTAssertFalse(app.buttons["刷新可用模型"].exists);recordScreen(app,"ModelSelectionTrailingCheckmark")
        app.buttons["DeepSeek Pro"].tap();app.buttons["chat.model"].tap()
        XCTAssertEqual(app.buttons["DeepSeek Pro"].value as? String,"已选择");XCTAssertEqual(app.buttons["DeepSeek Flash"].value as? String,"未选择")
        app.buttons["DeepSeek Flash"].tap()
    }
    func testChatCreatesActualNotesIncomeExpenseAndReminderAndClarifiesAccount() {
        let app=launchProduct(["--ui-action-fixture"]);app.buttons["助理"].firstMatch.tap()
        sendChat("帮我创建一个备忘录，内容是模拟器创建备忘录",in:app)
        XCTAssertTrue(app.buttons["chat.created.note"].waitForExistence(timeout:10));app.buttons["chat.created.note"].tap()
        XCTAssertTrue(app.textViews["note.body"].waitForExistence(timeout:5));XCTAssertEqual(app.textViews["note.body"].value as? String,"准备好水和运动鞋。")
        app.buttons["关闭"].tap()
        sendChat("今天午饭花了25元",in:app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS '请选择收付款账户' OR label CONTAINS '请说明使用哪个账户'")).firstMatch.waitForExistence(timeout:8))
        XCTAssertFalse(app.buttons["chat.created.expense"].exists)
        sendChat("中国工商银行",in:app);XCTAssertTrue(app.buttons["chat.created.expense"].waitForExistence(timeout:8))
        sendChat("用中国工商银行记录工资收入200元",in:app);XCTAssertTrue(app.buttons["chat.created.income"].waitForExistence(timeout:8))
        sendChat("明天早上9点提醒我喝水",in:app)
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        for name in ["允许","Allow"] {if springboard.buttons[name].waitForExistence(timeout:2) {springboard.buttons[name].tap();break}}
        if app.alerts.firstMatch.exists {let allow=app.alerts.buttons.matching(NSPredicate(format:"label == '允许' OR label == 'Allow'")).firstMatch;if allow.exists {allow.tap()}}
        XCTAssertTrue(app.buttons["chat.created.reminder"].waitForExistence(timeout:10));recordScreen(app,"ChatRealCreationReceipts")
        app.buttons["chat.created.reminder"].tap();XCTAssertTrue(app.navigationBars["编辑提醒"].waitForExistence(timeout:5));app.buttons["取消"].tap()
        app.buttons["返回"].firstMatch.tap();XCTAssertTrue(app.staticTexts["模拟器创建备忘录"].waitForExistence(timeout:8))
        app.buttons["账本"].firstMatch.tap();XCTAssertTrue(app.staticTexts["模拟器午饭"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["模拟器收入"].exists);recordScreen(app,"ChatEntriesInLedger")
        app.buttons["提醒"].firstMatch.tap();XCTAssertTrue(app.staticTexts["模拟器喝水提醒"].waitForExistence(timeout:5))
    }
}

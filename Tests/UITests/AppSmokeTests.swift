import XCTest

final class AppSmokeTests:XCTestCase {
    func testCreateVaultAndNavigateMainScreens() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","--ui-layout-fixture"]
        app.launch()
        attach(app,"UnlockFullScreen")
        if app.buttons["创建资料库"].waitForExistence(timeout:10) {
            let fields=app.secureTextFields
            XCTAssertGreaterThanOrEqual(fields.count,2)
            fields.element(boundBy:0).tap();fields.element(boundBy:0).typeText("test-password-351")
            fields.element(boundBy:1).tap();fields.element(boundBy:1).typeText("test-password-351")
            app.buttons["创建资料库"].tap()
        } else if app.buttons["解锁"].exists {
            app.secureTextFields.firstMatch.tap();app.secureTextFields.firstMatch.typeText("test-password-351");app.buttons["解锁"].tap()
        }
        XCTAssertTrue(app.buttons["展开快捷操作"].waitForExistence(timeout:20))
        attach(app,"Notes")
        app.buttons["账本"].firstMatch.tap();XCTAssertTrue(app.staticTexts["本月结余"].waitForExistence(timeout:5));attach(app,"Ledger")
        app.buttons["展开快捷操作"].tap();XCTAssertTrue(app.buttons["新建笔记"].exists);XCTAssertTrue(app.buttons["记一笔"].exists);XCTAssertTrue(app.buttons["新建提醒"].exists)
        let plus=app.buttons["收起快捷操作"].frame
        for name in ["新建笔记","记一笔","新建提醒"] {let frame=app.buttons[name].frame;XCTAssertEqual(frame.width,plus.width,accuracy:2);XCTAssertEqual(frame.midX,plus.midX,accuracy:2)}
        attach(app,"QuickActionsAligned")
        app.buttons["收起快捷操作"].tap()
        app.buttons["卡包与资产"].tap();XCTAssertTrue(app.navigationBars["卡包与资产"].waitForExistence(timeout:5));attach(app,"Wallet")
        let cards=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'wallet.card.'"))
        XCTAssertEqual(cards.count,4)
        app.buttons["查看全部"].tap()
        let firstCard=app.buttons["wallet.card.00000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(firstCard.isHittable);firstCard.tap()
        XCTAssertTrue(app.staticTexts["账户余额"].waitForExistence(timeout:5));attach(app,"WalletAttachedDetails")
        firstCard.tap()
        let lastCard=app.buttons["wallet.card.00000000-0000-0000-0000-000000000004"]
        for _ in 0..<5 {if lastCard.isHittable {break};app.swipeUp()}
        XCTAssertTrue(lastCard.isHittable);attach(app,"WalletFourthCard")
        app.buttons["完成"].firstMatch.tap()
        app.buttons["提醒"].firstMatch.tap();attach(app,"Reminders")
        app.buttons["助理"].firstMatch.tap();XCTAssertTrue(app.staticTexts["今天想聊点什么？"].waitForExistence(timeout:5));attach(app,"Assistant")
        let input=app.descendants(matching:.any).matching(identifier:"chat.input").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout:5));XCTAssertTrue(input.isHittable);input.tap();input.typeText("1200")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5));XCTAssertTrue(input.isHittable);XCTAssertTrue(app.buttons["发送"].isHittable)
        XCTAssertLessThanOrEqual(input.frame.maxY,app.keyboards.firstMatch.frame.minY+2)
        attach(app,"AssistantKeyboardVisibleInput")
        app.buttons["历史对话"].tap();XCTAssertTrue(app.navigationBars["历史对话"].waitForExistence(timeout:5));app.buttons["完成"].firstMatch.tap()
        app.buttons["个人详情"].tap()
        app.buttons.containing(.staticText,identifier:"个人头像").firstMatch.tap()
        XCTAssertTrue(app.buttons["使用小熊头像"].waitForExistence(timeout:5));app.buttons["使用小熊头像"].tap();attach(app,"ProfileAvatarPicker")
    }
    func attach(_ app:XCUIApplication,_ name:String) {let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)}
}

import XCTest

final class AppSmokeTests:XCTestCase {
    func testCreateVaultAndNavigateMainScreens() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN"]
        app.launch()
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
        app.buttons["收起快捷操作"].tap()
        app.buttons["卡包与资产"].tap();XCTAssertTrue(app.navigationBars["卡包与资产"].waitForExistence(timeout:5));attach(app,"Wallet")
        app.buttons["完成"].firstMatch.tap()
        app.buttons["提醒"].firstMatch.tap();attach(app,"Reminders")
        app.buttons["助理"].firstMatch.tap();XCTAssertTrue(app.staticTexts["今天想聊点什么？"].waitForExistence(timeout:5));attach(app,"Assistant")
    }
    func attach(_ app:XCUIApplication,_ name:String) {let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)}
}

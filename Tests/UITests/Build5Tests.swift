import XCTest

final class Build5Tests:XCTestCase {
    private func launch()->XCUIApplication {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","--ui-layout-fixture","--ui-debt-fixture"];app.launch()
        if app.buttons["创建资料库"].waitForExistence(timeout:5) {
            app.secureTextFields.element(boundBy:0).tap();app.secureTextFields.element(boundBy:0).typeText("test-password-351")
            app.secureTextFields.element(boundBy:1).tap();app.secureTextFields.element(boundBy:1).typeText("test-password-351");app.buttons["创建资料库"].tap()
        } else {app.secureTextFields.firstMatch.tap();app.secureTextFields.firstMatch.typeText("test-password-351");app.buttons["解锁"].tap()}
        XCTAssertTrue(app.buttons["展开快捷操作"].waitForExistence(timeout:20));return app
    }
    private func replace(_ field:XCUIElement,_ value:String) {
        XCTAssertTrue(field.waitForExistence(timeout:5));field.tap()
        let original=(field.value as? String) ?? ""
        field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:original.count)+value)
    }
    private func attach(_ app:XCUIApplication,_ name:String) {let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)}
    func testDebtPartialPaymentCorrectionAndAutomaticReminder() {
        let app=launch();app.buttons["卡包与资产"].tap();app.buttons["贷款与还款"].tap()
        let row=app.buttons["loan.row.00000000-0000-0000-0000-000000000201"];XCTAssertTrue(row.waitForExistence(timeout:5));row.tap()
        app.buttons["loan.edit"].tap();XCTAssertTrue(app.textFields["loan.name"].waitForExistence(timeout:5));app.buttons["取消"].tap()
        let editorClosed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:app.textFields["loan.name"])
        XCTAssertEqual(XCTWaiter.wait(for:[editorClosed],timeout:5),.completed)
        let installment=app.buttons["loan.installment.1"]
        XCTAssertTrue(installment.waitForExistence(timeout:5))
        installment.tap()
        replace(app.textFields["loan.payment.principal"],"100.00");replace(app.textFields["loan.payment.interest"],"0.00");replace(app.textFields["loan.payment.fee"],"10000.00")
        app.buttons["loan.payment.save"].tap();XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout:8));XCTAssertTrue(app.alerts.firstMatch.label.contains("提示"));attach(app,"DebtInsufficientFunds");app.buttons["知道了"].tap()
        replace(app.textFields["loan.payment.fee"],"0.00");app.buttons["loan.payment.save"].tap()
        XCTAssertTrue(app.staticTexts["部分已还"].waitForExistence(timeout:8));attach(app,"DebtPartialPayment")
        for _ in 0..<3 {if app.buttons["loan.history"].isHittable {break};app.swipeDown()}
        app.buttons["loan.history"].tap()
        let payment=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'loan.payment.'")).firstMatch
        XCTAssertTrue(payment.waitForExistence(timeout:5));payment.tap();replace(app.textFields["loan.payment.principal"],"50.00");app.buttons["loan.payment.save"].tap()
        XCTAssertTrue(payment.waitForExistence(timeout:5));payment.swipeLeft();app.buttons["撤销"].tap();app.buttons["撤销还款并恢复余额"].tap()
        XCTAssertTrue(app.staticTexts["还没有实际还款记录"].waitForExistence(timeout:8))
        app.navigationBars["还款记录"].buttons.firstMatch.tap();app.navigationBars["消费贷示例"].buttons.firstMatch.tap();app.navigationBars["贷款与还款"].buttons.firstMatch.tap()
        app.buttons["资产与负债"].tap();XCTAssertTrue(app.buttons["assets.addDebt"].waitForExistence(timeout:5));app.buttons["assets.addDebt"].tap()
        app.textFields["负债名称"].tap();app.textFields["负债名称"].typeText("朋友借款");app.textFields["待还金额"].tap();app.textFields["待还金额"].typeText("500");app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["朋友借款"].waitForExistence(timeout:8));attach(app,"UnifiedAssetsAndDebt")
        app.navigationBars["资产与负债"].buttons.firstMatch.tap();app.buttons["完成"].firstMatch.tap();app.buttons["提醒"].firstMatch.tap()
        let reminder=app.staticTexts["消费贷示例 · 第1期还款"];XCTAssertTrue(reminder.waitForExistence(timeout:8));attach(app,"AutomaticDebtReminders");reminder.tap();XCTAssertTrue(app.buttons["loan.edit"].waitForExistence(timeout:5))
    }
    func testNotesToolsAndConditionalImageEntry() {
        let app=launch();app.buttons["展开快捷操作"].tap();app.buttons["新建笔记"].tap()
        let title=app.descendants(matching:.any).matching(identifier:"note.title").firstMatch;title.tap();title.typeText("备忘录工具检查")
        let body=app.textViews["note.body"];XCTAssertTrue(body.waitForExistence(timeout:5));body.tap();body.typeText("记录今天的安排。")
        app.buttons["格式"].tap();XCTAssertTrue(app.buttons["粗体"].waitForExistence(timeout:5));app.buttons["粗体"].tap()
        app.buttons["添加清单"].tap();let check=app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH 'note.checklist.'")).firstMatch;XCTAssertTrue(check.waitForExistence(timeout:5));check.tap();check.typeText("买牛奶")
        app.buttons["勾选清单"].firstMatch.tap();app.buttons["添加表格"].tap();XCTAssertTrue(app.navigationBars["表格"].waitForExistence(timeout:5));let cell=app.descendants(matching:.any).matching(identifier:"note.table.0.0").firstMatch;cell.tap();cell.typeText("项目");app.navigationBars["表格"].buttons["完成"].tap()
        app.buttons["手绘"].tap();XCTAssertTrue(app.navigationBars["手绘"].waitForExistence(timeout:5));attach(app,"NativeDrawingTools")
        let canvas=app.descendants(matching:.any).matching(identifier:"note.drawing.canvas").firstMatch;XCTAssertTrue(canvas.waitForExistence(timeout:5))
        canvas.coordinate(withNormalizedOffset:CGVector(dx:0.2,dy:0.3)).press(forDuration:0.1,thenDragTo:canvas.coordinate(withNormalizedOffset:CGVector(dx:0.65,dy:0.5)))
        app.navigationBars["手绘"].buttons["完成"].tap();XCTAssertTrue(app.buttons["编辑手绘"].waitForExistence(timeout:5));XCTAssertFalse(app.staticTexts["手绘.pkdrawing"].exists);attach(app,"NativeNoteStructuredContent")
        app.buttons["note.done"].tap();XCTAssertTrue(app.staticTexts["备忘录工具检查"].waitForExistence(timeout:10));attach(app,"NotesGroupedList")
        app.buttons["助理"].firstMatch.tap();app.buttons["聊天功能"].tap();XCTAssertTrue(app.buttons["chat.menu.photos"].waitForExistence(timeout:5));app.buttons["chat.menu.preferences"].tap()
        for title in ["基本风格和语调","亲切程度","热情程度","表情符号","可视化回答"] {XCTAssertTrue(app.staticTexts[title].exists)}
        attach(app,"ChatResponsePreferences");app.buttons["保存"].tap()
        app.buttons["chat.model"].tap();app.buttons["chat.model.option.deepseek-v4-pro"].tap();app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap();app.buttons["聊天功能"].tap();XCTAssertFalse(app.buttons["chat.menu.photos"].exists);app.buttons["chat.menu.new"].tap()
        app.buttons["chat.model"].tap();app.buttons["chat.model.option.deepseek-flash"].tap();app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap();app.buttons["chat.mode.finance"].tap()
        XCTAssertEqual(app.buttons["chat.mode.finance"].label,"财务咨询")
        let duplicateHeadings=app.staticTexts.matching(NSPredicate(format:"label == '财务咨询'")).allElementsBoundByIndex.filter {$0.frame.minY<app.frame.height/2}
        XCTAssertTrue(duplicateHeadings.isEmpty,"No duplicate mode title in the header")
        attach(app,"FinanceWithoutDuplicateTitle")
    }
}

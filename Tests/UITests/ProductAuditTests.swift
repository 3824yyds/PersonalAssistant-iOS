import XCTest

/// User-flow audit. Observations of existing behavior are attached for review;
/// recommendations are not silently turned into product changes.
final class ProductAuditTests:XCTestCase {
    private func launch()->XCUIApplication {launchProduct(["--ui-audit-fixture"])}
    private func findButton(_ app:XCUIApplication,_ prefix:String)->XCUIElement {app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@",prefix)).firstMatch}
    private func menu(_ app:XCUIApplication,_ label:String) {
        let button=app.buttons[label];XCTAssertTrue(button.waitForExistence(timeout:5))
        // XCTest can choose a corner outside a circular menu's actual hit shape.
        button.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
    }
    private func reveal(_ element:XCUIElement,in app:XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable {return}
            let up = !element.exists || element.frame.midY>app.frame.midY
            let start=app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:up ? 0.72:0.42))
            let end=app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:up ? 0.48:0.65))
            start.press(forDuration:0.1,thenDragTo:end)
        }
        XCTAssertTrue(element.isHittable)
    }
    private func choose(_ app:XCUIApplication,_ label:String,_ value:String) {
        let picker=findButton(app,label);reveal(picker,in:app);picker.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        let options=app.descendants(matching:.any).matching(NSPredicate(format:"label == %@ OR identifier == %@",value,value))
        XCTAssertTrue(options.firstMatch.waitForExistence(timeout:5))
        guard let option=options.allElementsBoundByIndex.first(where:{$0.isHittable}) else {XCTFail("选项没有可点击元素："+value);return}
        option.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
    }
    private func tools(_ app:XCUIApplication) {
        app.buttons["账本"].firstMatch.tap();menu(app,"账本工具");XCTAssertTrue(app.buttons["订阅与资金规划"].waitForExistence(timeout:5));app.buttons["订阅与资金规划"].tap()
        XCTAssertTrue(app.navigationBars["财务工具"].waitForExistence(timeout:5))
    }
    private func back(_ app:XCUIApplication,_ title:String) {app.navigationBars[title].buttons.firstMatch.tap()}
    private func observation(_ text:String,_ name:String) {let a=XCTAttachment(string:text);a.name=name;a.lifetime = .keepAlways;add(a)}
    private func noteRow(_ app:XCUIApplication)->XCUIElement {app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'note.row.' AND label CONTAINS '审计笔记流程'")).firstMatch}

    func testNotesFolderPinArchiveTrashRestoreAndSearch() {
        let app=launch();menu(app,"笔记筛选");XCTAssertTrue(app.buttons["新建文件夹"].waitForExistence(timeout:5));app.buttons["新建文件夹"].tap()
        app.alerts.textFields.firstMatch.tap();app.alerts.textFields.firstMatch.typeText("审计文件夹");app.alerts.buttons["创建"].tap()
        app.buttons["展开快捷操作"].tap();app.buttons["新建笔记"].tap()
        let title=app.descendants(matching:.any).matching(identifier:"note.title").firstMatch;title.tap();title.typeText("审计笔记流程")
        app.textViews["note.body"].tap();app.textViews["note.body"].typeText("搜索归档和恢复的内容")
        app.buttons["备忘录选项"].tap();app.buttons["置顶"].tap();app.buttons["note.done"].tap()
        XCTAssertTrue(noteRow(app).waitForExistence(timeout:8));recordScreen(app,"AuditNotePinnedInFolder")
        noteRow(app).tap();app.buttons["备忘录选项"].tap();app.buttons["归档"].tap();app.buttons["note.done"].tap()
        menu(app,"笔记筛选");app.buttons["已归档"].tap();XCTAssertTrue(noteRow(app).waitForExistence(timeout:5))
        noteRow(app).press(forDuration:1);app.buttons["移出归档"].tap()
        menu(app,"笔记筛选");app.buttons["全部备忘录"].tap();XCTAssertTrue(noteRow(app).waitForExistence(timeout:5))
        noteRow(app).swipeLeft();app.buttons["删除"].tap()
        menu(app,"笔记筛选");app.buttons["最近删除"].tap();XCTAssertTrue(noteRow(app).waitForExistence(timeout:5));recordScreen(app,"AuditRecentlyDeletedNote")
        noteRow(app).swipeLeft();app.buttons["恢复"].tap();menu(app,"笔记筛选");app.buttons["全部备忘录"].tap()
        XCTAssertTrue(noteRow(app).waitForExistence(timeout:5))
        let search=app.textFields["搜索备忘录"];search.tap();search.typeText("不应有的关键词")
        XCTAssertTrue(app.staticTexts["没有找到笔记"].waitForExistence(timeout:5));app.buttons["清除搜索"].tap();XCTAssertTrue(noteRow(app).exists)
        noteRow(app).tap();recordScreen(app,"AuditRestoredNoteContent")
        app.buttons["关闭"].tap()
    }

    func testLedgerIncomeEditingStatisticsCalendarBudgetAndTransfer() {
        let app=launch();app.buttons["账本"].firstMatch.tap();app.buttons["展开快捷操作"].tap();app.buttons["记一笔"].tap()
        app.segmentedControls.buttons["收入"].tap();app.textFields["0.00"].tap();app.textFields["0.00"].typeText("50.00")
        app.textFields["这笔钱用在哪里"].tap();app.textFields["这笔钱用在哪里"].typeText("审计手动收入");app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["审计手动收入"].waitForExistence(timeout:8));app.staticTexts["审计手动收入"].tap()
        fill(app.textFields["0.00"],"60.00");app.buttons["保存"].tap();XCTAssertTrue(app.staticTexts["审计手动收入"].waitForExistence(timeout:8))
        app.buttons["统计"].firstMatch.tap();XCTAssertTrue(app.staticTexts["支出分类"].waitForExistence(timeout:5));recordScreen(app,"AuditStatistics")
        app.buttons["日历"].firstMatch.tap();recordScreen(app,"AuditCalendar")
        app.buttons["预算"].firstMatch.tap();app.buttons["设置"].tap();app.textFields["预算金额"].tap();app.textFields["预算金额"].typeText("500")
        app.buttons["保存"].tap();XCTAssertTrue(app.staticTexts["总预算"].waitForExistence(timeout:8));recordScreen(app,"AuditBudget")
        app.buttons["流水"].firstMatch.tap();app.buttons["筛选账目"].tap();app.buttons["重置筛选"].tap();app.buttons["完成"].firstMatch.tap()
        app.buttons["卡包与资产"].tap();app.buttons["全部账户与转账"].tap();app.buttons["账户转账"].tap()
        choose(app,"转出账户","中国工商银行 · CNY");choose(app,"转入账户","中国银行 · CNY")
        app.textFields["金额"].tap();app.textFields["金额"].typeText("25.00");app.buttons["确认"].tap()
        XCTAssertTrue(app.navigationBars["账户与余额"].waitForExistence(timeout:8));recordScreen(app,"AuditTransferBalances")
    }

    func testSubscriptionPaymentObservation() {
        let app=launch();tools(app);app.buttons["订阅与续费"].tap();app.buttons["添加订阅"].tap()
        app.textFields["订阅名称"].tap();app.textFields["订阅名称"].typeText("审计会员")
        app.textFields["每期金额"].tap();app.textFields["每期金额"].typeText("10.00")
        choose(app,"扣款账户","中国工商银行 · CNY");app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["审计会员"].waitForExistence(timeout:8));app.buttons["确认已付款"].tap()
        if app.buttons["确认付款并记账"].waitForExistence(timeout:5) {app.buttons["确认付款并记账"].tap();recordScreen(app,"AuditSubscriptionPaid")}
        else {
            recordScreen(app,"AuditSubscriptionPaymentButtonConflict")
            observation("点确认已付款后，付款确认没有出现。实际界面见截图及层级；保留现状，等待用户审批后修复列表按钮冲突。\n"+app.debugDescription,"ObservationSubscriptionPaymentButtonConflict")
        }
    }
    func testEnvelopeAllocationAndExpenseLinking() {
        let app=launch();tools(app);app.buttons["资金桶"].tap();app.buttons["新建资金桶"].tap()
        app.alerts.textFields.firstMatch.tap();app.alerts.textFields.firstMatch.typeText("审计旅行桶");app.alerts.buttons["创建"].tap()
        XCTAssertTrue(app.staticTexts["审计旅行桶"].waitForExistence(timeout:8));app.buttons["分配 / 释放"].tap()
        app.alerts.textFields.firstMatch.tap();app.alerts.textFields.firstMatch.typeText("100");app.alerts.buttons["确认"].tap()
        XCTAssertTrue(app.staticTexts["已分配"].waitForExistence(timeout:5));recordScreen(app,"AuditEnvelopeAllocated")
        app.buttons["关联支出"].tap();XCTAssertTrue(app.navigationBars["关联支出"].waitForExistence(timeout:5));app.staticTexts["审计午饭"].tap()
        XCTAssertTrue(app.navigationBars["资金桶"].waitForExistence(timeout:8));recordScreen(app,"AuditEnvelopeLinkedExpense")
    }

    func testSplitGroupsAndInvestmentTradingFlows() {
        let app=launch();tools(app);app.buttons["AA 分摊"].tap();app.buttons["新建 AA 账本"].tap()
        app.textFields["账本名称"].tap();app.textFields["账本名称"].typeText("审计AA")
        let memberFields=app.descendants(matching:.any).matching(NSPredicate(format:"(elementType == %d OR elementType == %d) AND (placeholderValue == %@ OR value == %@)",XCUIElement.ElementType.textField.rawValue,XCUIElement.ElementType.textView.rawValue,"成员，用逗号分开","我，"))
        fill(memberFields.firstMatch,"我,朋友")
        app.buttons["保存"].tap();XCTAssertTrue(app.staticTexts["审计AA"].waitForExistence(timeout:8));app.staticTexts["审计AA"].tap()
        recordScreen(app,"AuditSplitGroup")
        let add=findButton(app,"添加分摊");XCTAssertTrue(add.waitForExistence(timeout:5));add.tap()
        app.textFields["分摊事项"].tap();app.textFields["分摊事项"].typeText("审计聚餐")
        app.textFields["总金额"].tap();app.textFields["总金额"].typeText("100");app.buttons["平均分摊"].tap()
        choose(app,"本人收付账户","中国工商银行");app.buttons["保存"].tap();XCTAssertTrue(app.staticTexts["审计聚餐"].waitForExistence(timeout:8));recordScreen(app,"AuditSplitRecorded")
        back(app,"审计AA");back(app,"AA 分摊");app.buttons["投资持仓"].tap();app.buttons["新建投资持仓"].tap()
        app.textFields["投资名称"].tap();app.textFields["投资名称"].typeText("审计基金")
        fill(app.textFields["当前单价"],"10");app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["审计基金"].waitForExistence(timeout:8));app.staticTexts["审计基金"].tap();app.buttons["登记交易 / 分红"].tap()
        app.textFields["数量"].tap();app.textFields["数量"].typeText("10");app.textFields["成交总额 / 分红金额"].tap();app.textFields["成交总额 / 分红金额"].typeText("100")
        choose(app,"本人收付账户","中国工商银行");app.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["审计基金"].waitForExistence(timeout:8));recordScreen(app,"AuditInvestmentPurchase")
        app.buttons["更新价格"].tap();fill(app.alerts.textFields.firstMatch,"11");app.alerts.buttons["保存"].tap();recordScreen(app,"AuditInvestmentRevalued")
    }

    func testReminderCompletionAndMonthEndRecurrenceObservations() {
        let app=launch();app.buttons["提醒"].firstMatch.tap()
        let search=app.textFields["搜索提醒"];search.tap();search.typeText("审计一次性提醒");app.buttons["完成提醒"].firstMatch.tap()
        menu(app,"提醒筛选");app.buttons["查看已完成"].tap()
        XCTAssertTrue(app.staticTexts["审计一次性提醒"].waitForExistence(timeout:5));recordScreen(app,"AuditCompletedReminderBeforeReopen")
        app.buttons["完成提醒"].firstMatch.tap();recordScreen(app,"AuditCompletedReminderAfterReopen")
        observation("点击已完成提醒的勾选按钮后，标题是否仍留在已完成列表：\(app.staticTexts["审计一次性提醒"].exists)","ObservationCompletedReminderReopen")
        menu(app,"提醒筛选");app.buttons["查看已完成"].tap();app.buttons["清除搜索"].tap()
        app.textFields["搜索提醒"].tap();app.textFields["搜索提醒"].typeText("月底缴费复现")
        XCTAssertTrue(app.staticTexts["月底缴费复现"].waitForExistence(timeout:5));recordScreen(app,"AuditMonthEndBeforeCompletion")
        app.buttons["完成提醒"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS '2027' AND (label CONTAINS '3月' OR label CONTAINS 'Mar')")).firstMatch.waitForExistence(timeout:5))
        recordScreen(app,"AuditMonthEndAfterCompletion")
        observation(app.debugDescription,"ObservationMonthEndRecurrenceActualDate")
    }

    func testSettingsMemoryBackupExportAndReadOnlyToolScreens() {
        let app=launch();app.buttons["个人详情"].tap();app.buttons["云端智能"].tap()
        XCTAssertTrue(app.buttons["刷新可用模型"].waitForExistence(timeout:5));recordScreen(app,"AuditCloudSettingsNoCredentials")
        back(app,"云端智能");app.buttons["本机智能"].tap();XCTAssertTrue(app.buttons["下载模型（约 1.12 GB）"].waitForExistence(timeout:5));recordScreen(app,"AuditLocalModelNotInstalled")
        back(app,"本机智能");app.buttons["助理记忆"].tap();app.buttons["添加记忆"].tap()
        let memory=app.descendants(matching:.any).matching(identifier:"希望助理记住什么").firstMatch;memory.tap();memory.typeText("审计：喜欢简洁回答");app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["审计：喜欢简洁回答"].waitForExistence(timeout:8));recordScreen(app,"AuditMemorySaved")
        back(app,"助理记忆");let about=app.buttons["关于个人助理"];reveal(about,in:app);about.tap();XCTAssertTrue(app.navigationBars["关于"].waitForExistence(timeout:5));recordScreen(app,"AuditAboutAndPrivacy");back(app,"关于")
        let backup=app.buttons["加密备份与恢复"];reveal(backup,in:app);backup.tap()
        app.buttons["导出完整加密备份"].tap();recordScreen(app,"AuditBackupExporter")
        observation("本测试检查备份加密函数和导出入口；系统文件保存界面使用独立进程，本次不声称已完成选目录、保存文件或关闭系统界面的端到端验证。","ObservationSystemFileExporterBoundary")
    }
    func testManualLockWrongPasswordAndUnlockAgain() {
        let app=launch();app.buttons["个人详情"].tap();let lock=app.buttons["锁定资料库"];reveal(lock,in:app);lock.tap()
        XCTAssertTrue(app.buttons["解锁"].waitForExistence(timeout:8));XCTAssertFalse(app.buttons["展开快捷操作"].exists);recordScreen(app,"AuditVaultLocked")
        app.secureTextFields.firstMatch.tap();app.secureTextFields.firstMatch.typeText("wrong-password-351");app.buttons["解锁"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout:8));recordScreen(app,"AuditWrongPasswordRejected");app.buttons["知道了"].tap()
        app.secureTextFields.firstMatch.tap();app.secureTextFields.firstMatch.typeText("test-password-351");app.buttons["解锁"].tap()
        XCTAssertTrue(app.buttons["展开快捷操作"].waitForExistence(timeout:20));recordScreen(app,"AuditUnlockedAgain")
    }

    func testValidationErrorPreservationObservation() {
        let app=launch();tools(app);app.buttons["订阅与续费"].tap();app.buttons["添加订阅"].tap()
        app.textFields["订阅名称"].tap();app.textFields["订阅名称"].typeText("审计错误后保留输入")
        app.textFields["每期金额"].tap();app.textFields["每期金额"].typeText("1.234")
        choose(app,"扣款账户","中国工商银行 · CNY");app.buttons["保存"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout:8));recordScreen(app,"AuditValidationError")
        app.buttons["知道了"].tap();recordScreen(app,"AuditFormAfterValidationError")
        observation("错误提示关闭后编辑表单仍存在：\(app.textFields["订阅名称"].exists)。名称值：\(app.textFields["订阅名称"].exists ? app.textFields["订阅名称"].value as? String ?? "":"表单已离开")","ObservationValidationPreservesInput")
    }
}

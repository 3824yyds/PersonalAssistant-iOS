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
        XCTAssertFalse(app.buttons["语音通话"].isHittable)
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
        XCTAssertTrue(app.staticTexts["companion.error.message"].waitForExistence(timeout:8))
        XCTAssertTrue(app.buttons["重试这句话"].exists)
        XCTAssertFalse(app.buttons["chat.source.1"].exists)
        recordScreen(app,"CompanionWebFailureHasNoInventedSources")
    }
    func testNaturalNamingSuggestionCorrectionAndUndoKeepHeaderConsistent() {
        let app=launchProduct(["--ui-companion-fixture"]);tapProductTab("助理",in:app);enter(app)
        send("大肥鱼怎么样？",app)
        XCTAssertTrue(app.staticTexts["名字已更新为「大肥鱼」"].waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts["companion.title"].label,"大肥鱼")
        send("我说给你取名小鲸鱼",app)
        XCTAssertTrue(app.staticTexts["名字已更新为「小鲸鱼」"].waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts["companion.title"].label,"小鲸鱼")
        app.buttons["撤销"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"identifier == 'companion.title' AND label == '大肥鱼'")).firstMatch.waitForExistence(timeout:8))
        send("你叫什么名字？",app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS '我叫大肥鱼' AND label CONTAINS '呀'")).firstMatch.waitForExistence(timeout:8))
        recordScreen(app,"CompanionNaturalNamesAndUndo")
    }
    func testToneCommandsPersistAndTodayOverrideCanBeResetInProfile() {
        let app=launchProduct(["--ui-companion-fixture"]);tapProductTab("助理",in:app);enter(app)
        send("嘴再毒一点",app)
        XCTAssertTrue(app.staticTexts["好，聊天语气已改成“贴吧老哥”。"].waitForExistence(timeout:8))
        app.buttons["companion.profile"].tap();XCTAssertTrue(app.staticTexts["贴吧老哥"].waitForExistence(timeout:5));recordScreen(app,"CompanionToneProfile")
        app.buttons["完成"].tap()
        send("今天别损我",app)
        XCTAssertTrue(app.staticTexts["好，今天我收着点，陪你好好聊。"].waitForExistence(timeout:8))
        app.buttons["companion.back"].tap();enter(app);app.buttons["companion.profile"].tap()
        XCTAssertTrue(app.staticTexts["温柔一点"].waitForExistence(timeout:5));app.buttons["完成"].tap()
        send("恢复互损",app)
        XCTAssertTrue(app.staticTexts["好，聊天语气已改成“适度互损”。"].waitForExistence(timeout:8))
    }
    func testCancelAndRetryDoNotDuplicateUserMessageOrAppendLateReply() {
        let app=launchProduct(["--ui-companion-fixture","--ui-companion-slow-fixture"]);tapProductTab("助理",in:app);enter(app)
        send("这条消息检查取消和重试",app)
        XCTAssertTrue(app.buttons["停止伙伴回复"].waitForExistence(timeout:5));app.buttons["companion.send"].tap()
        app.buttons["companion.back"].tap();enter(app)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format:"label == '这条消息检查取消和重试'")).count,1)
        XCTAssertFalse(app.staticTexts["我在呢，接着聊。"].exists)
        XCTAssertTrue(app.buttons["重试这句话"].waitForExistence(timeout:5))
        app.buttons["重试这句话"].tap()
        XCTAssertTrue(app.staticTexts["我在呢，接着聊。"].waitForExistence(timeout:10))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format:"label == '这条消息检查取消和重试'")).count,1)
    }
    func testOrdinaryCompanionWithMissingKeyShowsErrorWithoutLocalFallback() {
        let app=launchProduct();tapProductTab("助理",in:app);enter(app);send("你好，今天聊点什么？",app)
        XCTAssertTrue(app.buttons["重试这句话"].waitForExistence(timeout:8))
        let error=app.staticTexts["companion.error.message"];XCTAssertTrue(error.waitForExistence(timeout:8));XCTAssertTrue(error.label.contains("DeepSeek API Key"))
        XCTAssertFalse(app.staticTexts["你好！今天想聊点什么？"].exists)
        recordScreen(app,"CompanionCloudFailureRemainsRetryable")
    }
    func testUpgradeRepairsMissedNameFromOldUserMessagesAndPreservesItAfterReopening() {
        let app=launchProduct(["--ui-companion-fixture","--ui-companion-legacy-name-fixture"]);tapProductTab("助理",in:app);enter(app)
        XCTAssertTrue(app.staticTexts["名字已更新为「大肥鱼」"].waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts["companion.title"].label,"大肥鱼")
        app.buttons["companion.back"].tap();enter(app)
        XCTAssertEqual(app.staticTexts["companion.title"].label,"大肥鱼");recordScreen(app,"CompanionRecoveredLegacyName")
    }
    func testNameProposalOnlyChangesHeaderAfterExplicitConfirmation() {
        let app=launchProduct(["--ui-companion-fixture","--ui-companion-name-proposal-fixture"]);tapProductTab("助理",in:app);enter(app)
        XCTAssertTrue(app.buttons["companion.name.confirm"].waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts["companion.title"].label,"伙伴")
        app.buttons["companion.name.confirm"].tap()
        XCTAssertTrue(app.staticTexts["名字已更新为「小鱼」"].waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts["companion.title"].label,"小鱼");XCTAssertFalse(app.buttons["companion.name.confirm"].exists)
        recordScreen(app,"CompanionConfirmedSemanticNameProposal")
    }
    func testContextWarningPreviewCancellationAndNewWindowPreserveHistoryAndMemory() {
        let app=launchProduct(["--ui-companion-fixture","--ui-companion-long-context-fixture"]);tapProductTab("助理",in:app);enter(app)
        XCTAssertTrue(app.staticTexts["companion.context.warning"].waitForExistence(timeout:8))
        XCTAssertTrue((app.buttons["companion.send"].value as? String ?? "").contains("83%"));recordScreen(app,"CompanionContextRingNearLimit")
        app.buttons["companion.context.compress"].tap()
        XCTAssertTrue(app.navigationBars["精简预览"].waitForExistence(timeout:8))
        let summary=app.textViews["companion.compression.text"];XCTAssertTrue((summary.value as? String ?? "").contains("杭州面试"));recordScreen(app,"CompanionCompressionPreview")
        app.buttons["取消"].tap();XCTAssertTrue(app.staticTexts["companion.context.warning"].waitForExistence(timeout:8))
        app.buttons["companion.context.compress"].tap();XCTAssertTrue(app.navigationBars["精简预览"].waitForExistence(timeout:8))
        app.buttons["companion.compression.confirm"].tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"companion.context.summary").firstMatch.waitForExistence(timeout:8));XCTAssertFalse(app.staticTexts["companion.context.warning"].exists)
        XCTAssertEqual(app.staticTexts["companion.title"].label,"大肥鱼")
        send("我喜欢什么样的地方，你还记得吗？",app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label CONTAINS '我记下的是' AND label CONTAINS '安静的地方'")).firstMatch.waitForExistence(timeout:8))
        app.buttons["伙伴更多功能"].tap();app.buttons["companion.windows"].tap()
        XCTAssertTrue(app.navigationBars["历史窗口"].waitForExistence(timeout:5));app.buttons["companion.window.0"].tap()
        XCTAssertTrue(app.navigationBars["窗口 1"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["窗口开头：面试计划的原话仍然保留。"].waitForExistence(timeout:5));recordScreen(app,"CompanionOriginalWindowRetained")
    }
    func testFullContextBlocksSendAndManualCompressionKeepsUnsentDraft() {
        let app=launchProduct(["--ui-companion-fixture","--ui-companion-full-context-fixture"]);tapProductTab("助理",in:app);enter(app)
        XCTAssertTrue(app.staticTexts["companion.context.warning"].waitForExistence(timeout:8))
        let input=app.textViews["companion.input"];input.tap();input.typeText("这段输入留到新窗口")
        XCTAssertFalse(app.buttons["companion.send"].isEnabled)
        XCTAssertTrue((app.buttons["companion.send"].value as? String ?? "").contains("100%"));recordScreen(app,"CompanionContextRingFull")
        app.buttons["伙伴更多功能"].tap();app.buttons["手动整理新窗口"].tap()
        XCTAssertTrue(app.navigationBars["精简预览"].waitForExistence(timeout:8))
        let summary=app.textViews["companion.compression.text"];summary.tap();summary.typeText("用户说：周六去杭州面试，需要提前准备。")
        app.buttons["companion.compression.confirm"].tap()
        XCTAssertTrue(app.textViews["companion.input"].waitForExistence(timeout:8))
        XCTAssertEqual(app.textViews["companion.input"].value as? String,"这段输入留到新窗口")
        XCTAssertTrue(app.buttons["companion.send"].isEnabled);XCTAssertFalse(app.staticTexts["companion.context.warning"].exists)
        recordScreen(app,"CompanionNewWindowPreservesDraft")
    }
}

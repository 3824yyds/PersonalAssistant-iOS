import XCTest

final class CompanionUITests:XCTestCase {
    func testRealDeliveryPipelineRendersImagesInsteadOfMetadataAndAllowsExplicitRepeat() {
        let app=launchProduct(["--ui-companion-fixture","--ui-companion-delivery-fixture"]);tapProductTab("助理",in:app);enter(app)
        XCTAssertFalse(app.staticTexts["Flash · 文字伙伴"].exists)
        app.buttons["companion.stickers"].tap();app.buttons["companion.sticker.send.hug"].tap()
        XCTAssertTrue(app.staticTexts["来，抱一下。"].waitForExistence(timeout:8))
        XCTAssertEqual(app.images.matching(identifier:"companion.sticker.image.hug").count,2)
        app.buttons["companion.stickers"].tap();send("用表情包呀",app)
        XCTAssertTrue(app.staticTexts["好，这次也用抱抱图。"].waitForExistence(timeout:8))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format:"label CONTAINS '[表情包：'")).firstMatch.exists)
        recordScreen(app,"CompanionActualStickerDeliveryWithoutMetadata")
        app.buttons["companion.back"].tap();enter(app)
        XCTAssertTrue(app.staticTexts["好，这次也用抱抱图。"].waitForExistence(timeout:5))
        XCTAssertTrue(app.images.matching(identifier:"companion.sticker.image.hug").firstMatch.exists)
    }
    func testMalePrivateIdentityAndNameAreIndependentFromFemale() {
        let app=launchProduct(["--ui-companion-fixture"]);tapProductTab("助理",in:app);openHub(app)
        app.buttons["companion.hub.male"].tap();XCTAssertTrue(app.buttons["companion.back"].waitForExistence(timeout:8))
        send("你的名字是阿川",app);XCTAssertTrue(app.staticTexts["名字已更新为「阿川」"].waitForExistence(timeout:8));XCTAssertEqual(app.staticTexts["companion.title"].label,"阿川")
        send("你是女生吗",app);XCTAssertTrue(app.staticTexts["我是男生。"].waitForExistence(timeout:5))
        app.buttons["companion.profile"].tap();XCTAssertTrue(app.navigationBars["他的资料"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["男性"].exists);recordScreen(app,"CompanionMaleProfile")
        app.buttons["完成"].tap();app.buttons["companion.back"].tap();enter(app)
        XCTAssertEqual(app.staticTexts["companion.title"].label,"伙伴")
        app.buttons["companion.back"].tap();app.buttons["companion.hub.male"].tap();XCTAssertEqual(app.staticTexts["companion.title"].label,"阿川")
    }
    func testGroupCreationBothSpeakersAndMentionedOnlyReplyPersist() {
        let app=launchProduct(["--ui-companion-fixture"]);tapProductTab("助理",in:app);createGroup(app)
        send("大家一起聊聊",app)
        XCTAssertTrue(app.staticTexts["我也在，今天想一起聊点什么？"].waitForExistence(timeout:8));XCTAssertTrue(app.staticTexts["先挑一件最想聊的，我听着。"].waitForExistence(timeout:8))
        app.buttons["companion.group.target"].tap();app.buttons["@男生伙伴"].tap();send("只让你回答",app)
        XCTAssertTrue(app.staticTexts["这轮我单独接话。"].waitForExistence(timeout:8));XCTAssertEqual(app.staticTexts.matching(identifier:"companion.speaker.female").count,1)
        recordScreen(app,"CompanionGroupWithDistinctSpeakersAndMention")
        app.buttons["companion.back"].tap();app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'companion.hub.group.'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["这轮我单独接话。"].waitForExistence(timeout:5))
    }
    func testGroupCancellationRetriesOnlyMissingMember() {
        let app=launchProduct(["--ui-companion-fixture","--ui-companion-group-slow-fixture"]);tapProductTab("助理",in:app);createGroup(app)
        send("一起讨论周末",app);XCTAssertTrue(app.staticTexts["我也在，今天想一起聊点什么？"].waitForExistence(timeout:8))
        app.buttons["companion.send"].tap();XCTAssertTrue(app.buttons["重试这句话"].waitForExistence(timeout:5));app.buttons["重试这句话"].tap()
        XCTAssertTrue(app.staticTexts["先挑一件最想聊的，我听着。"].waitForExistence(timeout:12))
        XCTAssertEqual(app.staticTexts.matching(identifier:"companion.speaker.female").count,1);XCTAssertEqual(app.staticTexts.matching(NSPredicate(format:"label == %@","一起讨论周末")).count,1)
        recordScreen(app,"CompanionGroupRetryOnlyMissingMember")
    }
    func testDeviceClockReplyWorksWithoutCloudAndDoesNotGuessACity() {
        let app=launchProduct();tapProductTab("助理",in:app);enter(app);send("现在几点了",app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format:"label BEGINSWITH '现在是'")).firstMatch.waitForExistence(timeout:8))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format:"label CONTAINS 'UTC是' OR label CONTAINS '长沙那边'")).firstMatch.exists)
        recordScreen(app,"CompanionLocalDeviceClock")
    }
    func testLearnedHabitCanBeReviewedAndRemovedInItsOwnPrivateChat() {
        let app=launchProduct(["--ui-companion-fixture"]);tapProductTab("助理",in:app);enter(app);send("以后和我聊天少用反问",app)
        XCTAssertTrue(app.staticTexts["我在呢，接着聊。"].waitForExistence(timeout:8));app.buttons["companion.profile"].tap();app.buttons["相处习惯"].tap()
        let habit=app.staticTexts["少用反问收尾，有内容再提问。"]
        XCTAssertTrue(habit.waitForExistence(timeout:5));recordScreen(app,"CompanionLearnedHabitWithUserEvidence")
        app.buttons["删除"].firstMatch.tap();let removed=expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:habit);wait(for:[removed],timeout:8)
    }
    private func openHub(_ app:XCUIApplication) {
        if app.buttons["companion.hub.female"].isHittable {return}
        app.buttons["聊天功能"].tap();app.buttons["chat.menu.companion"].tap();XCTAssertTrue(app.buttons["companion.hub.female"].waitForExistence(timeout:8))
    }
    private func createGroup(_ app:XCUIApplication) {
        openHub(app);app.buttons["companion.group.create"].tap();XCTAssertTrue(app.buttons["companion.group.confirm"].waitForExistence(timeout:5));app.buttons["companion.group.confirm"].tap()
        XCTAssertTrue(app.buttons["companion.back"].waitForExistence(timeout:8));XCTAssertEqual(app.staticTexts["companion.title"].label,"伙伴群聊")
    }
    func testPlainTextNameConfirmationFromScreenshotUpdatesHeaderAndPersists() {
        let app=launchProduct(["--ui-companion-fixture","--ui-companion-plain-name-fixture"]);tapProductTab("助理",in:app);enter(app)
        send("对的",app)
        XCTAssertTrue(app.staticTexts["名字已更新为「大肥鱼」"].waitForExistence(timeout:8))
        XCTAssertEqual(app.staticTexts["companion.title"].label,"大肥鱼")
        app.buttons["companion.back"].tap();enter(app)
        XCTAssertEqual(app.staticTexts["companion.title"].label,"大肥鱼");recordScreen(app,"CompanionPlainTextNameConfirmationFixed")
    }
    func testStickerPickerSendingAndReplyKeepDraftAndSurviveReopening() {
        let app=launchProduct(["--ui-companion-fixture","--ui-companion-sticker-fixture"]);tapProductTab("助理",in:app);enter(app)
        let input=app.textViews["companion.input"];input.tap();input.typeText("这段草稿保留🙂")
        app.buttons["companion.stickers"].tap();XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"companion.sticker.dock").firstMatch.waitForExistence(timeout:5))
        XCTAssertFalse(app.navigationBars["表情包"].exists);XCTAssertTrue(app.textViews["companion.input"].isHittable)
        recordScreen(app,"CompanionStickerPicker")
        app.buttons["companion.sticker.send.happy"].tap()
        XCTAssertTrue(app.images["companion.sticker.image.hug"].waitForExistence(timeout:8))
        XCTAssertTrue(app.images["companion.sticker.image.happy"].exists)
        XCTAssertEqual(app.textViews["companion.input"].value as? String,"这段草稿保留🙂")
        app.buttons["companion.stickers"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
        XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"companion.sticker.dock").firstMatch.exists)
        recordScreen(app,"CompanionStickerConversation")
        app.buttons["companion.back"].tap();enter(app)
        XCTAssertTrue(app.images["companion.sticker.image.hug"].waitForExistence(timeout:5))
        XCTAssertTrue(app.images["companion.sticker.image.happy"].exists)
    }
    func testCustomStickerEditorSaveSendRemoveAndHistoricalImagePersist() {
        let app=launchProduct(["--ui-companion-fixture","--ui-custom-sticker-fixture"]);tapProductTab("助理",in:app);enter(app)
        app.buttons["companion.stickers"].tap();app.buttons["companion.sticker.add"].tap()
        XCTAssertTrue(app.navigationBars["添加表情"].waitForExistence(timeout:8))
        app.textFields["companion.sticker.title"].tap();app.textFields["companion.sticker.title"].typeText("我的吃瓜")
        let meaning=app.descendants(matching:.any).matching(identifier:"companion.sticker.meaning").firstMatch
        meaning.tap();meaning.typeText("围观趣事，表示好奇")
        app.buttons["companion.sticker.save"].tap()
        let tile=app.buttons["发送我的吃瓜表情包"];XCTAssertTrue(tile.waitForExistence(timeout:8));recordScreen(app,"CompanionCustomStickerSaved")
        tile.tap();XCTAssertTrue(app.staticTexts["我在呢，接着聊。"].waitForExistence(timeout:8))
        tile.press(forDuration:1);app.buttons["移除表情"].tap()
        let gone=expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:tile);wait(for:[gone],timeout:8)
        app.buttons["companion.stickers"].tap()
        XCTAssertTrue(app.images.containing(NSPredicate(format:"label CONTAINS '我的吃瓜'")).firstMatch.waitForExistence(timeout:5))
        recordScreen(app,"CompanionCustomStickerHistoryPreserved")
        app.buttons["companion.back"].tap();enter(app)
        XCTAssertTrue(app.images.containing(NSPredicate(format:"label CONTAINS '我的吃瓜'")).firstMatch.waitForExistence(timeout:5))
    }
    func testReplyToSelectedOlderMessagePersistsInConversation() {
        let app=launchProduct(["--ui-companion-fixture","--ui-companion-quote-fixture"]);tapProductTab("助理",in:app);enter(app)
        app.staticTexts["先聊长沙计划，还是西安？"].press(forDuration:1);app.buttons["回复"].tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"companion.reply.preview").firstMatch.waitForExistence(timeout:5))
        send("这条先展开",app)
        XCTAssertTrue(app.staticTexts["收到，你是在回复这条消息，我接着这句聊。"].waitForExistence(timeout:8))
        XCTAssertFalse(app.buttons["companion.reply.cancel"].exists)
        XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH 'companion.quote.'")).firstMatch.exists)
        recordScreen(app,"CompanionQuotedReply")
        app.buttons["companion.back"].tap();enter(app)
        XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH 'companion.quote.'")).firstMatch.waitForExistence(timeout:5))
    }
    func testCancelQuotedReplyKeepsTypedDraft() {
        let app=launchProduct(["--ui-companion-fixture","--ui-companion-quote-fixture"]);tapProductTab("助理",in:app);enter(app)
        app.staticTexts["先聊长沙计划，还是西安？"].press(forDuration:1);app.buttons["回复"].tap()
        let input=app.textViews["companion.input"];input.tap();input.typeText("保留这段输入")
        app.buttons["companion.reply.cancel"].tap()
        XCTAssertEqual(input.value as? String,"保留这段输入");XCTAssertFalse(app.buttons["companion.reply.cancel"].exists)
        recordScreen(app,"CompanionCancelQuoteKeepsDraft")
    }
    func testFourDigitPINUnlockAfterWrongPINAndManualLock() {
        let app=launchProduct();tapProductTab("助理",in:app);app.buttons["个人详情"].tap()
        let lock=app.buttons["锁定资料库"]
        for _ in 0..<4 {if lock.isHittable {break};app.swipeUp()}
        lock.tap();XCTAssertTrue(app.buttons["解锁"].waitForExistence(timeout:8))
        let field=app.secureTextFields.firstMatch;field.tap();field.typeText("9999");app.buttons["解锁"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout:8));app.buttons["知道了"].tap()
        field.tap();field.typeText("0426");app.buttons["解锁"].tap()
        XCTAssertTrue(app.buttons["展开快捷操作"].waitForExistence(timeout:20));recordScreen(app,"FourDigitPINUnlocked")
    }
    func testEmojiRoundTripAndTextCommandDisableAutomaticStickers() {
        let app=launchProduct(["--ui-companion-fixture","--ui-companion-sticker-fixture"]);tapProductTab("助理",in:app);enter(app)
        send("别发表情包",app)
        XCTAssertTrue(app.staticTexts["好，接下来我只用文字回复。"].waitForExistence(timeout:8))
        send("又加班🙂👩🏽‍💻",app)
        XCTAssertTrue(app.staticTexts["我在呢，接着聊。"].waitForExistence(timeout:8))
        XCTAssertTrue(app.staticTexts["又加班🙂👩🏽‍💻"].exists)
        XCTAssertFalse(app.images["companion.sticker.image.hug"].exists)
        recordScreen(app,"CompanionEmojiAndStickerPreference")
    }
    private func enter(_ app:XCUIApplication) {
        openHub(app);app.buttons["companion.hub.female"].tap()
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
        app.buttons["companion.back"].tap();app.buttons["companion.hub.back"].tap();XCTAssertTrue(app.buttons["chat.model"].waitForExistence(timeout:8));enter(app)
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
        XCTAssertFalse(app.staticTexts["这句话还没有回复"].exists)
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
        XCTAssertFalse(app.staticTexts["这句话还没有回复"].exists)
        recordScreen(app,"CompanionNewWindowPreservesDraft")
    }
}

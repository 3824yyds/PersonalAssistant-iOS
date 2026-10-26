import XCTest
@testable import AssistantCore

final class CompanionConversationTests:XCTestCase {
    func testNaturalNamingStatementsAndCorrectionsPreserveExactName() throws {
        for q in ["我说给你取名大肥鱼","你的名字是大肥鱼","给你起名叫大肥鱼","我给你取名字叫大肥鱼","你的名字就叫大肥鱼","以后就叫你大肥鱼吧"] {
            var data=CompanionData()
            XCTAssertTrue(try CompanionRules.appendUserTurn(q,to:&data),q)
            XCTAssertEqual(data.profile.title,"大肥鱼",q)
            XCTAssertTrue(data.messages.last!.content.contains("大肥鱼"))
            XCTAssertEqual(data.messages.count,2)
            XCTAssertEqual(data.messages.last?.renamedTo,"大肥鱼")
            XCTAssertEqual(data.messages.last?.renamedFrom,"")
            XCTAssertTrue(try CompanionRules.appendUserTurn("不，就是小鲸鱼",to:&data))
            XCTAssertEqual(data.profile.name,"小鲸鱼")
            XCTAssertEqual(data.messages.last?.renamedFrom,"大肥鱼")
        }
    }
    func testScreenshotConversationUpdatesTitleAtFirstNamingSuggestion() throws {
        var data=CompanionData()
        data.messages=[CompanionMessage(role:"assistant",content:"你来啦，今天过得怎么样？也可以先给我取个名字呀。")]
        XCTAssertTrue(try CompanionRules.appendUserTurn("大肥鱼怎么样？",to:&data))
        XCTAssertEqual(data.profile.name,"大肥鱼")
        _=try CompanionRules.appendUserTurn("我说给你取名大肥鱼",to:&data)
        _=try CompanionRules.appendUserTurn("你叫什么名字？",to:&data)
        XCTAssertTrue(data.messages.last!.content.contains("我叫大肥鱼"))
        XCTAssertFalse(data.messages.last!.content.contains("还没有名字"))
        var document=Document();try data.write(to:&document)
        XCTAssertEqual(try CompanionData.read(JSONDecoder().decode(Document.self,from:document.encoded())).profile.title,"大肥鱼")
    }
    func testNamingNeedsIntentAndNeverLearnsUserOrThirdPartyIdentity() {
        let invite=[CompanionMessage(role:"assistant",content:"你想怎么叫我？")]
        for q in ["我叫大肥鱼","我朋友叫大肥鱼","他说给你取名大肥鱼","你的名字是大肥鱼吗？","如果你的名字是大肥鱼","给你取名大肥鱼还是小蓝","以后叫你小澜怎么样？","嗯","那好吧","你好","今天有点累","你是谁？","我一个人"] {
            XCTAssertNil(CompanionRules.proposedName(q,history:invite),q)
        }
        XCTAssertNil(CompanionRules.proposedName("大肥鱼"))
        XCTAssertEqual(CompanionRules.proposedName("大肥鱼",history:invite),"大肥鱼")
        XCTAssertNil(CompanionRules.proposedName("不，就是大肥鱼",history:[CompanionMessage(role:"assistant",content:"晚饭吃什么？")]))
        XCTAssertEqual(CompanionRules.proposedName("以后叫你「Blue Fish」吧"),"Blue Fish")
    }
    func testIdentityQueriesDoNotBecomeRenames() throws {
        var data=CompanionData();data.profile.name="大肥鱼"
        for q in ["你叫什么名字？","你叫啥名字？","你的名字是啥？","你名字是什么？"] {
            XCTAssertTrue(try CompanionRules.appendUserTurn(q,to:&data))
            XCTAssertEqual(data.profile.name,"大肥鱼")
            XCTAssertTrue(data.messages.last!.content.contains("大肥鱼"),q)
        }
    }
    func testPreferenceCorrectionReplacesOppositeWithoutErasingOtherPreferences() throws {
        var data=CompanionData()
        data.memories=[CompanionMemory(text:"喜欢咖啡"),CompanionMemory(text:"喜欢公园")]
        XCTAssertFalse(try CompanionRules.appendUserTurn("其实我现在不喜欢咖啡了",to:&data))
        XCTAssertEqual(Set(data.memories.map(\.text)),["不喜欢咖啡","喜欢公园"])
        XCTAssertEqual(data.messages.last?.replacedMemories?.map(\.text),["喜欢咖啡"])
        XCTAssertEqual(data.messages.last?.rememberedText,"不喜欢咖啡")
        let id=data.memories.first {$0.text=="不喜欢咖啡"}!.id
        _=try CompanionRules.appendUserTurn("我不喜欢咖啡",to:&data)
        XCTAssertEqual(data.memories.first {$0.text=="不喜欢咖啡"}!.id,id)
    }
    func testHypotheticalQuotedPastOrQualifiedPreferencesAreNotSavedAsCurrentFacts() {
        for q in ["我以前喜欢咖啡","我喜欢咖啡吗？","他说我喜欢咖啡","如果我喜欢咖啡呢","我喜欢咖啡，但也不是每天喝","我喜欢咖啡就怪了","我不喜欢咖啡，不过也不讨厌","我更喜欢什么呢？"] {
            XCTAssertNil(CompanionRules.newMemory(q),q)
        }
    }
    func testExplicitRememberHasAtomicReceiptAndUnknownDeletionIsTruthful() throws {
        var data=CompanionData()
        XCTAssertTrue(try CompanionRules.appendUserTurn("记住：周六想去公园",to:&data))
        XCTAssertEqual(data.memories.count,1)
        XCTAssertEqual(data.messages.count,2)
        XCTAssertTrue(data.messages.last!.content.contains("记住啦"))
        XCTAssertTrue(try CompanionRules.appendUserTurn("忘掉：周六想去公园",to:&data))
        XCTAssertTrue(data.memories.isEmpty)
        XCTAssertTrue(try CompanionRules.appendUserTurn("忘掉：不存在的内容",to:&data))
        XCTAssertTrue(data.messages.last!.content.contains("没找到"))
    }
    func testAmbiguousDeletionDoesNotClearMemoryAndDeletingOtherNameDoesNotRename() throws {
        var data=CompanionData();data.profile.name="大肥鱼";data.memories=[CompanionMemory(text:"喜欢公园")]
        _=try CompanionRules.appendUserTurn("忘记所有事情",to:&data)
        XCTAssertEqual(data.memories.count,1);XCTAssertEqual(data.profile.name,"大肥鱼")
    }
    func testToneCommandsAreExplicitAndTodayOverrideExpiresInUsersCalendar() throws {
        var data=CompanionData();var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:8*3600)!
        let now=Date(timeIntervalSince1970:1793012400)
        _=try CompanionRules.appendUserTurn("嘴再毒一点",to:&data,now:now,calendar:calendar)
        XCTAssertEqual(data.profile.effectiveTone(at:now),.spicy)
        _=try CompanionRules.appendUserTurn("今天别损我",to:&data,now:now,calendar:calendar)
        XCTAssertEqual(data.profile.tone,.spicy)
        XCTAssertEqual(data.profile.effectiveTone(at:now),.gentle)
        let tomorrow=try XCTUnwrap(calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:now)))
        XCTAssertEqual(data.profile.gentleUntil,tomorrow)
        XCTAssertEqual(data.profile.effectiveTone(at:tomorrow),.spicy)
        _=try CompanionRules.appendUserTurn("恢复互损",to:&data,now:now)
        XCTAssertEqual(data.profile.effectiveTone(at:now),.playful);XCTAssertNil(data.profile.gentleUntil)
        for q in ["你能嘴毒一点吗？","如果我说今天别损我","她说嘴再毒一点","贴吧老哥是什么？"] {XCTAssertNil(CompanionRules.proposedTone(q))}
    }
    func testBuild10ProfileWithoutNewFieldsRemainsReadableAndBackupKeepsTone() throws {
        let old=Data(#"{"appearance":"蓝发，白围裙。","personality":"热情","proactive":true,"web":true}"#.utf8)
        let profile=try JSONDecoder().decode(CompanionProfile.self,from:old)
        XCTAssertEqual(profile.title,"伙伴");XCTAssertEqual(profile.effectiveTone(),.playful)
        var data=CompanionData();data.profile=profile;data.profile.tone = .spicy;data.profile.gentleUntil=Date().addingTimeInterval(300)
        var d=Document();try data.write(to:&d)
        XCTAssertEqual(try CompanionData.read(JSONDecoder().decode(Document.self,from:d.encoded())),data)
    }
    func testCloudConversationCarriesCorrectionsAndDistinctRolesAcrossMultipleTurns() throws {
        var data=CompanionData();data.profile.name="大肥鱼";data.memories=[CompanionMemory(text:"喜欢安静的地方")]
        let history=[CompanionMessage(role:"user",content:"这个点吃饭？"),CompanionMessage(role:"assistant",content:"我一个人，你呢？"),CompanionMessage(role:"user",content:"我问的是吃饭时间"),CompanionMessage(role:"assistant",content:"哦，你问时间呀。")]
        let messages=CompanionConversation.messages(question:"对，为什么这么晚？",data:data,history:history)
        XCTAssertEqual(messages.count,6)
        XCTAssertEqual(messages[1]["role"] as? String,"user");XCTAssertEqual(messages[2]["role"] as? String,"assistant")
        XCTAssertEqual(messages[3]["content"] as? String,"我问的是吃饭时间")
        XCTAssertTrue((messages[0]["content"] as? String)!.contains("大肥鱼"))
        XCTAssertTrue((messages[0]["content"] as? String)!.contains("喜欢安静的地方"))
        XCTAssertEqual(messages.last?["content"] as? String,"对，为什么这么晚？")
    }
    func testLongConversationHasBoundedRecentWindowAndRetrievesOlderRelevantUserQuote() {
        var history=[CompanionMessage(role:"user",content:"下周六我的面试在杭州，想提前准备。")]
        history += (0..<120).map {CompanionMessage(role:$0%2==0 ? "user":"assistant",content:String(repeating:"填充甲乙",count:400))}
        let messages=CompanionConversation.messages(question:"杭州面试准备到哪了？",data:CompanionData(),history:history)
        XCTAssertLessThanOrEqual(messages.count,26)
        XCTAssertLessThanOrEqual(messages.dropFirst().dropLast().compactMap {$0["content"] as? String}.reduce(0) {$0+$1.count},12000)
        XCTAssertTrue((messages[0]["content"] as? String)!.contains("下周六我的面试在杭州"))
        XCTAssertFalse((messages[0]["content"] as? String)!.contains("填充甲乙"))
    }
    func testBanterExamplesMatchSelectedToneAndDistressRuleRemainsPresent() {
        for tone in CompanionTone.allCases {
            var data=CompanionData();data.profile.tone=tone
            let system=CompanionConversation.messages(question:"今天很难过",data:data,history:[])[0]["content"] as! String
            XCTAssertTrue(system.contains(tone.instruction));XCTAssertTrue(system.contains("立即收住毒舌"))
            if tone == .gentle {XCTAssertFalse(system.contains("博士毕业"))}
            XCTAssertTrue(system.contains("用户的姓名、偏好和经历属于用户"))
        }
    }
    func testRepeatedAnswersAreDetectedButShortAcknowledgementsAndNewInformationAreAllowed() {
        let history=[CompanionMessage(role:"assistant",content:"我一个人，你呢？")]
        XCTAssertTrue(CompanionRules.repeats("那我一个人，你呢？",history:history))
        XCTAssertTrue(CompanionRules.repeats("我一个人，你呢",history:history))
        XCTAssertFalse(CompanionRules.repeats("我问的是时间，刚才听岔了。",history:history))
        XCTAssertFalse(CompanionRules.repeats("嗯",history:[CompanionMessage(role:"assistant",content:"嗯")]))
        XCTAssertFalse(CompanionRules.repeats("我一个人，你呢？",history:[CompanionMessage(role:"user",content:"我一个人，你呢？")]))
    }
    func testNoWebAndProactiveInstructionsAreExplicitAndNoWholeDocumentIsSent() {
        var data=CompanionData();data.profile.web=false
        let system=CompanionConversation.messages(question:"查一下这个新梗",data:data,history:[],proactive:true)[0]["content"] as! String
        XCTAssertTrue(system.contains("联网查询已关闭"));XCTAssertTrue(system.contains("不发起搜索"))
        XCTAssertFalse(system.contains("accountId"));XCTAssertFalse(system.contains("openingCents"))
        XCTAssertTrue(CompanionRules.needsWeb("这个新词是什么梗？"))
        XCTAssertFalse(CompanionRules.needsWeb("不用联网，陪我聊聊"))
    }
    func testFullHistoryOrMemoryDoesNotSilentlyDiscardUserData() throws {
        var data=CompanionData();data.messages=(0..<999).map {_ in CompanionMessage(role:"user",content:"原文")}
        XCTAssertThrowsError(try CompanionRules.appendUserTurn("以后叫你大肥鱼吧",to:&data))
        XCTAssertNil(data.profile.name);XCTAssertEqual(data.messages.count,999)
        data=CompanionData();data.memories=(0..<200).map {CompanionMemory(text:"第\($0)条")}
        XCTAssertThrowsError(try CompanionRules.appendUserTurn("记住：第201条",to:&data))
        XCTAssertEqual(data.memories.count,200);XCTAssertTrue(data.messages.isEmpty)
    }
    func testStreamTracksFinishReasonWithoutDeltaAndDoesNotTreatItAsText() throws {
        var stream=DeepSeekStreamMessage()
        try stream.consume(Data(#"{"choices":[{"delta":{"content":"半句"}}]}"#.utf8))
        try stream.consume(Data(#"{"choices":[{"finish_reason":"length"}]}"#.utf8))
        XCTAssertEqual(stream.content,"半句");XCTAssertEqual(stream.finishReason,"length")
    }
    func testUndoingPreferenceCorrectionRestoresPreviousFactAndCannotUndoAnEditedMemory() throws {
        var data=CompanionData();let original=CompanionMemory(text:"喜欢咖啡");data.memories=[original]
        _=try CompanionRules.appendUserTurn("我不喜欢咖啡",to:&data)
        let receipt=try XCTUnwrap(data.messages.last)
        XCTAssertTrue(CompanionRules.undoMemory(receipt,in:&data));XCTAssertEqual(data.memories,[original])
        XCTAssertFalse(CompanionRules.undoMemory(receipt,in:&data))
        _=try CompanionRules.appendUserTurn("我不喜欢咖啡",to:&data)
        let next=try XCTUnwrap(data.messages.last);data.memories[0].text="不喜欢浓咖啡"
        XCTAssertFalse(CompanionRules.undoMemory(next,in:&data));XCTAssertEqual(data.memories[0].text,"不喜欢浓咖啡")
    }
    func testOnlyLatestNameReceiptCanUndoAfterCyclingBackToSameName() throws {
        var data=CompanionData()
        _=try CompanionRules.appendUserTurn("以后叫你小蓝吧",to:&data);let first=data.messages.last!
        _=try CompanionRules.appendUserTurn("以后叫你小鲸吧",to:&data)
        _=try CompanionRules.appendUserTurn("以后叫你小蓝吧",to:&data)
        XCTAssertFalse(CompanionRules.canUndoName(first,data:data))
        XCTAssertTrue(CompanionRules.canUndoName(data.messages.last!,data:data))
    }
    func testEndingConversationOrUnansweredQuestionSuppressesProactiveButNewTopicResumesIt() {
        let now=Date();var data=CompanionData()
        func can()->Bool {CompanionRules.mayInitiate(data:data,visible:true,active:true,editing:false,draft:"",busy:false,now:now,lastInteraction:now.addingTimeInterval(-31))}
        data.messages=[CompanionMessage(role:"user",content:"晚安"),CompanionMessage(role:"assistant",content:"晚安，早点休息。")]
        XCTAssertFalse(can())
        data.messages.append(CompanionMessage(role:"user",content:"嗯"));XCTAssertFalse(can())
        data.messages.append(CompanionMessage(role:"user",content:"对了，明天面试还有件事"));XCTAssertTrue(can())
        data.messages.append(CompanionMessage(role:"assistant",content:"最担心的是哪一部分？"));XCTAssertFalse(can())
    }
    func testSemanticNameProposalNeedsConfirmationAndDoesNotSurviveUnrelatedReply() throws {
        var data=CompanionData();data.messages=[CompanionMessage(role:"assistant",content:"你是想叫我小鱼吗？",nameProposal:"小鱼")]
        let proposal=data.messages.last!
        XCTAssertNil(data.profile.name)
        XCTAssertTrue(try CompanionRules.appendUserTurn("对",to:&data))
        XCTAssertEqual(data.profile.name,"小鱼")
        XCTAssertFalse(try CompanionRules.confirmNameProposal(proposal,in:&data))
        data=CompanionData();data.messages=[proposal]
        _=try CompanionRules.appendUserTurn("我再想想，今天有点累",to:&data)
        XCTAssertNil(data.profile.name);XCTAssertNil(data.messages.first?.nameProposal)
        _=try CompanionRules.appendUserTurn("好",to:&data)
        XCTAssertNil(data.profile.name)
        data=CompanionData();data.messages=[proposal]
        XCTAssertTrue(try CompanionRules.confirmNameProposal(proposal,in:&data));XCTAssertEqual(data.profile.name,"小鱼")
    }
    func testUserNameMemoryNeverChangesCompanionIdentityAndNewUserNameSupersedesOld() throws {
        var data=CompanionData();data.profile.name="大肥鱼"
        _=try CompanionRules.appendUserTurn("我叫小王",to:&data)
        _=try CompanionRules.appendUserTurn("以后叫我小李吧",to:&data)
        XCTAssertEqual(data.profile.name,"大肥鱼")
        XCTAssertEqual(data.memories.map(\.text),["用户称呼：小李"])
        XCTAssertEqual(CompanionRules.recallReply("我叫什么名字？",data:data,history:[]),"你让我叫你小李。")
        XCTAssertNil(CompanionRules.newMemory("我叫你去吃饭"))
        XCTAssertTrue(CompanionRules.recallReply("我喜欢什么？",data:data,history:[])!.contains("还没记下来"))
        _=try CompanionRules.appendUserTurn("记住：我喜欢咖啡",to:&data)
        XCTAssertTrue(CompanionRules.recallReply("我喜欢什么？",data:data,history:[])!.contains("喜欢咖啡"))
    }
    func testUpgradeRecoversMissedExplicitUserNameButNeverTheModelsInventedName() throws {
        var data=CompanionData()
        data.messages=[CompanionMessage(role:"user",content:"我说给你取名大肥鱼"),CompanionMessage(role:"assistant",content:"哈哈，那我叫阿肥。",source:"本机伙伴"),CompanionMessage(role:"user",content:"你的名字是大肥鱼"),CompanionMessage(role:"assistant",content:"我叫阿七。",source:"本机伙伴")]
        XCTAssertTrue(CompanionRules.recoverLegacyName(in:&data));XCTAssertEqual(data.profile.name,"大肥鱼")
        XCTAssertTrue(data.messages.last!.content.contains("补存"))
        data.profile.name=nil
        XCTAssertFalse(CompanionRules.recoverLegacyName(in:&data));XCTAssertNil(data.profile.name)
        data=CompanionData();data.messages=[CompanionMessage(role:"assistant",content:"我叫阿肥。",source:"本机伙伴")]
        XCTAssertFalse(CompanionRules.recoverLegacyName(in:&data));XCTAssertNil(data.profile.name)
    }
    func testUpgradeDoesNotOverrideSavedNamesOrUndoAndCancellationEvidence() {
        var data=CompanionData();data.profile.name="现有名字";data.messages=[CompanionMessage(role:"user",content:"以后叫你旧名字吧")]
        XCTAssertFalse(CompanionRules.recoverLegacyName(in:&data));XCTAssertEqual(data.profile.name,"现有名字")
        for last in [CompanionMessage(role:"assistant",content:"好呀，那我就叫旧名字啦！",source:"伙伴资料"),CompanionMessage(role:"user",content:"不要这个名字了")] {
            data=CompanionData();data.messages=[CompanionMessage(role:"user",content:"以后叫你旧名字吧"),last]
            XCTAssertFalse(CompanionRules.recoverLegacyName(in:&data));XCTAssertNil(data.profile.name)
        }
    }
}

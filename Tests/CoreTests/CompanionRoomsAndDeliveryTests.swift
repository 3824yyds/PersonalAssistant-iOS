import XCTest
@testable import AssistantCore

final class CompanionRoomsAndDeliveryTests:XCTestCase {
    let annotation="[表情包：抱抱：张开双臂，温柔地表示安慰、关心和支持]"
    func testScreenshotAnnotationBecomesPersistedImageAndNotVisibleMetadata() throws {
        var data=CompanionData()
        let result=CompanionStickerDelivery.resolve("行行，那就图来。\n"+annotation,selected:nil,question:"用表情包呀",data:data,history:[],proactive:false)
        XCTAssertNil(result.issue);XCTAssertEqual(result.id,"hug");XCTAssertEqual(result.text,"行行，那就图来。")
        data.messages=[CompanionMessage(role:"assistant",content:result.text,stickerID:result.id)]
        var document=Document();try data.write(to:&document);let restored=try CompanionData.read(document)
        XCTAssertEqual(restored.messages[0].stickerID,"hug");XCTAssertFalse(restored.messages[0].content.contains("[表情包"));XCTAssertTrue(restored.messages[0].contextText.contains("attached_sticker"))
    }
    func testSameWayAndFollowupOverrideOnlyAutomaticCooldown() {
        var data=CompanionData();let history=[CompanionMessage(role:"user",content:"抱抱",stickerID:"hug"),CompanionMessage(role:"assistant",content:"抱抱",stickerID:"hug")]
        for q in ["你就不能同样的方式抱抱我？","用表情包呀","？图在哪里"] {
            XCTAssertTrue(CompanionStickerRules.allowed("hug",question:q,data:data,history:history,proactive:false),q)
            XCTAssertEqual(CompanionStickerDelivery.preferredID(q,data:data,history:history),"hug")
        }
        XCTAssertFalse(CompanionStickerRules.allowed("hug",question:"你好",data:data,history:history,proactive:false))
        for q in ["不用表情包，文字就好","解释发个表情包是什么意思","[表情包：开心]","表情包怎么用"] {XCTAssertFalse(CompanionStickerDelivery.explicitRequest(q,history:history),q)}
        data.profile.stickers=false;XCTAssertFalse(CompanionStickerRules.allowed("hug",question:"用表情包呀",data:data,history:history,proactive:false))
        data.profile.stickers=true;data.profile.tone = .gentle;XCTAssertFalse(CompanionStickerRules.allowed("smug",question:"发得意表情包",data:data,history:history,proactive:false))
    }
    func testNoImageCannotTurnIntoFalseReceiptOrNetworkExcuse() {
        let data=CompanionData()
        XCTAssertNotNil(CompanionStickerDelivery.resolve("图应该已经跟着消息过去了，刷新一下。",selected:nil,question:"图在哪里",data:data,history:[],proactive:false).issue)
        XCTAssertNotNil(CompanionStickerDelivery.resolve("图已经发过去了。",selected:nil,question:"嗯",data:data,history:[],proactive:false).issue)
        XCTAssertNotNil(CompanionStickerDelivery.resolve("[表情包：https://evil.invalid/x.png]",selected:nil,question:"发个表情包",data:data,history:[],proactive:false).issue)
        XCTAssertNotNil(CompanionStickerDelivery.resolve("[表情包：抱抱",selected:nil,question:"你好",data:data,history:[],proactive:false).issue)
        let literal=CompanionStickerDelivery.resolve(annotation,selected:nil,question:"解释这段表情包格式",data:data,history:[],proactive:false)
        XCTAssertNil(literal.id);XCTAssertEqual(literal.text,annotation);XCTAssertNil(literal.issue)
    }
    func testOnlyActualImageCanPersistWithoutTextAndOldHistoryIsNotASendReceipt() throws {
        var data=CompanionData();let image=CompanionStickerDelivery.resolve(annotation,selected:nil,question:"抱抱",data:data,history:[],proactive:false)
        XCTAssertEqual(image.text,"");XCTAssertEqual(image.id,"hug")
        data.messages=[CompanionMessage(role:"assistant",content:"",stickerID:image.id)];XCTAssertNoThrow(try data.validate())
        data.messages=[CompanionMessage(role:"assistant",content:"")];XCTAssertThrowsError(try data.validate())
        let legacy=CompanionMessage(role:"assistant",content:"抱一下。\n"+annotation)
        let context=CompanionStickerDelivery.historyText(legacy,data:data);XCTAssertFalse(context.contains(annotation));XCTAssertTrue(context.contains("没有图片"))
        data.messages=[CompanionMessage(role:"user",content:"抱抱",stickerID:"hug")]
        let request=CompanionConversation.messages(question:"抱抱",data:data,history:[])
        XCTAssertTrue((request.last?["content"] as? String ?? "").contains("attached_sticker"))
    }
    func testDeviceTimeUsesZoneAndDateRolloverInsteadOfHistoricalCity() throws {
        let now=try XCTUnwrap(ISO8601DateFormatter().date(from:"2026-10-26T16:49:00Z")),zone=try XCTUnwrap(TimeZone(identifier:"Asia/Shanghai"))
        XCTAssertEqual(CompanionClock.reply("现在几点了？",now:now,timeZone:zone),"现在是10月27日 00:49。")
        XCTAssertEqual(CompanionClock.reply("现在几点了",now:now,timeZone:TimeZone(secondsFromGMT:0)!),"现在是10月26日 16:49。")
        XCTAssertTrue(CompanionClock.context(now:now,timeZone:zone).contains("Asia/Shanghai"));XCTAssertNil(CompanionClock.reply("伦敦现在几点"));XCTAssertNil(CompanionClock.reply("明天几点提醒我"))
        var data=CompanionData();var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
        XCTAssertTrue(try CompanionRules.appendUserTurn("现在几点了",to:&data,now:now,calendar:calendar));XCTAssertEqual(data.messages.last?.source,"设备时间");XCTAssertFalse(data.messages.last!.content.contains("UTC"))
        let ny=TimeZone(identifier:"America/New_York")!
        XCTAssertEqual(CompanionClock.formatted(ISO8601DateFormatter().date(from:"2026-11-01T05:30:00Z")!,timeZone:ny,pattern:"HH:mm"),"01:30")
        XCTAssertEqual(CompanionClock.formatted(ISO8601DateFormatter().date(from:"2026-11-01T06:30:00Z")!,timeZone:ny,pattern:"HH:mm"),"01:30")
    }
    func testMaleAndFemaleIdentityHistoryMemoryAndStickerPacksStaySeparate() throws {
        var document=Document();var female=CompanionData();female.profile.name="大肥鱼";female.memories=[CompanionMemory(text:"女生私聊秘密")];try female.write(to:&document)
        var male=CompanionPersona.male.initial;male.profile.name="阿川";try CompanionDirectory.write(male,space:.direct(.male),to:&document)
        XCTAssertEqual(try CompanionData.read(document),female);XCTAssertEqual(try CompanionDirectory.read(.direct(.male),in:document).profile.title,"阿川")
        XCTAssertEqual(CompanionRules.selfReply("你是女生吗",profile:male.profile),"我是男生。")
        XCTAssertTrue(male.assistantStickers.allSatisfy {$0.id.hasPrefix("male_")});XCTAssertFalse(female.assistantStickers.contains {$0.id.hasPrefix("male_")})
        let result=CompanionStickerDelivery.resolve("来，抱一下。",selected:nil,question:"用抱抱表情包",data:male,history:[],proactive:false);XCTAssertEqual(result.id,"male_hug")
    }
    func testGroupContextContainsSharedFactsAndAttributedVoicesButNoPrivateMemory() throws {
        var document=Document(),female=CompanionData(),male=CompanionPersona.male.initial
        female.memories=[CompanionMemory(text:"只在女生私聊的秘密")];male.memories=[CompanionMemory(text:"只在男生私聊的秘密")]
        try female.write(to:&document);try CompanionDirectory.write(male,space:.direct(.male),to:&document)
        var group=try CompanionDirectory.create(name:"三人聊天",members:[.female,.male],in:&document)
        let user=CompanionMessage(role:"user",content:"一起聊周末",recipients:["female","male"])
        group.data.messages=[user,CompanionMessage(role:"assistant",content:"去散步吧。",speakerID:"female",turnID:user.id)];group.data.memories=[CompanionMemory(text:"群里约好去公园")]
        try CompanionDirectory.write(group.data,space:.group(group.id),to:&document)
        let context=CompanionDirectory.groupContext(group.data,as:.male,document:document)
        XCTAssertEqual(context.profile.persona,.male);XCTAssertEqual(context.memories,group.data.memories)
        let system=CompanionConversation.messages(question:"继续聊",data:context,history:context.messages)[0]["content"] as? String ?? ""
        XCTAssertFalse(system.contains("私聊的秘密"));XCTAssertEqual(context.messages.last?.speakerID,"female");XCTAssertEqual(context.messages.last?.content,"去散步吧。");XCTAssertEqual(context.messages.last?.role,"assistant")
        XCTAssertEqual(try CompanionDirectory.read(.direct(.female),in:document).memories,female.memories)
    }
    func testGroupRetryTargetsOnlyMissingMembersAndRejectsDuplicateTurnReplies() throws {
        var document=Document();var group=try CompanionDirectory.create(name:"群聊",members:[.female,.male],in:&document)
        let user=CompanionMessage(role:"user",content:"你好",recipients:["female","male"]);group.data.messages=[user]
        XCTAssertEqual(CompanionDirectory.pending(user,in:group.data),[.female,.male])
        let answer=CompanionMessage(role:"assistant",content:"我在。",speakerID:"female",turnID:user.id);group.data.messages.append(answer)
        XCTAssertEqual(CompanionDirectory.pending(user,in:group.data),[.male]);try group.validate()
        group.data.messages.append(CompanionMessage(role:"assistant",content:"我也在。",speakerID:"male",turnID:user.id));XCTAssertTrue(CompanionDirectory.pending(user,in:group.data).isEmpty)
        try CompanionDirectory.write(group.data,space:.group(group.id),to:&document);XCTAssertNoThrow(try document.validated())
        group.data.messages.append(CompanionMessage(role:"assistant",content:"重复",speakerID:"female",turnID:user.id));XCTAssertThrowsError(try group.validate())
    }
    func testGroupNaturalAddressingDoesNotNeedMentionsOrStartAutonomousRounds() throws {
        var document=Document(),male=CompanionPersona.male.initial;male.profile.name="阿川";try CompanionDirectory.write(male,space:.direct(.male),to:&document)
        let group=try CompanionDirectory.create(name:"小群",members:[.female,.male],in:&document)
        XCTAssertEqual(CompanionGroupChat.localRecipients(question:"大家聊聊",replyTo:nil,group:group,document:document),[.female,.male])
        XCTAssertEqual(CompanionGroupChat.localRecipients(question:"阿川，你说呢",replyTo:nil,group:group,document:document),[.male])
        XCTAssertEqual(CompanionGroupChat.localRecipients(question:"现在几点了",replyTo:nil,group:group,document:document)?.count,1)
        XCTAssertThrowsError(try CompanionDirectory.create(name:"坏群",members:[.female,.female],in:&document))
        XCTAssertThrowsError(try CompanionDirectory.create(name:"空群",members:[],in:&document))
    }
    func testGrowthUsesLastingFeedbackAndKeepsEachOwnerAndSpaceIndependent() throws {
        var female=CompanionData(),male=CompanionPersona.male.initial
        _=try CompanionRules.appendUserTurn("以后和我聊天少用反问，简短一点",to:&female)
        XCTAssertEqual(female.experiences?.count,2);XCTAssertTrue((male.experiences ?? []).isEmpty)
        _=try CompanionRules.appendUserTurn("我更喜欢你多说一点",to:&male)
        XCTAssertEqual(male.experiences?.first?.ownerID,"male");XCTAssertFalse(CompanionGrowth.instruction(male).contains("少用反问"))
        let before=female.experiences
        _=try CompanionRules.appendUserTurn("今天希望你详细一点",to:&female);XCTAssertEqual(female.experiences,before)
        female.profile.growthEnabled=false;_=try CompanionRules.appendUserTurn("以后希望你详细一点",to:&female);XCTAssertEqual(female.experiences,before)
        var document=Document();try female.write(to:&document);try CompanionDirectory.write(male,space:.direct(.male),to:&document)
        let group=try CompanionDirectory.create(name:"群内习惯",members:[.female,.male],in:&document)
        XCTAssertTrue((CompanionDirectory.groupContext(group.data,as:.female,document:document).experiences ?? []).isEmpty)
        try CompanionDirectory.remove(group.id,in:&document);XCTAssertEqual(try CompanionData.read(document).experiences,female.experiences)
    }
}

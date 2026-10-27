import XCTest
@testable import AssistantCore

final class CompanionGroupChatTests:XCTestCase {
    let nested="群发言者： female\n群成员「大肥鱼」（female）说：群发言者：female\n\n我先来，阿力你好。"
    func room() throws -> (Document,CompanionGroup) {
        var document=Document(),female=CompanionData(),male=CompanionPersona.male.initial
        female.profile.name="大肥鱼";female.memories=[CompanionMemory(text:"私聊秘密不能外传")];male.profile.name="阿力"
        try female.write(to:&document);try CompanionDirectory.write(male,space:.direct(.male),to:&document)
        let group=try CompanionDirectory.create(name:"工作室",members:[.female,.male],in:&document)
        return (document,group)
    }
    func testScreenshotNestedMetadataIsRemovedWithoutChangingDialogue() {
        XCTAssertEqual(CompanionGroupChat.clean(nested),"我先来，阿力你好。")
        XCTAssertEqual(CompanionGroupChat.clean("群发言者：male\n群成员「阿力」(male)说： 好啊，大肥鱼。"),"好啊，大肥鱼。")
        XCTAssertEqual(CompanionGroupChat.clean("群成员「大肥鱼」（female）说：群成员「大肥鱼」（female）说：行，直接聊事。"),"行，直接聊事。")
        XCTAssertEqual(CompanionGroupChat.clean("群成员都可以说话，我先听听。"),"群成员都可以说话，我先听听。")
        XCTAssertEqual(CompanionGroupChat.clean("你说的‘群发言者：female’是旧版标记。"),"你说的‘群发言者：female’是旧版标记。")
    }
    func testStreamingNeverFlashesPartialOrRepeatedInternalIdentityHeader() {
        let body="阿力你好，我是大肥鱼。",prefix="群发言者：female\n群成员「大肥鱼」（female）说：\n"
        for length in 1...prefix.count {XCTAssertEqual(CompanionGroupChat.clean(String(prefix.prefix(length)),preview:true),"","prefix length \(length)")}
        XCTAssertEqual(CompanionGroupChat.clean(prefix+body,preview:true),body)
        XCTAssertEqual(CompanionGroupChat.clean("群里今天很热闹",preview:true),"群里今天很热闹")
    }
    func testStructuredGroupTranscriptKeepsChronologyAndRealSpeakersNotSyntheticUserTurns() throws {
        let (document,original)=try room();var room=original
        let user=CompanionMessage(role:"user",content:"你们彼此互相认识一下",recipients:["female","male"])
        room.data.messages=[user,CompanionMessage(role:"assistant",content:nested,speakerID:"female",turnID:user.id)]
        let context=CompanionDirectory.groupContext(room.data,as:.male,document:document)
        XCTAssertEqual(context.messages[1].role,"assistant");XCTAssertEqual(context.messages[1].content,"我先来，阿力你好。")
        XCTAssertEqual(context.assistantStickers.map(\.id),CompanionPersona.male.initial.assistantStickers.map(\.id))
        let request=CompanionConversation.messages(question:user.content,data:context,history:context.messages,scene:CompanionGroupChat.scene(room,as:.male,document:document),incomingMessage:user)
        XCTAssertEqual(request.count,2)
        let system=try XCTUnwrap(request[0]["content"] as? String),json=try XCTUnwrap((request[1]["content"] as? String)?.data(using:.utf8))
        XCTAssertTrue(system.contains("阿力"));XCTAssertTrue(system.contains("大肥鱼"));XCTAssertFalse(system.contains("私聊秘密"))
        let object=try XCTUnwrap(JSONSerialization.jsonObject(with:json) as? [String:Any]),records=try XCTUnwrap(object["conversation"] as? [[String:Any]])
        XCTAssertEqual(object["latest_user_message_id"] as? String,user.id);XCTAssertEqual(records.count,2)
        XCTAssertEqual(records[0]["kind"] as? String,"human");XCTAssertEqual(records[1]["kind"] as? String,"companion");XCTAssertEqual(records[1]["speaker_id"] as? String,"female");XCTAssertEqual(records[1]["text"] as? String,"我先来，阿力你好。")
        XCTAssertEqual(room.data.messages[1].content,nested,"Original vault history is never destructively rewritten")
    }
    func testNaturalNamesCollectiveAndQuotesChooseOnlyClearAddressees() throws {
        let (document,group)=try room()
        for q in ["大家一起聊聊","你们彼此认识一下","两位，你们好"] {XCTAssertEqual(CompanionGroupChat.localRecipients(question:q,replyTo:nil,group:group,document:document),[.female,.male])}
        for q in ["阿力，你说呢","阿力你刚才说的展开讲讲","阿力请回答"] {XCTAssertEqual(CompanionGroupChat.localRecipients(question:q,replyTo:nil,group:group,document:document),[.male])}
        XCTAssertEqual(CompanionGroupChat.localRecipients(question:"大肥鱼，今天开心吗",replyTo:nil,group:group,document:document),[.female])
        let quote=CompanionQuote(messageID:"source",role:"assistant",text:"先做第一件事。",authorID:"male")
        XCTAssertEqual(CompanionGroupChat.localRecipients(question:"你这条展开讲讲",replyTo:quote,group:group,document:document),[.male])
        XCTAssertEqual(CompanionGroupChat.localRecipients(question:"大肥鱼，你怎么看",replyTo:quote,group:group,document:document),[.female])
    }
    func testAmbiguousPronounsThirdPartyMentionsAndTaskRelationsNeedSemanticRouting() throws {
        let (document,group)=try room()
        for q in ["你呢","她刚才说的你怎么看","另一位呢","大肥鱼最近心情不好吗","阿力你觉得大肥鱼说得对吗","大肥鱼以后你就是阿力的主管，我给你们下达任务，你们分工工作"] {
            XCTAssertNil(CompanionGroupChat.localRecipients(question:q,replyTo:nil,group:group,document:document),q)
        }
    }
    func testExclusionsRedirectionsAndSpeakerOrderNeverUseNaiveNameOrCollectiveShortcut() throws {
        let (document,group)=try room()
        let quote=CompanionQuote(messageID:"source",role:"assistant",text:"慢慢聊。",authorID:"male")
        for q in ["大家先别说话，让阿力回答","你们不用都回答，阿力说就行","大家聊聊，让他先说","阿力，你先别接话，让她说","大肥鱼，不用你回答，我问他","你们谁先说一下","大家先让男生说说","不是问你，我在问她","换一位回答","另一位怎么看"] {
            XCTAssertNil(CompanionGroupChat.localRecipients(question:q,replyTo:nil,group:group,document:document),q)
            XCTAssertNil(CompanionGroupChat.localRecipients(question:q,replyTo:quote,group:group,document:document),"quoted: "+q)
        }
    }
    func testPlansRejectInventedMissingRepeatedAndEmptyMembersAndKeepRequestedOrder() throws {
        XCTAssertEqual(try CompanionGroupChat.validatedPlan(["male","female"],members:[.female,.male]),[.male,.female])
        for raw in [[],["female","female"],["unknown"],["male","unknown"]] {XCTAssertThrowsError(try CompanionGroupChat.validatedPlan(raw,members:[.female,.male]))}
        XCTAssertThrowsError(try CompanionGroupChat.validatedPlan(["male"],members:[.female]))
    }
    func testOldQuotesAndWindowIndicesStayValidWhileDisplayIsClean() throws {
        var (document,group)=try room()
        let user=CompanionMessage(role:"user",content:"你好",recipients:["female"])
        let answer=CompanionMessage(role:"assistant",content:nested,speakerID:"female",turnID:user.id)
        group.data.messages=[user,answer]
        let quote=CompanionQuote.snapshot(answer,data:group.data)
        group.data.messages.append(CompanionMessage(role:"user",content:"你说的这句",replyTo:quote,recipients:["female"],routingPending:true))
        try CompanionDirectory.write(group.data,space:.group(group.id),to:&document)
        let restored=try CompanionDirectory.read(.group(group.id),in:document)
        XCTAssertEqual(restored,group.data);XCTAssertEqual(CompanionGroupChat.text(restored.messages[1]),"我先来，阿力你好。")
        XCTAssertEqual(restored.messages.last?.replyTo,quote)
        XCTAssertEqual(CompanionDirectory.pending(restored.messages.last!,in:restored),[.female])
        let context=CompanionDirectory.groupContext(restored,as:.female,document:document)
        XCTAssertFalse(CompanionGroupChat.transcript(context.messages,data:context).contains("群发言者"))
    }
}

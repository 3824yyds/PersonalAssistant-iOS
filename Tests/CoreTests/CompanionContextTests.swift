import XCTest
@testable import AssistantCore

final class CompanionContextTests:XCTestCase {
    func testFullWindowDoesNotSlideAwayBeginningAndStopsAtVisibleBudget() {
        var data=CompanionData()
        data.messages=(0..<45).map {CompanionMessage(role:$0%2==0 ? "user":"assistant",content:String(repeating:"字",count:1000))}
        XCTAssertEqual(CompanionContext.count(data),45000)
        XCTAssertTrue(CompanionContext.canSend("再聊一句",data:data))
        XCTAssertGreaterThan(CompanionContext.count(data),CompanionContext.warning)
        let request=CompanionConversation.messages(question:"第一句说了什么？",data:data,history:data.messages)
        XCTAssertEqual(request.count,47)
        XCTAssertEqual(request[1]["content"] as? String,data.messages.first?.content)
        XCTAssertFalse(CompanionContext.canSend(String(repeating:"甲",count:3000),data:data))
        data.messages.append(CompanionMessage(role:"assistant",content:String(repeating:"甲",count:3100)))
        XCTAssertTrue(CompanionContext.full(data))
    }
    func testCompressionPreviewDoesNotMutateUntilAppliedAndKeepsOriginalNameMemoriesAndMessages() throws {
        var data=CompanionData();data.profile.name="大肥鱼";data.memories=[CompanionMemory(text:"喜欢安静的地方")]
        data.messages=[CompanionMessage(role:"user",content:"周六去杭州面试"),CompanionMessage(role:"assistant",content:"可以先准备几个常见问题。")]
        let original=data.messages
        let preview=CompanionCompressionPreview(text:"用户说：周六去杭州面试。",expectedLastID:data.messages.last?.id,expectedWindowID:nil)
        XCTAssertNil(data.windows)
        XCTAssertTrue(CompanionContext.apply(preview,to:&data))
        XCTAssertEqual(data.messages,original);XCTAssertEqual(data.profile.name,"大肥鱼");XCTAssertEqual(data.memories.count,1)
        XCTAssertTrue(CompanionContext.current(data).isEmpty);XCTAssertEqual(CompanionContext.summary(data),preview.text)
        XCTAssertFalse(CompanionContext.apply(preview,to:&data))
        _=try CompanionRules.appendUserTurn("继续聊面试",to:&data)
        let request=CompanionConversation.messages(question:"你记得我们聊到哪吗",data:data,history:data.messages)
        XCTAssertEqual(request.count,3);XCTAssertEqual(request[1]["content"] as? String,"继续聊面试")
        XCTAssertTrue((request[0]["content"] as? String ?? "").contains("用户说：周六去杭州面试"))
    }
    func testStaleEmptyAndOversizeCompressionAreRejectedWithoutDeletingAnything() {
        var data=CompanionData();data.messages=[CompanionMessage(role:"user",content:"原文")]
        for text in ["",String(repeating:"甲",count:5001)] {
            let before=data
            XCTAssertFalse(CompanionContext.apply(CompanionCompressionPreview(text:text,expectedLastID:data.messages.last?.id,expectedWindowID:nil),to:&data));XCTAssertEqual(data,before)
        }
        let stale=CompanionCompressionPreview(text:"摘要",expectedLastID:data.messages.last?.id,expectedWindowID:nil)
        data.messages.append(CompanionMessage(role:"user",content:"新的纠正"));let before=data
        XCTAssertFalse(CompanionContext.apply(stale,to:&data));XCTAssertEqual(data,before)
    }
    func testMultipleWindowsKeepBoundariesAndRoundTripInExistingBackup() throws {
        var data=CompanionData();data.messages=[CompanionMessage(role:"user",content:"第一窗原文")]
        XCTAssertTrue(CompanionContext.apply(CompanionCompressionPreview(text:"第一窗摘要",expectedLastID:data.messages.last?.id,expectedWindowID:nil),to:&data))
        _=try CompanionRules.appendUserTurn("第二窗的新消息",to:&data)
        XCTAssertTrue(CompanionContext.apply(CompanionCompressionPreview(text:"更正后的合并摘要",expectedLastID:data.messages.last?.id,expectedWindowID:data.windows?.last?.id),to:&data))
        XCTAssertEqual(data.windows?.map(\.startIndex),[1,2])
        XCTAssertEqual(data.messages.map(\.content),["第一窗原文","第二窗的新消息"])
        var document=Document();try data.write(to:&document)
        XCTAssertEqual(try CompanionData.read(JSONDecoder().decode(Document.self,from:document.encoded())),data)
    }
    func testBadWindowBoundariesAndOversizedSummaryCannotEnterBackup() {
        for windows in [[CompanionWindow(startIndex:-1,summary:"摘要")],[CompanionWindow(startIndex:2,summary:"摘要")],[CompanionWindow(startIndex:0,summary:"")],[CompanionWindow(startIndex:0,summary:String(repeating:"甲",count:5001))],[CompanionWindow(startIndex:1,summary:"前"),CompanionWindow(startIndex:0,summary:"后")]] {
            var data=CompanionData();data.messages=[CompanionMessage(role:"user",content:"原文")];data.windows=windows
            XCTAssertThrowsError(try data.validate())
        }
    }
    func testSummaryNeedsRealMessageEvidenceAndKeepsSpeakerDistinct() {
        let user=CompanionMessage(role:"user",content:"面试改到周日下午两点，不是周六了。")
        let assistant=CompanionMessage(role:"assistant",content:"我刚才把时间记错了。")
        let good=[CompanionSummaryFact(text:"面试改到周日下午两点",messageID:user.id,quote:"改到周日下午两点"),CompanionSummaryFact(text:"曾误记时间",messageID:assistant.id,quote:"把时间记错了")]
        XCTAssertEqual(CompanionContext.facts(good,source:[user,assistant]),"用户说：面试改到周日下午两点\n伙伴曾回复：曾误记时间")
        XCTAssertNil(CompanionContext.facts([CompanionSummaryFact(text:"假事实",messageID:user.id,quote:"周一")],source:[user]))
        XCTAssertNil(CompanionContext.facts([CompanionSummaryFact(text:"假事实",messageID:"missing",quote:"面试")],source:[user]))
        XCTAssertNil(CompanionContext.facts(good,source:[user,user]))
    }
    func testNewWindowExpiresNameProposalAndAcknowledgementCannotAccidentallyRename() throws {
        var data=CompanionData();data.messages=[CompanionMessage(role:"assistant",content:"你想叫我小鱼吗",nameProposal:"小鱼")]
        XCTAssertTrue(CompanionContext.apply(CompanionCompressionPreview(text:"尚未确定伙伴名字",expectedLastID:data.messages.last?.id,expectedWindowID:nil),to:&data))
        _=try CompanionRules.appendUserTurn("对",to:&data)
        XCTAssertNil(data.profile.name);XCTAssertNil(data.messages.first?.nameProposal)
    }
    func testProactiveNeverStartsWhenWindowIsFull() {
        var data=CompanionData();data.messages=(0..<48).map {_ in CompanionMessage(role:"user",content:String(repeating:"甲",count:1000))}
        let now=Date()
        XCTAssertFalse(CompanionRules.mayInitiate(data:data,visible:true,active:true,editing:false,draft:"",busy:false,now:now,lastInteraction:now.addingTimeInterval(-60)))
    }
    func testSourceEditedWithSameIDsStillMakesPreviewStale() {
        var data=CompanionData();data.messages=[CompanionMessage(role:"user",content:"原来周六面试")]
        let preview=CompanionCompressionPreview(text:"周六面试",expectedLastID:data.messages.last?.id,expectedWindowID:nil,expectedMessages:data.messages,expectedSummary:"")
        data.messages[0].content="已经改成周日面试"
        let changed=data
        XCTAssertFalse(CompanionContext.apply(preview,to:&data));XCTAssertEqual(data,changed)
    }
}

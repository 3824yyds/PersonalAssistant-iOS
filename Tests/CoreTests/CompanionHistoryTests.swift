import XCTest
@testable import AssistantCore

final class CompanionHistoryTests:XCTestCase {
    func testHistoricalNamingQuestionsDoNotBecomeNameChanges() throws {
        for question in ["我第一次叫你大肥鱼是什么日期？","哪天给你取的名字？","我给你取名是什么时候","第一次叫你“大肥鱼”是几号","我给你取名是啥时候","我给你取名多少天了","我给你取名多长时间了","我给你取名的时间"] {
            XCTAssertFalse(CompanionNaming.isNamingRequest(question,history:[]),question)
            var data=CompanionData();data.profile.name="大肥鱼"
            XCTAssertFalse(try CompanionRules.appendUserTurn(question,to:&data),question);XCTAssertEqual(data.profile.name,"大肥鱼")
        }
        XCTAssertTrue(CompanionNaming.isNamingRequest("以后叫你“什么时候”吧",history:[]))
    }
    private let zone=TimeZone(identifier:"Asia/Shanghai")!
    private func date(_ value:String)->Date {ISO8601DateFormatter().date(from:value)!}
    private var old:Date {date("2026-10-26T19:36:00Z")}
    private var now:Date {date("2026-11-01T14:04:00Z")}
    private func metadata(_ system:String) throws -> [String:Any] {
        let line=try XCTUnwrap(system.components(separatedBy:"聊天时间证据JSON：").last?.components(separatedBy:"\n").first)
        return try XCTUnwrap(JSONSerialization.jsonObject(with:Data(line.utf8)) as? [String:Any])
    }
    func testOriginalDatesAndCurrentTurnSurviveRequestAssemblyWithoutRewritingText() throws {
        let first=CompanionMessage(role:"user",content:"大肥鱼",date:old)
        let latest=CompanionMessage(role:"user",content:"我第一次喊你是什么日期",date:now)
        var data=CompanionData();data.messages=[first,latest]
        let copy=data,request=CompanionConversation.messages(question:latest.content,data:data,history:[first],now:now,timeZone:zone)
        let info=try metadata(request[0]["content"] as! String),rows=try XCTUnwrap(info["turn_sent_at"] as? [[Any]])
        XCTAssertEqual(rows.count,2);XCTAssertEqual(rows[0][1] as? String,"2026-10-27T03:36:00+08:00");XCTAssertEqual(rows[1][1] as? String,"2026-11-01T22:04:00+08:00")
        XCTAssertEqual(request[1]["content"] as? String,"大肥鱼");XCTAssertEqual(request[2]["content"] as? String,latest.content)
        XCTAssertEqual(CompanionConversation.incoming(question:latest.content,data:data,replyTo:nil),latest);XCTAssertEqual(data,copy)
        XCTAssertTrue((request[0]["content"] as! String).contains("年龄和生日没有明确设定"))
    }
    func testQuotedOldWindowUsesSourceDateInsteadOfCurrentQuoteDate() throws {
        let first=CompanionMessage(role:"user",content:"大肥鱼",date:old)
        var data=CompanionData();data.messages=[first];data.windows=[CompanionWindow(startIndex:1,summary:"伙伴叫大肥鱼")]
        let quote=CompanionQuote.snapshot(first,data:data)
        let incoming=CompanionMessage(role:"user",content:"你自己看这是哪天",date:now,replyTo:quote);data.messages.append(incoming)
        let request=CompanionConversation.messages(question:incoming.content,data:data,history:[first],now:now,replyTo:quote,timeZone:zone)
        let info=try metadata(request[0]["content"] as! String),quotes=try XCTUnwrap(info["quoted_sources"] as? [[String:Any]])
        XCTAssertEqual(request.count,2);XCTAssertEqual(quotes[0]["sent_at"] as? String,"2026-10-27T03:36:00+08:00");XCTAssertEqual(quotes[0]["calendar_days_ago"] as? Int,5)
        XCTAssertEqual(quotes[0]["available"] as? Bool,true)
    }
    func testMissingChangedOrWrongAuthorQuoteDoesNotAcquireAnInventedDate() {
        var data=CompanionData();let source=CompanionMessage(role:"assistant",content:"我记得。",date:old,speakerID:"male");data.messages=[source]
        let wrong=CompanionQuote(messageID:source.id,role:"assistant",text:source.content,authorID:"female")
        XCTAssertEqual(CompanionHistory.quoteEvidence(wrong,data:data,now:now,timeZone:zone)["available"] as? Bool,false)
        let quote=CompanionQuote.snapshot(source,data:data);data.messages[0].content="改过的正文"
        let changed=CompanionHistory.quoteEvidence(quote,data:data,now:now,timeZone:zone)
        XCTAssertEqual(changed["available"] as? Bool,false);XCTAssertNil(changed["sent_at"])
        data.messages=[];XCTAssertNil(CompanionHistory.quoteEvidence(quote,data:data,now:now,timeZone:zone)["sent_at"])
    }
    func testHistorySearchIncludesOldWindowsSortsBySavedDatesAndExcludesCurrentQuestion() throws {
        let first=CompanionMessage(role:"user",content:"大肥鱼",date:old)
        let second=CompanionMessage(role:"assistant",content:"那我就叫大肥鱼。",date:old.addingTimeInterval(5))
        let latest=CompanionMessage(role:"user",content:"大肥鱼是什么时候取名的",date:now)
        var data=CompanionData();data.messages=[latest,second,first];data.windows=[CompanionWindow(startIndex:3,summary:"旧窗口已精简")]
        let result=try CompanionHistory.search(#"{"query":"大肥鱼","role":"user","order":"oldest"}"#,data:data,excluding:latest.id,now:now,timeZone:zone)
        XCTAssertEqual(result.int("total_matches"),1);XCTAssertEqual(result.items("results")[0].text("message_id"),first.id)
        XCTAssertEqual(result.items("results")[0].text("sent_at"),"2026-10-27T03:36:00+08:00");XCTAssertEqual(result.items("results")[0].int("calendar_days_ago"),5)
        XCTAssertEqual(result.text("scope"),"current_chat_retained_records_only")
    }
    func testHistorySearchIsBoundedPreservesUnicodeAndReturnsAnExcerptAroundMatch() throws {
        var data=CompanionData();data.messages=(0..<12).map {i in CompanionMessage(role:"user",content:String(repeating:"🙂",count:700)+"唯一关键词"+String(repeating:"字",count:900),date:old.addingTimeInterval(Double(i)))}
        let before=data,result=try CompanionHistory.search(#"{"query":"唯一关键词","role":"all","order":"newest"}"#,data:data,now:now,timeZone:zone)
        XCTAssertEqual(result.int("total_matches"),12);XCTAssertEqual(result.items("results").count,8)
        XCTAssertEqual(result.items("results")[0].text("message_id"),data.messages.last!.id)
        XCTAssertTrue(result.items("results").allSatisfy {$0.text("text").contains("唯一关键词") && $0.text("text").count<=500 && $0.bool("excerpt_truncated")});XCTAssertEqual(data,before)
    }
    func testInvalidSearchAndNoMatchNeverInventsHistory() throws {
        for args in [#"{"query":"","role":"all","order":"oldest"}"#,#"{"query":"鱼","role":"system","order":"oldest"}"#,#"{"query":"鱼","role":"all","order":"random"}"#,#"{"query":"鱼","role":"all","order":"oldest","space":"male"}"#] {XCTAssertThrowsError(try CompanionHistory.search(args,data:CompanionData()))}
        let empty=try CompanionHistory.search(#"{"query":"大肥鱼","role":"all","order":"oldest"}"#,data:CompanionData())
        XCTAssertEqual(empty.int("total_matches"),0);XCTAssertTrue(empty.items("results").isEmpty)
    }
    func testGroupRecordsCarryDatesAndStayInTheirOwnChat() throws {
        let groupMessage=CompanionMessage(role:"assistant",content:"群发言者：male\n大家好。",date:old,speakerID:"male")
        var group=CompanionData();group.messages=[groupMessage]
        let json=CompanionGroupChat.transcript(group.messages,data:group,timeZone:zone)
        let records=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(json.utf8)) as? [[String:Any]])
        XCTAssertEqual(records[0]["sent_at"] as? String,"2026-10-27T03:36:00+08:00");XCTAssertEqual(records[0]["text"] as? String,"大家好。")
        let missing=try CompanionHistory.search(#"{"query":"私聊秘密","role":"all","order":"oldest"}"#,data:group)
        XCTAssertTrue(missing.items("results").isEmpty)
    }
    func testCalendarDaysUseLocalMidnightAndDaylightSavingNotWhole24HourBlocks() {
        XCTAssertEqual(CompanionHistory.days(from:date("2026-10-31T15:59:00Z"),to:date("2026-10-31T16:01:00Z"),timeZone:zone),1)
        let ny=TimeZone(identifier:"America/New_York")!
        XCTAssertEqual(CompanionHistory.days(from:date("2026-11-01T05:30:00Z"),to:date("2026-11-01T06:30:00Z"),timeZone:ny),0)
        XCTAssertEqual(CompanionHistory.days(from:now,to:old,timeZone:zone),-5)
    }
    func testCompressionRetainsOriginalDateAndDoesNotRedateExistingSummary() throws {
        let message=CompanionMessage(role:"user",content:"今天决定叫你大肥鱼",date:old)
        let fact=CompanionSummaryFact(text:"用户给伙伴取名大肥鱼",messageID:message.id,quote:"大肥鱼")
        let summary=try XCTUnwrap(CompanionContext.facts([fact],source:[message]))
        XCTAssertTrue(summary.contains(CompanionHistory.formatter(.current).string(from:old)));XCTAssertTrue(summary.contains("用户说：用户给伙伴取名大肥鱼"))
        let carried=CompanionMessage(role:"user",content:summary,date:now,source:"已确认摘要")
        let next=try XCTUnwrap(CompanionContext.facts([CompanionSummaryFact(text:summary,messageID:carried.id,quote:"大肥鱼")],source:[carried]))
        XCTAssertFalse(next.contains(CompanionHistory.formatter(.current).string(from:now)));XCTAssertTrue(next.contains(CompanionHistory.formatter(.current).string(from:old)))
    }
    func testSummaryOfQuotedOldMessageKeepsBothReplyDateAndOriginalDate() throws {
        let original=CompanionMessage(role:"user",content:"大肥鱼",date:old)
        var data=CompanionData();data.messages=[original]
        let reply=CompanionMessage(role:"user",content:"这个名字是那天给你的",date:now,replyTo:CompanionQuote.snapshot(original,data:data));data.messages.append(reply)
        let fact=CompanionSummaryFact(text:"用户核对旧的取名记录",messageID:reply.id,quote:"大肥鱼")
        let summary=try XCTUnwrap(CompanionContext.facts([fact],source:[reply],retained:data))
        XCTAssertTrue(summary.contains("[引用原消息时间："+CompanionHistory.formatter(.current).string(from:old)+"]"));XCTAssertTrue(summary.contains(CompanionHistory.formatter(.current).string(from:now)))
    }
}

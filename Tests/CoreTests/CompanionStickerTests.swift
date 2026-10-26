import XCTest
@testable import AssistantCore

final class CompanionStickerTests:XCTestCase {
    func testBuild11DataWithoutStickerFieldsRemainsReadable() throws {
        let old=Data(#"{"profile":{"appearance":"蓝发蓝眼","personality":"热情","proactive":true,"web":true},"messages":[{"id":"old","role":"user","content":"🙂","date":0,"source":"","sources":[]}],"memories":[],"awaitingProactiveReply":false}"#.utf8)
        let data=try JSONDecoder().decode(CompanionData.self,from:old)
        try data.validate();XCTAssertNil(data.profile.stickers);XCTAssertNil(data.messages[0].stickerID)
        XCTAssertEqual(data.messages[0].content,"🙂")
    }
    func testStickersAndEmojiRoundTripWithoutBreakingUnicodeSequences() throws {
        var data=CompanionData();data.profile.stickers=false
        let emoji="又加班🙂🙃 👩🏽‍💻 👨‍👩‍👧‍👦 🇨🇳 👍🏽 ❤️‍🩹"
        data.messages=CompanionSticker.all.map {CompanionMessage(role:"assistant",content:"我在。",stickerID:$0.id)}+[CompanionMessage(role:"user",content:emoji)]
        var document=Document();try data.write(to:&document)
        let restored=try CompanionData.read(JSONDecoder().decode(Document.self,from:document.encoded()))
        XCTAssertEqual(data,restored);XCTAssertEqual(restored.messages.last?.content,emoji)
        XCTAssertTrue(restored.messages.allSatisfy { $0.stickerID==nil || CompanionSticker.find($0.stickerID) != nil })
    }
    func testUnknownStickerIDCannotBePersistedAsAnArbitraryAssetOrURL() throws {
        for id in ["../secret","https://example.com/image.png","not-in-pack"] {
            var data=CompanionData();data.messages=[CompanionMessage(role:"assistant",content:"你好",stickerID:id)]
            XCTAssertThrowsError(try data.validate())
        }
    }
    func testModelAndCompressionCanReadStickerMeaningAndContextRingCountsIt() throws {
        var data=CompanionData();let message=CompanionMessage(role:"user",content:"送你一个抱抱",stickerID:"hug");data.messages=[message]
        let messages=CompanionConversation.messages(question:"你知道我发的什么意思吗？",data:data,history:data.messages)
        XCTAssertTrue((messages[1]["content"] as? String ?? "").contains("安慰"))
        XCTAssertEqual(CompanionContext.count(data),message.contextText.count)
        let facts=[CompanionSummaryFact(text:"用户用抱抱表达关心",messageID:message.id,quote:"安慰、关心和支持")]
        XCTAssertNotNil(CompanionContext.facts(facts,source:data.messages))
    }
    func testEmojiIsSentIntactAndInstructionsExplainAmbiguityRatherThanLabelingUser() {
        let q="又加班🙂 👩🏽‍💻"
        let messages=CompanionConversation.messages(question:q,data:CompanionData(),history:[])
        XCTAssertEqual(messages.last?["content"] as? String,q)
        let system=messages[0]["content"] as? String ?? ""
        XCTAssertTrue(system.contains("可能礼貌、无奈或反讽"));XCTAssertTrue(system.contains("不能据此自动更名"))
    }
    func testFrequencyAvoidsConsecutiveAndRepeatedStickersButExplicitRequestsCanOverrideCooldown() {
        let history=[CompanionMessage(role:"assistant",content:"太棒啦",stickerID:"happy"),CompanionMessage(role:"assistant",content:"说说看")]
        let data=CompanionData()
        XCTAssertFalse(CompanionStickerRules.allowed("hug",question:"你好",data:data,history:history,proactive:false))
        XCTAssertFalse(CompanionStickerRules.allowed("happy",question:"[表情包：开心]",data:data,history:history,proactive:false))
        XCTAssertTrue(CompanionStickerRules.allowed("hug",question:"给我发一张表情包",data:data,history:history,proactive:false))
        XCTAssertFalse(CompanionStickerRules.allowed("happy",question:"继续",data:data,history:history,proactive:true))
    }
    func testSeriousDistressAndGentleToneCannotGetMockingStickerEvenWhenRequested() {
        var data=CompanionData()
        for id in ["happy","smug","speechless","goodnight"] {
            XCTAssertFalse(CompanionStickerRules.allowed(id,question:"我今天很难过😭，发个表情包",data:data,history:[],proactive:false))
        }
        XCTAssertTrue(CompanionStickerRules.allowed("hug",question:"我今天很难过😭",data:data,history:[],proactive:false))
        XCTAssertFalse(CompanionStickerRules.allowed("smug",question:"嗯",data:data,history:[CompanionMessage(role:"user",content:"我真的很难过")],proactive:false))
        data.profile.tone = .gentle
        XCTAssertFalse(CompanionStickerRules.allowed("speechless",question:"发个表情包",data:data,history:[],proactive:false))
    }
    func testStickerPreferenceWritesAndRestoresWithoutACloudCall() throws {
        var data=CompanionData()
        XCTAssertTrue(try CompanionRules.appendUserTurn("别发表情包",to:&data));XCTAssertEqual(data.profile.stickers,false)
        XCTAssertFalse(CompanionStickerRules.allowed("hug",question:"发个表情包",data:data,history:[],proactive:false))
        XCTAssertTrue(try CompanionRules.appendUserTurn("恢复表情包",to:&data));XCTAssertEqual(data.profile.stickers,true)
    }
    private var screenshotFlow:[CompanionMessage] {[
        CompanionMessage(role:"assistant",content:"也可以先给我取个名字呀。"),
        CompanionMessage(role:"user",content:"大肥鱼"),
        CompanionMessage(role:"assistant",content:"这是送我的名字，还是谁的外号？"),
        CompanionMessage(role:"user",content:"名字"),
        CompanionMessage(role:"assistant",content:"行啊，确认一下，是叫我“大肥鱼”对吧？")
    ]}
    func testScreenshotPlainTextConfirmationSavesExactNameAndReceipt() throws {
        var data=CompanionData();data.messages=screenshotFlow
        XCTAssertTrue(try CompanionRules.appendUserTurn("对的",to:&data))
        XCTAssertEqual(data.profile.name,"大肥鱼");XCTAssertEqual(data.messages.last?.renamedTo,"大肥鱼")
        var document=Document();try data.write(to:&document);XCTAssertEqual(try CompanionData.read(document).profile.name,"大肥鱼")
    }
    func testAssistantInventedNamesAndUnrelatedOldConfirmationsCannotRename() throws {
        var data=CompanionData();data.messages=[CompanionMessage(role:"user",content:"你好"),CompanionMessage(role:"assistant",content:"是叫我“阿肥”对吧？")]
        XCTAssertFalse(try CompanionRules.appendUserTurn("对的",to:&data));XCTAssertNil(data.profile.name)
        data.messages=screenshotFlow+[CompanionMessage(role:"user",content:"先聊别的"),CompanionMessage(role:"assistant",content:"今天过得怎样？")]
        XCTAssertFalse(try CompanionRules.appendUserTurn("对的",to:&data));XCTAssertNil(data.profile.name)
        data.messages=screenshotFlow;XCTAssertFalse(try CompanionRules.appendUserTurn("👍",to:&data));XCTAssertNil(data.profile.name)
    }
    func testShortNamingClarificationCanQuoteImmediateUserButNotOtherSpeakersOrOldTopics() {
        let flow=Array(screenshotFlow.dropLast())
        XCTAssertTrue(CompanionNaming.validEvidence(name:"大肥鱼",quote:"大肥鱼",question:"名字",history:Array(flow.dropLast())))
        XCTAssertFalse(CompanionNaming.validEvidence(name:"阿肥",quote:"阿肥",question:"名字",history:Array(flow.dropLast())))
        XCTAssertFalse(CompanionNaming.validEvidence(name:"大肥鱼",quote:"大肥鱼",question:"吃饭",history:Array(flow.dropLast())))
        XCTAssertFalse(CompanionNaming.validEvidence(name:"大肥鱼",quote:"大肥鱼",question:"名字",history:[CompanionMessage(role:"user",content:"我朋友叫大肥鱼"),CompanionMessage(role:"assistant",content:"什么名字？")]))
    }
}

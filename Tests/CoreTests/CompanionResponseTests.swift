import XCTest
@testable import AssistantCore

final class CompanionResponseTests:XCTestCase {
    private var screenshot:[CompanionMessage] {[
        CompanionMessage(role:"assistant",content:"你来啦，今天过得怎么样？也可以先给我取个名字呀。"),
        CompanionMessage(role:"user",content:"大肥鱼"),
        CompanionMessage(role:"assistant",content:"这名字来得突然，我抖了抖水花～真要拿“大肥鱼”当我的名字？确认了我可就顶着它到处游了。")
    ]}
    func testNewScreenshotConfirmationSavesBeforeNextWeatherTopic() throws {
        var data=CompanionData();data.messages=screenshot
        XCTAssertEqual(CompanionNaming.pending(data.messages),"大肥鱼")
        XCTAssertTrue(try CompanionRules.appendUserTurn("是的",to:&data))
        XCTAssertEqual(data.profile.name,"大肥鱼");XCTAssertEqual(data.messages.last?.renamedTo,"大肥鱼")
        XCTAssertFalse(try CompanionRules.appendUserTurn("今天的天气怎么样",to:&data))
        XCTAssertFalse(CompanionNaming.isNamingRequest("今天的天气怎么样",history:Array(data.messages.dropLast())))
        XCTAssertNil(CompanionNaming.pending(data.messages))
        var document=Document();try data.write(to:&document);XCTAssertEqual(try CompanionData.read(document).profile.name,"大肥鱼")
        for yes in ["对，就叫这个吧","是的呀","没错，就用这个名字","就叫这个吧"] {
            var other=CompanionData();other.messages=screenshot
            XCTAssertTrue(try CompanionRules.appendUserTurn(yes,to:&other),yes);XCTAssertEqual(other.profile.name,"大肥鱼",yes)
        }
    }
    func testConfirmationParaphrasesUseExactUserCandidateAndRequireDirectNamingRelation() throws {
        for name in ["大肥鱼","阿川","A.B+","鱼🐟"] {
            for sentence in ["真要拿“\(name)”当我的名字？", "那我就叫\(name)，可以吗？", "\(name)是给我的名字吗？", "确定叫我「\(name)」吗？"] {
                var data=CompanionData();data.messages=[CompanionMessage(role:"user",content:name),CompanionMessage(role:"assistant",content:sentence)]
                XCTAssertTrue(try CompanionRules.appendUserTurn("是的",to:&data),sentence);XCTAssertEqual(data.profile.name,name,sentence)
            }
        }
    }
    func testUnrelatedQuotedInventedAndThirdPartyNamesNeverRenameOrOpenNameTool() throws {
        for question in ["今天的天气怎么样","几点了","吃了么","我朋友叫大肥鱼","我的名字是大肥鱼","不要改名","引用“给你取名大肥鱼”"] {
            XCTAssertFalse(CompanionNaming.isNamingRequest(question,history:screenshot),question)
        }
        for user in ["你好","我朋友叫大肥鱼","我叫大肥鱼","如果叫大肥鱼呢"] {
            var data=CompanionData();data.messages=[CompanionMessage(role:"user",content:user),screenshot.last!]
            XCTAssertFalse(try CompanionRules.appendUserTurn("是的",to:&data),user);XCTAssertNil(data.profile.name,user)
        }
        var data=CompanionData();data.messages=screenshot+[CompanionMessage(role:"user",content:"今天的天气怎么样"),CompanionMessage(role:"assistant",content:"你在哪座城市？")]
        XCTAssertFalse(try CompanionRules.appendUserTurn("是的",to:&data));XCTAssertNil(data.profile.name)
    }
    func testRetryExistingFailedConfirmationPreservesUserIDAndDoesNotDuplicateIt() throws {
        var data=CompanionData();let user=CompanionMessage(role:"user",content:"是的")
        data.messages=screenshot+[user]
        let restored=try XCTUnwrap(CompanionRules.localRetry(data))
        XCTAssertEqual(restored.profile.name,"大肥鱼");XCTAssertEqual(restored.messages.filter {$0.id==user.id}.count,1)
        XCTAssertEqual(restored.messages.dropLast().last,user);XCTAssertEqual(restored.messages.count,data.messages.count+1)
        XCTAssertNil(CompanionRules.localRetry(restored))
    }
    func testStreamPreviewDoesNotExposeIncompleteStickerInstructionsOrFalseReceipts() {
        let data=CompanionData()
        XCTAssertEqual(CompanionStickerDelivery.preview("来，抱一下。\n[表情包：抱",question:"抱抱",data:data),"来，抱一下。")
        XCTAssertEqual(CompanionStickerDelivery.preview("来，抱一下。\n[表",question:"抱抱",data:data),"来，抱一下。")
        XCTAssertEqual(CompanionStickerDelivery.preview("图已经发过去了。",question:"抱抱",data:data),"")
        XCTAssertEqual(CompanionStickerDelivery.preview("我在听，你接着说。",question:"今天很累",data:data),"我在听，你接着说。")
        XCTAssertEqual(CompanionStickerDelivery.preview("[表情包：抱抱]",question:"解释这段格式",data:data),"[表情包：抱抱]")
    }
    func testUpgradeRecoversAlreadyConfirmedNameAfterWeatherAndRunsOnlyOnce() throws {
        var data=CompanionData();data.profile.nameRecoveryChecked=true
        data.messages=screenshot+[CompanionMessage(role:"user",content:"是的"),CompanionMessage(role:"user",content:"今天的天气怎么样")]
        let old=data.messages
        CompanionNaming.recoverConfirmedName(in:&data)
        XCTAssertEqual(data.profile.name,"大肥鱼");XCTAssertEqual(data.messages,old)
        let saved=data;CompanionNaming.recoverConfirmedName(in:&data);XCTAssertEqual(saved,data)
        data.profile.name=nil;CompanionNaming.recoverConfirmedName(in:&data);XCTAssertNil(data.profile.name)
        var cancelled=CompanionData();cancelled.messages=old+[CompanionMessage(role:"user",content:"取消取名")]
        CompanionNaming.recoverConfirmedName(in:&cancelled);XCTAssertNil(cancelled.profile.name)
    }
}

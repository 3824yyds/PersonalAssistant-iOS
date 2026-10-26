import XCTest
@testable import PersonalAssistant

private final class WebProtocol:URLProtocol {
    static var handler:((URLRequest)throws->(Int,Data))?
    override class func canInit(with request:URLRequest)->Bool {request.url?.host=="api.deepseek.com"}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        do {
            guard let handler=Self.handler else {throw URLError(.badServerResponse)}
            let (status,data)=try handler(request)
            let response=HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:"HTTP/1.1",headerFields:["Content-Type":request.url!.path=="/chat/completions" ? "text/event-stream":"application/json"])!
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        } catch {client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading() {}
}
final class DeepSeekWebTests:XCTestCase {
    @MainActor func testQuotedReplyCarriesSelectedSpeakerAndNeverExposesRenameTool() async throws {
        let original=CompanionMessage(role:"assistant",content:"旧消息：先聊长沙计划")
        var data=CompanionData();data.messages=[original];let quote=CompanionQuote.snapshot(original,data:data)
        WebProtocol.handler={request in
            let body=try self.body(request),messages=try XCTUnwrap(body["messages"] as? [[String:Any]])
            let text=messages.last?["content"] as? String ?? ""
            XCTAssertTrue(text.contains("旧消息：先聊长沙计划"));XCTAssertTrue(text.contains("assistant"));XCTAssertTrue(text.contains("本条新发言：这条先展开"))
            let tools=body["tools"] as? [[String:Any]] ?? []
            XCTAssertFalse(tools.contains {($0["function"] as? [String:Any])?["name"] as? String=="propose_companion_name"})
            return (200,try self.sse(["content":"那先说长沙的安排。 "]))
        }
        let result=try await CompanionReplyService.answer(question:"这条先展开",data:data,history:[],client:client(),replyTo:quote)
        XCTAssertNil(result.3);XCTAssertTrue(result.0.contains("长沙"))
    }
    @MainActor func testCustomStickerToolOnlyOffersAllowedIDsAndNeverUploadsPictureBytes() async throws {
        let png=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7GQAAAAASUVORK5CYII=")!
        let allowed=CompanionCustomSticker(title:"自定义招呼",meaning:"挥手打招呼",image:png),privateImage=CompanionCustomSticker(title:"自己用",meaning:"只供用户发送",image:png,allowAssistant:false)
        var data=CompanionData();try data.addSticker(allowed);try data.addSticker(privateImage);var calls=0
        WebProtocol.handler={request in
            calls+=1;let body=try self.body(request)
            XCTAssertFalse(String(describing:body).contains(png.base64EncodedString()))
            if calls==1 {
                let tools=try XCTUnwrap(body["tools"] as? [[String:Any]])
                let function=try XCTUnwrap(tools.compactMap {$0["function"] as? [String:Any]}.first {$0["name"] as? String=="send_companion_sticker"})
                let parameters=function["parameters"] as? [String:Any],properties=parameters?["properties"] as? [String:Any],field=properties?["id"] as? [String:Any],ids=field?["enum"] as? [String] ?? []
                XCTAssertTrue(ids.contains(allowed.id));XCTAssertFalse(ids.contains(privateImage.id))
                let arguments=String(decoding:try JSONSerialization.data(withJSONObject:["id":allowed.id]),as:UTF8.self)
                return (200,try self.sse(["tool_calls":[["index":0,"id":"custom","function":["name":"send_companion_sticker","arguments":arguments]]]]))
            }
            return (200,try self.sse(["content":"嗨，我们接着聊。 "]))
        }
        let result=try await CompanionReplyService.answer(question:"发个表情包打个招呼",data:data,history:[],client:client())
        XCTAssertEqual(result.4,allowed.id)
    }
    @MainActor func testPrivateQuotedNumbersCannotBecomeSearchQuery() async throws {
        let original=CompanionMessage(role:"user",content:"私人号码9876543210，帮我保留")
        var data=CompanionData();data.messages=[original];let quote=CompanionQuote.snapshot(original,data:data)
        WebProtocol.handler={request in
            XCTAssertEqual(request.url!.path,"/chat/completions")
            return (200,try self.sse(["tool_calls":[["index":0,"id":"quote-search","function":["name":"web_search","arguments":"{\"query\":\"9876543210\"}"]]]]))
        }
        do {_=try await CompanionReplyService.answer(question:"查一下这个话题",data:data,history:[],client:client(),replyTo:quote);XCTFail("Quoted private numbers must not be forwarded")}
        catch {XCTAssertTrue(error.localizedDescription.contains("私人"))}
    }
    @MainActor func testStickerToolAttachesOneKnownImageAndPreservesTextAnswer() async throws {
        var calls=0
        WebProtocol.handler={request in
            calls+=1
            if calls==1 {
                let body=try self.body(request),messages=try XCTUnwrap(body["messages"] as? [[String:Any]])
                XCTAssertTrue((messages[0]["content"] as? String ?? "").contains("双手握拳欢呼"))
                return (200,try self.sse(["tool_calls":[["index":0,"id":"sticker","function":["name":"send_companion_sticker","arguments":"{\"id\":\"happy\"}"]],["index":1,"id":"second","function":["name":"send_companion_sticker","arguments":"{\"id\":\"smug\"}"]]]]))
            }
            return (200,try self.sse(["content":"面试过了！这下可以松口气啦。 "]))
        }
        let result=try await CompanionReplyService.answer(question:"我的面试过了！",data:CompanionData(),history:[],client:client())
        XCTAssertEqual(result.4,"happy");XCTAssertTrue(result.0.contains("面试"));XCTAssertNil(result.3);XCTAssertEqual(calls,2)
    }
    @MainActor func testInvalidOrUnsuitableStickerDoesNotBreakUsefulTextReply() async throws {
        for (id,question) in [("https://example.com/x.png","你好"),("smug","今天真的很难过😭")] {
            var calls=0
            WebProtocol.handler={_ in
                calls+=1
                if calls==1 {
                    let args=String(decoding:try JSONSerialization.data(withJSONObject:["id":id]),as:UTF8.self)
                    return (200,try self.sse(["tool_calls":[["index":0,"id":"sticker","function":["name":"send_companion_sticker","arguments":args]]]]))
                }
                return (200,try self.sse(["content":"我在，你想说的话我听着。 "]))
            }
            let result=try await CompanionReplyService.answer(question:question,data:CompanionData(),history:[],client:client())
            XCTAssertNil(result.4);XCTAssertTrue(result.0.contains("我在"))
        }
    }
    @MainActor func testDisabledStickerToolIsNotExposedButUserEmojiAndStickerMeaningRemainReadable() async throws {
        var data=CompanionData();data.profile.stickers=false
        let original=CompanionMessage(role:"user",content:"抱抱",stickerID:"hug");data.messages=[original]
        let emoji="又加班🙂 👩🏽‍💻 👍🏽"
        WebProtocol.handler={request in
            let body=try self.body(request),tools=body["tools"] as? [[String:Any]] ?? [],messages=try XCTUnwrap(body["messages"] as? [[String:Any]])
            XCTAssertFalse(tools.contains {($0["function"] as? [String:Any])?["name"] as? String=="send_companion_sticker"})
            XCTAssertEqual(messages.last?["content"] as? String,emoji)
            XCTAssertTrue((messages[1]["content"] as? String ?? "").contains("安慰、关心和支持"))
            return (200,try self.sse(["content":"这笑脸后面，听着都是加班的无奈。 "]))
        }
        let result=try await CompanionReplyService.answer(question:emoji,data:data,history:data.messages,client:client())
        XCTAssertNil(result.4)
    }
    @MainActor func testStickerIsNotReturnedWhenFinalTextStreamFails() async throws {
        var calls=0
        WebProtocol.handler={_ in
            calls+=1
            if calls==1 {return (200,try self.sse(["tool_calls":[["index":0,"id":"sticker","function":["name":"send_companion_sticker","arguments":"{\"id\":\"hug\"}"]]]]))}
            throw URLError(.networkConnectionLost)
        }
        do {_=try await CompanionReplyService.answer(question:"陪我聊聊",data:CompanionData(),history:[],client:client());XCTFail("An uncompleted reply must not commit a sticker")}
        catch {XCTAssertEqual((error as? URLError)?.code,.networkConnectionLost)}
    }
    @MainActor func testNamingClarificationCanUsePreviousUserEvidenceAndProseConfirmationBecomesRealProposal() async throws {
        let history=[CompanionMessage(role:"user",content:"大肥鱼"),CompanionMessage(role:"assistant",content:"这是给我的名字吗？")]
        for usesTool in [true,false] {
            var calls=0
            WebProtocol.handler={_ in
                calls+=1
                if usesTool && calls==1 {return (200,try self.sse(["tool_calls":[["index":0,"id":"name","function":["name":"propose_companion_name","arguments":"{\"name\":\"大肥鱼\",\"quote\":\"大肥鱼\"}"]]]]))}
                return (200,try self.sse(["content":"确认一下，是叫我“大肥鱼”对吧？"]))
            }
            let result=try await CompanionReplyService.answer(question:"名字",data:CompanionData(),history:history,client:client())
            XCTAssertEqual(result.3,"大肥鱼");XCTAssertNil(result.4)
            var data=CompanionData();data.messages=history+[CompanionMessage(role:"user",content:"名字"),CompanionMessage(role:"assistant",content:result.0,nameProposal:result.3)]
            XCTAssertTrue(try CompanionRules.appendUserTurn("对的",to:&data));XCTAssertEqual(data.profile.name,"大肥鱼")
        }
    }
    @MainActor func testEmptyMemeSearchKeepsUnverifiedStatusVisible() async throws {
        var calls=0
        WebProtocol.handler={request in
            if request.url!.path=="/v1/tools/search" {return (200,Data(#"{"results":[]}"#.utf8))}
            calls+=1
            if calls==1 {return (200,try self.sse(["tool_calls":[["index":0,"id":"empty-search","function":["name":"web_search","arguments":"{\"query\":\"不存在的示例新梗\"}"]]]]))}
            return (200,try self.sse(["content":"没找到能核实的出处，可以把原话发我看看。 "]))
        }
        let result=try await CompanionReplyService.answer(question:"查一下这个不存在的示例梗",data:CompanionData(),history:[],client:client())
        XCTAssertEqual(result.1,"联网查询 · 未找到可核实来源");XCTAssertTrue(result.2.isEmpty)
    }
    @MainActor func testInvalidNameProposalCannotBecomeAFakeSuccessfulRename() async throws {
        var calls=0
        WebProtocol.handler={_ in
            calls+=1
            return (200,try self.sse(["tool_calls":[["index":0,"id":"bad-name","function":["name":"propose_companion_name","arguments":"{\"name\":\"阿肥\",\"quote\":\"不存在的取名指令\"}"]]]]))
        }
        do {_=try await CompanionReplyService.answer(question:"我说的是吃饭时间",data:CompanionData(),history:[],client:client());XCTFail("Expected invalid proposal rejection")}
        catch {XCTAssertTrue(error.localizedDescription.contains("名字尚未更改"))}
        XCTAssertEqual(calls,1)
    }
    @MainActor func testCompressionPreviewUsesQuotesAndDoesNotChangeStoredWindow() async throws {
        var data=CompanionData();data.profile.name="大肥鱼"
        let source=CompanionMessage(role:"user",content:"面试改到周日下午两点，不是周六了。")
        data.messages=[source];var calls=0
        WebProtocol.handler={request in
            calls+=1;let body=try self.body(request)
            XCTAssertNil(body["tools"]);XCTAssertEqual(body["model"] as? String,"deepseek-flash");XCTAssertEqual(body["max_tokens"] as? Int,8192)
            let messages=try XCTUnwrap(body["messages"] as? [[String:Any]])
            XCTAssertTrue((messages.last?["content"] as? String ?? "").contains(source.content))
            let value=["facts":[["text":"面试改到周日下午两点","messageID":source.id,"quote":"改到周日下午两点"]]]
            let text=String(decoding:try JSONSerialization.data(withJSONObject:value),as:UTF8.self)
            return (200,try self.sse(["content":text]))
        }
        let preview=try await CompanionCompressionService.preview(data:data,client:client())
        XCTAssertEqual(calls,1);XCTAssertTrue(preview.text.contains("用户说：面试改到周日下午两点"));XCTAssertEqual(preview.expectedLastID,source.id)
        XCTAssertNil(data.windows);XCTAssertEqual(data.messages,[source])
    }
    @MainActor func testCompressionRejectsInventedQuoteAndCancellationDoesNotContactServer() async throws {
        var data=CompanionData();let source=CompanionMessage(role:"user",content:"周六面试");data.messages=[source]
        WebProtocol.handler={_ in
            let value=["facts":[["text":"周一面试","messageID":source.id,"quote":"周一"]]]
            return (200,try self.sse(["content":String(decoding:try JSONSerialization.data(withJSONObject:value),as:UTF8.self)]))
        }
        do {_=try await CompanionCompressionService.preview(data:data,client:client());XCTFail("Expected quote rejection")}
        catch {XCTAssertTrue(error.localizedDescription.contains("原文依据"))}
        XCTAssertNil(data.windows);XCTAssertEqual(data.messages,[source])
        WebProtocol.handler={_ in XCTFail("Cancelled compression must not run");throw URLError(.cancelled)}
        let client=client(),snapshot=data
        let task=Task {try await CompanionCompressionService.preview(data:snapshot,client:client)};task.cancel()
        do {_=try await task.value;XCTFail("Expected cancellation")}catch{XCTAssertTrue(error is CancellationError)}
    }
    @MainActor func testCompressionVisitsEveryBatchAndCarriesPriorEvidence() async throws {
        var data=CompanionData()
        data.messages=(0..<90).map {CompanionMessage(role:"user",content:"第\($0)条计划："+String(repeating:"计划内容",count:150))}
        let expected=Set(data.messages.map(\.id));var seen=Set<String>(),calls=0
        WebProtocol.handler={request in
            calls+=1
            let body=try self.body(request),messages=try XCTUnwrap(body["messages"] as? [[String:Any]])
            let payload=try self.decodeJSON(try XCTUnwrap(messages.last?["content"] as? String))
            let current=try XCTUnwrap(payload["messages"] as? [[String:String]])
            seen.formUnion(current.compactMap {$0["id"]})
            let prior=try XCTUnwrap(payload["previous_facts"] as? [[String:String]])
            if calls>1 {XCTAssertFalse(prior.isEmpty)}
            let first=try XCTUnwrap(current.first),id=try XCTUnwrap(first["id"]),quote=String(try XCTUnwrap(first["text"]).prefix(12))
            let facts=prior.map {["text":$0["text"]!,"messageID":$0["messageID"]!,"quote":$0["quote"]!]}+[["text":"保留这一段的计划","messageID":id,"quote":quote]]
            return (200,try self.sse(["content":String(decoding:try JSONSerialization.data(withJSONObject:["facts":facts]),as:UTF8.self)]))
        }
        let preview=try await CompanionCompressionService.preview(data:data,client:client())
        XCTAssertGreaterThan(calls,1);XCTAssertEqual(seen,expected);XCTAssertFalse(preview.text.isEmpty);XCTAssertNil(data.windows)
    }
    private func decodeJSON(_ text:String)throws->[String:Any] {try XCTUnwrap(JSONSerialization.jsonObject(with:Data(text.utf8)) as? [String:Any])}
    @MainActor func testNewWindowSendsConfirmedSummaryAndAllCurrentTurnsButNoArchivedRawMessages() async throws {
        var data=CompanionData()
        let old=CompanionMessage(role:"user",content:"归档的原始长对话"),current=CompanionMessage(role:"user",content:"当前窗口继续聊面试")
        data.messages=[old,current];data.windows=[CompanionWindow(startIndex:1,summary:"用户已确认：面试在周日下午两点。")]
        WebProtocol.handler={request in
            let body=try self.body(request),messages=try XCTUnwrap(body["messages"] as? [[String:Any]])
            XCTAssertEqual(messages.count,3);XCTAssertEqual(messages[1]["content"] as? String,current.content)
            XCTAssertTrue((messages.first?["content"] as? String ?? "").contains("面试在周日下午两点"))
            XCTAssertFalse(String(describing:messages).contains(old.content))
            return (200,try self.sse(["content":"记得，我们接着准备周日下午的面试。 "]))
        }
        _=try await CompanionReplyService.answer(question:"继续",data:data,history:data.messages,client:client())
    }
    @MainActor func testFullWindowPreventsRequestInsteadOfSilentlyTruncatingHistory() async throws {
        var data=CompanionData();data.messages=(0..<49).map {_ in CompanionMessage(role:"user",content:String(repeating:"甲",count:1000))}
        WebProtocol.handler={_ in XCTFail("Full window must not contact the API");throw URLError(.cancelled)}
        do {_=try await CompanionReplyService.answer(question:"继续",data:data,history:data.messages,client:client());XCTFail("Expected context cap")}
        catch {XCTAssertTrue(error.localizedDescription.contains("上限"))}
    }
    @MainActor func testSemanticNamingToolReturnsConfirmationWithoutPretendingNameWasSaved() async throws {
        let data=CompanionData();var calls=0
        WebProtocol.handler={request in
            calls+=1
            if calls==1 {return (200,try self.sse(["tool_calls":[["index":0,"id":"name-proposal","function":["name":"propose_companion_name","arguments":"{\"name\":\"小鱼\",\"quote\":\"以后你就用小鱼这个名字\"}"]]]]))}
            return (200,try self.sse(["content":"我已经改名叫小鱼了。 "]))
        }
        let result=try await CompanionReplyService.answer(question:"我决定了，以后你就用小鱼这个名字",data:data,history:[],client:client())
        XCTAssertEqual(result.3,"小鱼");XCTAssertTrue(result.0.contains("确认后"));XCTAssertFalse(result.0.contains("已经改名"))
        XCTAssertNil(data.profile.name)
    }
    @MainActor func testCompanionOrdinaryChatUsesFlashFullContextAndSelectedTone() async throws {
        var data=CompanionData();data.profile.name="大肥鱼";data.profile.tone = .spicy;data.memories=[CompanionMemory(text:"喜欢安静的地方")]
        let history=[CompanionMessage(role:"user",content:"这个点吃饭？"),CompanionMessage(role:"assistant",content:"我一个人，你呢？"),CompanionMessage(role:"user",content:"我说的是时间")]
        var count=0
        WebProtocol.handler={request in
            count+=1;XCTAssertEqual(request.url!.path,"/chat/completions")
            let body=try self.body(request);XCTAssertEqual(body["model"] as? String,"deepseek-flash");XCTAssertEqual(body["max_tokens"] as? Int,768)
            let messages=try XCTUnwrap(body["messages"] as? [[String:Any]])
            XCTAssertEqual(messages.count,5);XCTAssertEqual(messages[1]["content"] as? String,"这个点吃饭？")
            let system=try XCTUnwrap(messages[0]["content"] as? String)
            XCTAssertTrue(system.contains("大肥鱼"));XCTAssertTrue(system.contains("贴吧老哥"));XCTAssertTrue(system.contains("喜欢安静的地方"))
            XCTAssertFalse(system.contains("再给必要的2–4个要点"))
            let tools=try XCTUnwrap(body["tools"] as? [[String:Any]])
            XCTAssertEqual(tools.count,3);XCTAssertEqual((tools[0]["function"] as? [String:Any])?["name"] as? String,"web_search")
            return (200,try self.sse(["content":"哦，你问的是时间，我刚才听岔了。 "]))
        }
        let result=try await CompanionReplyService.answer(question:"我问为什么这么晚",data:data,history:history,client:client())
        XCTAssertEqual(count,1);XCTAssertEqual(result.1,"DeepSeek Flash");XCTAssertTrue(result.2.isEmpty)
    }
    @MainActor func testCompanionDisabledSearchAndPerTurnNoWebNeverExposeSearchTool() async throws {
        for disabled in [true,false] {
            var data=CompanionData();data.profile.web = !disabled
            WebProtocol.handler={request in
                let body=try self.body(request)
                XCTAssertFalse((body["tools"] as? [[String:Any]] ?? []).contains {($0["function"] as? [String:Any])?["name"] as? String=="web_search"})
                XCTAssertEqual(request.url!.path,"/chat/completions")
                return (200,try self.sse(["content":"这轮没有联网核实，我们可以先聊你发来的这句话。 "]))
            }
            _=try await CompanionReplyService.answer(question:disabled ? "这个词最近很火吗？":"不要联网，聊聊这个梗",data:data,history:[],client:client())
        }
    }
    @MainActor func testUnknownMemeCanSearchAndKeepsRealSourcesAndPersona() async throws {
        var data=CompanionData();data.profile.name="大肥鱼";var chats=0,queries:[String]=[]
        WebProtocol.handler={request in
            let body=try self.body(request)
            if request.url!.path=="/v1/tools/search" {
                queries.append(body["query"] as? String ?? "")
                return (200,Data(#"{"results":[{"title":"梗的原始发布","url":"https://example.com/meme","content":"这个词的原始语境说明","date":"2026-10-26"}]}"#.utf8))
            }
            chats+=1
            let messages=try XCTUnwrap(body["messages"] as? [[String:Any]])
            XCTAssertTrue((messages.first?["content"] as? String ?? "").contains("大肥鱼"))
            if chats==1 {return (200,try self.sse(["tool_calls":[["index":0,"id":"meme-search","function":["name":"web_search","arguments":"{\"query\":\"示例新梗 含义 原始语境\"}"]]]]))}
            return (200,try self.sse(["content":"找到原始语境了，这句话是在调侃那种情况。[1]"]))
        }
        let result=try await CompanionReplyService.answer(question:"这个示例新词是什么梗？",data:data,history:[],client:client())
        XCTAssertEqual(chats,2);XCTAssertEqual(queries,["示例新梗 含义 原始语境"])
        XCTAssertEqual(result.2.first?.url,"https://example.com/meme");XCTAssertEqual(result.1,"联网搜索 · 1 个来源")
    }
    @MainActor func testRepeatedAnswerGetsOnlyOneRepairWithoutAnotherSearchBudget() async throws {
        let history=[CompanionMessage(role:"assistant",content:"我一个人，你呢？")]
        var calls=0,statuses:[String]=[]
        WebProtocol.handler={request in
            calls+=1;let body=try self.body(request)
            if calls==2 {
                XCTAssertFalse((body["tools"] as? [[String:Any]] ?? []).contains {($0["function"] as? [String:Any])?["name"] as? String=="web_search"})
                let messages=try XCTUnwrap(body["messages"] as? [[String:Any]])
                XCTAssertTrue((messages.first?["content"] as? String ?? "").contains("未发给用户"))
                return (200,try self.sse(["content":"哦，你问的是时间，我刚才听岔了。 "]))
            }
            return (200,try self.sse(["content":"那我一个人，你呢？"]))
        }
        let result=try await CompanionReplyService.answer(question:"我说的是时间",data:CompanionData(),history:history,client:client(),onStatus:{statuses.append($0)})
        XCTAssertEqual(calls,2);XCTAssertTrue(result.0.contains("时间"));XCTAssertTrue(statuses.contains("正在换个说法…"))
    }
    @MainActor func testPersistentRepetitionFailsRatherThanLoopingOrReturningCannedSuccess() async throws {
        var calls=0;WebProtocol.handler={_ in calls+=1;return (200,try self.sse(["content":"我一个人，你呢？"]))}
        do {
            _=try await CompanionReplyService.answer(question:"你听懂我了吗？",data:CompanionData(),history:[CompanionMessage(role:"assistant",content:"我一个人，你呢？")],client:client())
            XCTFail("Repeated response should be rejected")
        } catch {XCTAssertTrue(error.localizedDescription.contains("重复"))}
        XCTAssertEqual(calls,2)
    }
    @MainActor func testCompanionFailureDoesNotSilentlyFallBackToTrainedModel() async throws {
        for code in [401,402,429,500] {
            var calls=0;WebProtocol.handler={_ in calls+=1;return(code,Data())}
            do {_=try await CompanionReplyService.answer(question:"聊点什么？",data:CompanionData(),history:[],client:client());XCTFail("Expected failure \(code)")}
            catch {XCTAssertFalse(error.localizedDescription.isEmpty)}
            XCTAssertEqual(calls,1)
        }
    }
    @MainActor func testCompanionTransportFailureAndTruncatedStreamDoNotProduceCompletedReply() async throws {
        WebProtocol.handler={_ in throw URLError(.notConnectedToInternet)}
        do {_=try await CompanionReplyService.answer(question:"你好",data:CompanionData(),history:[],client:client());XCTFail("Expected offline error")}
        catch {XCTAssertEqual((error as? URLError)?.code,.notConnectedToInternet)}
        WebProtocol.handler={_ in
            let raw=try JSONSerialization.data(withJSONObject:["choices":[["delta":["content":"只有半句"]]]])
            return (200,Data(("data: "+String(decoding:raw,as:UTF8.self)+"\n\n").utf8))
        }
        do {_=try await CompanionReplyService.answer(question:"你好",data:CompanionData(),history:[],client:client());XCTFail("Expected truncated stream error")}
        catch {XCTAssertTrue(error.localizedDescription.contains("未完成"))}
    }
    @MainActor func testCompanionRejectsTokenLimitAndAllowsExplicitDetailedReplyBudget() async throws {
        WebProtocol.handler={request in
            let body=try self.body(request);XCTAssertEqual(body["max_tokens"] as? Int,3072)
            let raw=try JSONSerialization.data(withJSONObject:["choices":[["delta":["content":"半篇正文"],"finish_reason":"length"]]])
            return (200,Data(("data: "+String(decoding:raw,as:UTF8.self)+"\n\ndata: [DONE]\n\n").utf8))
        }
        do {_=try await CompanionReplyService.answer(question:"详细解释一下",data:CompanionData(),history:[],client:client());XCTFail("Expected length error")}
        catch {XCTAssertTrue(error.localizedDescription.contains("长度上限"))}
    }
    @MainActor func testCompanionPrivateMemoryCannotBeCopiedIntoSearchQuery() async throws {
        var data=CompanionData();data.memories=[CompanionMemory(text:"秘密号码9876543210")]
        WebProtocol.handler={request in
            XCTAssertEqual(request.url!.path,"/chat/completions","Private search must never be sent")
            return (200,try self.sse(["tool_calls":[["index":0,"id":"private","function":["name":"web_search","arguments":"{\"query\":\"9876543210\"}"]]]]))
        }
        do {_=try await CompanionReplyService.answer(question:"帮我查一个公开梗",data:data,history:[],client:client());XCTFail("Expected privacy guard")}
        catch {XCTAssertTrue(error.localizedDescription.contains("私人资料"))}
    }
    @MainActor func testCancelledCompanionDoesNotSendAnyRequestAndProactiveCannotSearch() async throws {
        let client=client();WebProtocol.handler={_ in XCTFail("Cancelled call must not run");throw URLError(.cancelled)}
        let task=Task {try await CompanionReplyService.answer(question:"你好",data:CompanionData(),history:[],client:client)}
        task.cancel()
        do {_=try await task.value;XCTFail("Expected cancellation")}
        catch {XCTAssertTrue(error is CancellationError)}
        WebProtocol.handler={request in
            let body=try self.body(request);XCTAssertNil(body["tools"])
            return (200,try self.sse(["content":"刚才那个话题，我想到一点。 "]))
        }
        _=try await CompanionReplyService.answer(question:"主动接一句",data:CompanionData(),history:[],proactive:true,client:client)
    }
    func testCompanionEncryptedBackupKeepsNameAndUserMemorySeparate() throws {
        let key=try VaultCrypto.random(32),salt=try VaultCrypto.random(32)
        var document=Document(),data=CompanionData();data.profile.name="小澜"
        data.memories=[CompanionMemory(text:"喜欢公园")]
        data.profile.tone = .spicy;data.windows=[CompanionWindow(startIndex:0,summary:"用户说：周六去公园。")]
        data.profile.stickers=false;data.messages=[CompanionMessage(role:"user",content:"🙂👩🏽‍💻"),CompanionMessage(role:"assistant",content:"抱抱",stickerID:"hug")]
        try data.write(to:&document)
        let envelope=try VaultCrypto.encrypt(document.encoded(),key:key,salt:salt)
        XCTAssertFalse(String(decoding:envelope,as:UTF8.self).contains("小澜"))
        let restored=try JSONDecoder().decode(Document.self,from:VaultCrypto.decrypt(envelope,key:key))
        XCTAssertEqual(try CompanionData.read(restored),data)
        XCTAssertNil(restored.root.raw["assistantMemory"])
    }
    override func tearDown() {WebProtocol.handler=nil;super.tearDown()}
    func client()->DeepSeekWebClient {
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[WebProtocol.self]
        return DeepSeekWebClient(apiKey:"unit-test-placeholder",configuration:config)
    }
    func body(_ request:URLRequest)throws->[String:Any] {
        var data=request.httpBody ?? Data()
        if data.isEmpty,let stream=request.httpBodyStream {
            stream.open();defer{stream.close()};var buffer=[UInt8](repeating:0,count:1024)
            while stream.hasBytesAvailable {let count=stream.read(&buffer,maxLength:buffer.count);if count<=0 {break};data.append(buffer,count:count)}
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
    }
    func sse(_ delta:[String:Any])throws->Data {
        let data=try JSONSerialization.data(withJSONObject:["choices":[["delta":delta]]])
        return Data(("data: "+String(decoding:data,as:UTF8.self)+"\n\ndata: [DONE]\n\n").utf8)
    }
    @MainActor func testSearchFetchToolLoopAndCitationsUseOfficialEndpoints() async throws {
        var paths:[String]=[],chatCalls=0,sources:[WebSource]=[],statuses:[String]=[]
        WebProtocol.handler={request in
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer unit-test-placeholder")
            let path=request.url!.path;paths.append(path);let body=try self.body(request)
            switch path {
            case "/chat/completions":
                chatCalls+=1;XCTAssertEqual(body["model"] as? String,"deepseek-flash")
                if chatCalls==1 {
                    XCTAssertNotNil(body["tools"])
                    return (200,try self.sse(["tool_calls":[["index":0,"id":"search-1","function":["name":"web_search","arguments":"{\"query\":\"DeepSeek最新搜索API\"}"]]]]))
                }
                let messages=try XCTUnwrap(body["messages"] as? [[String:Any]])
                XCTAssertEqual(messages.last?["tool_call_id"] as? String,"search-1")
                XCTAssertTrue((messages.last?["content"] as? String)?.contains("官方正文")==true)
                return (200,try self.sse(["content":"已开放搜索接口。[1]"]))
            case "/v1/tools/search":
                XCTAssertEqual(body["count"] as? Int,5);XCTAssertEqual(body["need_content"] as? Bool,true)
                return (200,Data(#"{"results":[{"title":"官方公告","url":"https://api-docs.deepseek.com/news/","summary":"摘要","date":"2026-10-17T00:00:00Z"}]}"#.utf8))
            case "/v1/tools/fetch":
                XCTAssertEqual(body["url"] as? String,"https://api-docs.deepseek.com/news/")
                return (200,Data(#"{"title":"官方公告","content":"官方正文"}"#.utf8))
            default:throw URLError(.unsupportedURL)
            }
        }
        let result=try await client().answer(messages:[["role":"user","content":"查最新消息"]],model:"deepseek-flash",onPartial:nil,onSources:{sources=$0},onStatus:{statuses.append($0)})
        XCTAssertEqual(result.0,"已开放搜索接口。[1]");XCTAssertEqual(result.1,"联网搜索 · 1 个来源")
        XCTAssertEqual(paths,["/chat/completions","/v1/tools/search","/v1/tools/fetch","/chat/completions"])
        XCTAssertEqual(sources.first?.date,"2026-10-17T00:00:00Z")
        XCTAssertEqual(statuses,["正在搜索网页…","正在阅读来源…","正在整理回答…"])
    }
    @MainActor func testOrdinaryChatDoesNotForceSearch() async throws {
        var calls=0
        WebProtocol.handler={request in calls+=1;XCTAssertEqual(request.url!.path,"/chat/completions");return (200,try self.sse(["content":"你好！"]))}
        let result=try await client().answer(messages:[["role":"user","content":"你好"]],model:"deepseek-flash",onPartial:nil,onSources:nil,onStatus:nil)
        XCTAssertEqual(calls,1);XCTAssertEqual(result.1,"云端回答")
    }
    func testInsufficientBalanceIsReportedWithoutInventedResults() async throws {
        WebProtocol.handler={_ in (402,Data())}
        do {_=try await client().search("最新新闻");XCTFail("Expected balance error")}
        catch {XCTAssertTrue(error.localizedDescription.contains("余额不足"))}
    }
    func testEmptySearchResultsRemainEmpty() async throws {
        WebProtocol.handler={_ in (200,Data(#"{"results":[]}"#.utf8))}
        let pages=try await client().search("没有匹配的内容")
        XCTAssertTrue(pages.isEmpty)
    }
    @MainActor func testCancelledSearchDoesNotContactServer() async throws {
        WebProtocol.handler={_ in XCTFail("Cancelled searches must not be sent");return (200,Data(#"{"results":[]}"#.utf8))}
        let client=client()
        let pending=Task {try await client.search("最新消息")}
        pending.cancel()
        do {_=try await pending.value;XCTFail("Expected cancellation")}
        catch {XCTAssertTrue(error is CancellationError)}
    }
    func testOldMessagesDecodeWithoutSources() throws {
        let message=try JSONDecoder().decode(ChatMessage.self,from:Data(#"{"id":"old","role":"assistant","content":"旧对话","source":"云端回答"}"#.utf8))
        XCTAssertNil(message.sources)
        let source=WebSource(title:"官方",url:"https://example.com",date:"2026-10-17")
        let current=ChatMessage(role:"assistant",content:"内容[1]",sources:[source])
        XCTAssertEqual(try JSONDecoder().decode(ChatMessage.self,from:JSONEncoder().encode(current)),current)
        XCTAssertNil(message.images)
        let image=ChatImage(jpeg:Data([0xff,0xd8,0xff,0xd9]))
        let pictured=ChatMessage(role:"user",content:"图中有什么",images:[image])
        XCTAssertEqual(try JSONDecoder().decode(ChatMessage.self,from:JSONEncoder().encode(pictured)),pictured)
    }
    @MainActor func testVisionSendsRealImageBlocksAndPreservesThemThroughSearch() async throws {
        let image=ChatImage(jpeg:Data([0xff,0xd8,0xff,0xd9]))
        WebProtocol.handler={request in
            XCTAssertEqual(request.url?.host,"api.deepseek.com")
            let body=try self.body(request)
            let messages=try XCTUnwrap(body["messages"] as? [[String:Any]])
            let blocks=try XCTUnwrap(messages.last?["content"] as? [[String:Any]])
            XCTAssertEqual(blocks.last?["type"] as? String,"image_url")
            XCTAssertTrue(((blocks.last?["image_url"] as? [String:String])?["url"] ?? "").hasPrefix("data:image/jpeg;base64,"))
            XCTAssertEqual(body["model"] as? String,"deepseek-flash")
            return (200,try self.sse(["content":"这是一张风景图片。颜色和场景均来自图像。 "]))
        }
        let messages:[[String:Any]]=[["role":"user","content":try ChatImage.content("看懂这张图",images:[image])]]
        let result=try await client().answer(messages:messages,model:"deepseek-flash",onPartial:nil,onSources:nil,onStatus:nil)
        XCTAssertTrue(result.0.contains("风景"))
    }
    @MainActor func testLocalCreationToolWritesRealDocumentAndReturnsReceiptWithoutSearch() async throws {
        var chats=0,document=Document()
        let id=UUID().uuidString
        let schema:[String:Any]=["type":"function","function":["name":"create_note","parameters":["type":"object","properties":[:]]]]
        WebProtocol.handler={request in
            XCTAssertEqual(request.url!.path,"/chat/completions")
            let body=try self.body(request);chats+=1
            if chats==1 {
                let tools=try XCTUnwrap(body["tools"] as? [[String:Any]])
                XCTAssertEqual(tools.count,1);XCTAssertEqual((tools[0]["function"] as? [String:Any])?["name"] as? String,"create_note")
                return (200,try self.sse(["tool_calls":[["index":0,"id":"note-1","function":["name":"create_note","arguments":"{\"title\":\"明天爬山\",\"body\":\"准备水和运动鞋\"}"]]]]))
            }
            let messages=try XCTUnwrap(body["messages"] as? [[String:Any]])
            XCTAssertTrue((messages.last?["content"] as? String)?.contains("true")==true)
            return (200,try self.sse(["content":"已保存备忘录。 "]))
        }
        _=try await client().answer(messages:[["role":"user","content":"帮我新建爬山笔记"]],model:"deepseek-flash",webSearch:false,localTools:[schema],onTool:{name,args in
            XCTAssertEqual(name,"create_note")
            let draft=try JSONDecoder().decode(Item.self,from:Data(args.utf8))
            document=try ChatActions.create(draft,kind:.note,id:id,in:document,source:"帮我新建爬山笔记").0
            return Item(["saved":.bool(true),"id":.string(id)])
        },onPartial:nil,onSources:nil,onStatus:nil)
        XCTAssertEqual(chats,2);XCTAssertEqual(document.notes.count,1);XCTAssertEqual(document.notes[0].text("body"),"准备水和运动鞋")
    }
    @MainActor func testUnexposedWriteToolIsNeverExecuted() async throws {
        var chats=0,executed=false
        WebProtocol.handler={_ in chats+=1;return (200,try self.sse(chats==1 ? ["tool_calls":[["index":0,"id":"bad","function":["name":"create_note","arguments":"{}"]]]]:["content":"没有保存任何内容。 "]))}
        _=try await client().answer(messages:[["role":"user","content":"查天气"]],model:"deepseek-flash",onTool:{_,_ in executed=true;return Item()},onPartial:nil,onSources:nil,onStatus:nil)
        XCTAssertFalse(executed)
    }
}

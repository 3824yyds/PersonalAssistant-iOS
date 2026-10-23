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
    }
}

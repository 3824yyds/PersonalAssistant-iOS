import XCTest
@testable import AssistantCore

final class WebEvidenceTests:XCTestCase {
    func testSearchResultsValidateLinksDeduplicateAndBoundContent() throws {
        let data=Data(#"{"results":[{"title":"官方","url":"https://example.com/news","content":"正文"},{"title":"重复","url":"https://example.com/news"},{"title":"无效","url":"javascript:alert(1)"},{"title":"带凭证","url":"https://user:pass@example.com"}]}"#.utf8)
        let result=WebEvidence.pages(try JSONDecoder().decode(WebSearchResponse.self,from:data).results)
        XCTAssertEqual(result.count,1);XCTAssertEqual(result[0].source?.host,"example.com");XCTAssertEqual(result[0].text,"正文")
        let long=WebPage(title:"标题",url:"https://example.com",summary:String(repeating:"文",count:7000))
        XCTAssertEqual(long.text.count,6000)
    }
    func testCitationsOnlyLinkToReturnedSourcesAndPreserveExistingMarkdown() {
        let sources=[WebSource(title:"官方",url:"https://example.com/a(b)")]
        XCTAssertEqual(WebEvidence.cited("已证实[1] 未知[2] [0] 已有[1](https://example.org)",sources:sources),"已证实[1](https://example.com/a%28b%29) 未知[2] [0] 已有[1](https://example.org)")
    }
    func testCodeSubscriptsRemainCodeInsteadOfSourceLinks() {
        let source=WebSource(title:"官方",url:"https://example.com")
        XCTAssertEqual(WebEvidence.cited("结论[1] `items[1]`\n```swift\nitems[1]\n```",sources:[source]),"结论[1](https://example.com) `items[1]`\n```swift\nitems[1]\n```")
    }
    func testQueryIsNonblankAndWithinUnicodeScalarLimit() {
        XCTAssertEqual(WebEvidence.query("  今日新闻\n"),"今日新闻")
        XCTAssertEqual(WebEvidence.query(String(repeating:"🙂",count:200)).unicodeScalars.count,128)
        XCTAssertEqual(WebEvidence.query(" \n "),"")
    }
    func testFragmentedToolCallsAreReassembledInIndexOrder() throws {
        var stream=DeepSeekStreamMessage()
        func chunk(_ delta:[String:Any]) throws -> Data {try JSONSerialization.data(withJSONObject:["choices":[["delta":delta]]])}
        try stream.consume(chunk(["tool_calls":[["index":0,"id":"call-1","function":["name":"web_search","arguments":"{\"query\":\"最新"]]]]))
        try stream.consume(chunk(["tool_calls":[["index":0,"function":["arguments":"消息\"}"]]]]))
        XCTAssertEqual(stream.orderedCalls,[DeepSeekToolCall(id:"call-1",name:"web_search",arguments:"{\"query\":\"最新消息\"}")])
        try stream.consume(chunk(["content":"回答"]));XCTAssertEqual(stream.content,"回答")
        XCTAssertThrowsError(try stream.consume(chunk(["tool_calls":[["index":4]]])))
    }
    func testModelMigrationPreservesCurrentAndCustomSelections() {
        XCTAssertEqual(DeepSeekModels.current("deepseek-chat"),"deepseek-flash")
        XCTAssertEqual(DeepSeekModels.current("deepseek-reasoner"),"deepseek-flash")
        XCTAssertEqual(DeepSeekModels.current("deepseek-v4-pro"),"deepseek-v4-pro")
        XCTAssertEqual(DeepSeekModels.current("future-custom-model"),"future-custom-model")
    }
}

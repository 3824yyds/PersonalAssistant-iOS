import XCTest
@testable import AssistantCore

final class NotePresentationTests:XCTestCase {
    func testMarkdownExcerptIsReadableAndKeepsAmounts() {
        XCTAssertEqual(NoteText.snippet("## 本月计划\n- **购物** 1,200.00 HKD\n> 保留原文\n[银行](https://example.com)"),"本月计划 购物 1,200.00 HKD 保留原文 银行")
    }
    func testExcerptDoesNotRewriteStoredContent() {
        let text="## 摘要\r\n- 去北京\r\n  > 想去天安门看看"
        XCTAssertFalse(NoteText.snippet(text).contains("##"));XCTAssertTrue(text.contains("##"))
    }
    func testEvidenceIsValidatedButNotRepeatedInAdoptedText() throws {
        let result=try NoteActionResult.validated(source:"想去天安门看看，也想去西安。",mode:"摘要",items:[["text":"计划去北京和西安。","quote":"想去天安门看看"]])
        XCTAssertEqual(result.body,"## 摘要\n\n- 计划去北京和西安。")
        XCTAssertEqual(result.evidence,["想去天安门看看"]);XCTAssertFalse(result.body.contains(">"))
    }
    func testInventedEvidenceIsRejected() {
        XCTAssertThrowsError(try NoteActionResult.validated(source:"想去西安。",mode:"摘要",items:[["text":"去巴黎","quote":"去巴黎"]]))
    }
    func testEmptyEvidenceIsRejected() {
        XCTAssertThrowsError(try NoteActionResult.validated(source:"正文",mode:"摘要",items:[["text":"内容","quote":" "]]))
    }
    func testEmptyExtractionIsUsefulWithoutInventingItems() throws {
        XCTAssertEqual(try NoteActionResult.validated(source:"你好",mode:"行动清单",items:[]).body,"## 行动清单\n\n原文未提取到相关内容。")
    }
}

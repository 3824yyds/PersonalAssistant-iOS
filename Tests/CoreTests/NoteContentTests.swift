import XCTest
@testable import AssistantCore

final class NoteContentTests:XCTestCase {
    func note()->Item {Item.make(["title":.string("备忘录"),"body":.string("正文"),"updatedAt":.int(Clock.milliseconds)])}
    func testChecklistTableAndAttachmentsRoundTripInEncryptedDocumentModel() throws {
        var value=note();value.set("checklist",items:[Item.make(["text":.string("购买牛奶"),"done":.bool(true)])])
        var table=NoteContent.table();NoteContent.setCells([["项目","金额"],["牛奶","12"]],in:&table);value.set("tables",items:[table])
        value.set("attachments",items:[Item.make(["name":.string("合同.pdf"),"kind":.string("file"),"data":.string(Data("example".utf8).base64EncodedString())])]);value.set("richText","rich-text-representation")
        var document=Document();document.notes=[value];_=try document.validated()
        let restored=try JSONDecoder().decode(Document.self,from:document.encoded());XCTAssertEqual(restored.notes,[value])
        let text=NoteContent.text(value);for expected in ["购买牛奶","☑","项目","12","合同.pdf"] {XCTAssertTrue(text.contains(expected))}
    }
    func testIrregularTableAndOversizedFileAreRejected() {
        var value=note(),table=NoteContent.table();NoteContent.setCells([["A","B"],["C"]],in:&table);value.set("tables",items:[table]);XCTAssertThrowsError(try NoteContent.validate(value))
        value.set("tables",items:[]);value.set("attachments",items:[Item.make(["name":.string("x"),"kind":.string("file"),"data":.string(Data(repeating:0,count:5*1024*1024+1).base64EncodedString())])]);XCTAssertThrowsError(try NoteContent.validate(value))
    }
    func testTimeGroupingAndPinnedPriority() {
        var value=note();let now=Clock.date("2026-10-24")!;value.set("updatedAt",Int64(now.timeIntervalSince1970*1000));XCTAssertEqual(NoteContent.group(value,now:now),"今天")
        value.set("updatedAt",Int64(now.addingTimeInterval(-86400).timeIntervalSince1970*1000));XCTAssertEqual(NoteContent.group(value,now:now),"昨天")
        value.set("pinned",true);XCTAssertEqual(NoteContent.group(value,now:now),"置顶")
    }
    func testOldPlainNotesRemainValid() throws {var document=Document();document.notes=[note()];_=try document.validated()}
}

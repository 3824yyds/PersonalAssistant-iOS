import XCTest
@testable import AssistantCore

final class NoteAIProposalTests:XCTestCase {
    let source=NoteTextVersion(title:"原题",body:"第一行\n\n第三行")
    func testPolishOnlyReplacesOnExplicitAdoption() {
        let result=NoteTextVersion(title:"新题",body:"润色后的正文")
        let pending=NoteAIProposal(mode:"润色",source:source,result:result)
        XCTAssertEqual(pending.source,source)
        XCTAssertEqual(pending.adopting(over:source),result)
        XCTAssertEqual(source.title,"原题")
    }
    func testOtherSkillsAppendAndPreserveOriginalTitleAndWhitespace() {
        for mode in ["摘要","要点","会议纪要","行动清单"] {
            let pending=NoteAIProposal(mode:mode,source:source,result:NoteTextVersion(title:"不采用这个标题",body:"整理结果"))
            XCTAssertEqual(pending.adopting(over:source),NoteTextVersion(title:"原题",body:"第一行\n\n第三行\n\n整理结果"))
        }
    }
    func testStaleResultCannotOverwriteNewEdits() {
        let pending=NoteAIProposal(mode:"润色",source:source,result:NoteTextVersion(title:"新题",body:"结果"))
        XCTAssertNil(pending.adopting(over:NoteTextVersion(title:source.title,body:source.body+"新想法")))
        XCTAssertNil(pending.adopting(over:NoteTextVersion(title:"改过标题",body:source.body)))
    }
}

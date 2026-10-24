import XCTest
import SwiftUI
import UIKit
@testable import PersonalAssistant

@MainActor final class CompositionTests:XCTestCase {
    private func composingView(_ initial:String)->UITextView {
        let view=UITextView(frame:CGRect(x:0,y:0,width:320,height:160));view.text=initial
        view.selectedRange=NSRange(location:(initial as NSString).length,length:0)
        return view
    }
    func testNoteRefreshDoesNotCommitLatinMarkedTextAndChineseCandidateIsSaved() throws {
        var text="前文",rtf=""
        let editor=NoteRichText(text:Binding(get:{text},set:{text=$0}),richText:Binding(get:{rtf},set:{rtf=$0}))
        let coordinator=editor.makeCoordinator(),view=composingView(text)
        view.setMarkedText("zhi jie",selectedRange:NSRange(location:7,length:0))
        XCTAssertNotNil(view.markedTextRange)
        coordinator.textViewDidChange(view)
        editor.synchronize(view)
        XCTAssertEqual(text,"前文");XCTAssertNotNil(view.markedTextRange);XCTAssertTrue(view.text.contains("zhi jie"))
        view.setMarkedText("直接",selectedRange:NSRange(location:2,length:0));view.unmarkText();coordinator.textViewDidChange(view)
        XCTAssertEqual(text,"前文直接")
        let bytes=try XCTUnwrap(Data(base64Encoded:rtf))
        XCTAssertEqual(try NSAttributedString(data:bytes,options:[.documentType:NSAttributedString.DocumentType.rtf],documentAttributes:nil).string,text)
    }
    func testStreamingChatRefreshPreservesCompositionUntilUserAcceptsCandidate() {
        var text="帮我",focused=true
        let input=ComposingTextInput(text:Binding(get:{text},set:{text=$0}),isFocused:Binding(get:{focused},set:{focused=$0}),placeholder:"发消息…")
        let coordinator=input.makeCoordinator(),view=composingView(text)
        view.setMarkedText("ji lu",selectedRange:NSRange(location:5,length:0));XCTAssertNotNil(view.markedTextRange)
        for _ in 0..<12 {coordinator.textViewDidChange(view);input.synchronize(view)}
        XCTAssertEqual(text,"帮我");XCTAssertNotNil(view.markedTextRange)
        view.setMarkedText("记录",selectedRange:NSRange(location:2,length:0));view.unmarkText();coordinator.textViewDidEndEditing(view)
        XCTAssertEqual(text,"帮我记录");XCTAssertFalse(focused)
    }
    func testCreatedCardsAreBackwardCompatibleAndRoundTripWithHistory() throws {
        let old=try JSONDecoder().decode(ChatMessage.self,from:Data(#"{"id":"old","role":"assistant","content":"旧回答","source":"云端回答"}"#.utf8))
        XCTAssertNil(old.createdItems)
        let receipt=ChatCreatedItem(id:UUID().uuidString,kind:.expense,title:"午饭",detail:"CNY 25.00 · 现金")
        let message=ChatMessage(role:"assistant",content:"已保存支出",createdItems:[receipt])
        XCTAssertEqual(try JSONDecoder().decode(ChatMessage.self,from:JSONEncoder().encode(message)),message)
    }
}

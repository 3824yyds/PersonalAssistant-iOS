import XCTest
@testable import AssistantCore

final class VoiceGestureTests:XCTestCase {
    func testReleaseWithoutDraggingSends() {XCTAssertEqual(VoiceGesture.action(horizontal:5,vertical:-8),.send)}
    func testSlideLeftOrUpCancels() {XCTAssertEqual(VoiceGesture.action(horizontal:-100,vertical:0),.cancel);XCTAssertEqual(VoiceGesture.action(horizontal:0,vertical:-90),.cancel)}
    func testSlideRightRequestsEditableText() {XCTAssertEqual(VoiceGesture.action(horizontal:100,vertical:0),.text);XCTAssertEqual(VoiceGesture.action(horizontal:60,vertical:-90),.text)}
}

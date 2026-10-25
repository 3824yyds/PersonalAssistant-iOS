import XCTest
@testable import AssistantCore

final class VoiceTurnDetectorTests:XCTestCase {
    func testConstantBackgroundNoiseCannotPreventSendingRecognizedWords() {
        var detector=VoiceTurnDetector();detector.observe(text:"你好呀",at:0)
        for step in 0..<22 {
            let now=Double(step)/10;detector.observe(level:0.95,at:now)
            XCTAssertFalse(detector.shouldFinish(at:now))
        }
        detector.observe(level:0.95,at:2.3);XCTAssertTrue(detector.shouldFinish(at:2.3))
    }
    func testRecognitionProgressExtendsTheTurnWhileUserIsSpeaking() {
        var detector=VoiceTurnDetector()
        for step in 0..<20 {
            let now=Double(step)*0.5;detector.observe(text:String(repeating:"继续",count:step+1),at:now)
            detector.observe(level:0.8,at:now);XCTAssertFalse(detector.shouldFinish(at:now))
        }
        XCTAssertFalse(detector.shouldFinish(at:11));XCTAssertTrue(detector.shouldFinish(at:12))
    }
    func testDuplicateWhitespaceAndPunctuationUpdatesDoNotPostponeSending() {
        var detector=VoiceTurnDetector();detector.observe(text:"你好呀",at:0)
        for (offset,text) in ["你好呀","你好呀。"," 你好 呀！","你好呀？"].enumerated() {
            detector.observe(text:text,at:Double(offset)*0.6);detector.observe(level:0.9,at:Double(offset)*0.6)
        }
        XCTAssertTrue(detector.shouldFinish(at:2.3))
    }
    func testQuietPauseCanCompleteSoonerThanBackgroundNoiseDeadline() {
        var detector=VoiceTurnDetector();detector.observe(text:"明天去公园",at:0)
        detector.observe(level:0.7,at:0);detector.observe(level:0.02,at:0.2)
        XCTAssertFalse(detector.shouldFinish(at:1.1));XCTAssertTrue(detector.shouldFinish(at:1.3))
    }
    func testNoTextOrOnlyPunctuationCannotCreateAnEmptyRequest() {
        var detector=VoiceTurnDetector();detector.observe(text:"。！？",at:0)
        detector.observe(level:0,at:0);XCTAssertFalse(detector.shouldFinish(at:120))
    }
    func testCorrectionOfAnAmountWaitsForTheRevisedWordsToSettle() {
        var detector=VoiceTurnDetector();detector.observe(text:"记一百元",at:0)
        detector.observe(text:"记一千元",at:2);detector.observe(level:0.9,at:2)
        XCTAssertFalse(detector.shouldFinish(at:2.3));XCTAssertTrue(detector.shouldFinish(at:4.3))
    }
    func testNewTurnDoesNotInheritThePreviousDeadline() {
        var detector=VoiceTurnDetector();detector.observe(text:"第一句",at:0)
        XCTAssertTrue(detector.shouldFinish(at:3));detector=VoiceTurnDetector()
        XCTAssertFalse(detector.shouldFinish(at:100));detector.observe(text:"第二句",at:100)
        XCTAssertFalse(detector.shouldFinish(at:101))
    }
    func testInvalidMeterValuesCannotDisableTheTextDeadline() {
        var detector=VoiceTurnDetector();detector.observe(text:"你好",at:0)
        detector.observe(level:.nan,at:2);XCTAssertTrue(detector.shouldFinish(at:2.3))
    }
}

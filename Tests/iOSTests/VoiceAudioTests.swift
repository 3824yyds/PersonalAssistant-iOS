import XCTest
import AVFoundation
@testable import PersonalAssistant

private final class VoicePCMStats:@unchecked Sendable {
    private let lock=NSLock()
    private var frames=0
    private var peak:Float=0
    func append(_ buffer:AVAudioPCMBuffer) {
        lock.lock();defer{lock.unlock()}
        frames+=Int(buffer.frameLength)
        if let samples=buffer.floatChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) {peak=max(peak,abs(samples[i]))}
        }else if let samples=buffer.int16ChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) {peak=max(peak,Float(abs(Int(samples[i])))/32768)}
        }
    }
    func result()->(Int,Float) {lock.lock();defer{lock.unlock()};return(frames,peak)}
}
@MainActor final class VoiceAudioTests:XCTestCase {
    func testRecognitionFinishFallbackEmitsTheCapturedWords() async {
        let service=SpeechService(),done=expectation(description:"recognition finalization callback")
        service.text="你好呀";service.recording=true
        service.onFinal={text in XCTAssertEqual(text,"你好呀");done.fulfill()}
        service.finish()
        await fulfillment(of:[done],timeout:4)
        XCTAssertFalse(service.recording);XCTAssertFalse(service.finishing)
    }
    func testCancellingPendingRecognitionCannotSendAfterCallEnds() async {
        let service=SpeechService(),late=expectation(description:"no late final callback");late.isInverted=true
        service.text="不要再发送";service.recording=true;service.onFinal={_ in late.fulfill()}
        service.finish();service.cancel()
        await fulfillment(of:[late],timeout:2)
    }
    func testChineseSystemSpeechProducesNonSilentPCM() async throws {
        guard let voice=AVSpeechSynthesisVoice(language:"zh-CN") else{throw XCTSkip("Runner has no Chinese synthesis voice installed")}
        let synthesizer=AVSpeechSynthesizer(),text=AVSpeechUtterance(string:"你好，语音回复测试。")
        text.voice=voice
        let stats=VoicePCMStats(),done=expectation(description:"synthesized audio stream completed")
        synthesizer.write(text) {buffer in
            guard let pcm=buffer as? AVAudioPCMBuffer else{return}
            if pcm.frameLength==0 {done.fulfill()}else{stats.append(pcm)}
        }
        await fulfillment(of:[done],timeout:25)
        let(frames,peak)=stats.result()
        print("Chinese synthesis output: frames=\(frames), peak=\(peak)")
        XCTAssertGreaterThan(frames,0);XCTAssertGreaterThan(peak,0.00001)
        synthesizer.stopSpeaking(at:.immediate)
    }
}

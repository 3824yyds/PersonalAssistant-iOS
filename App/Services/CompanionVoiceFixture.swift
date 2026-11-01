#if DEBUG
import Foundation

/// Simulator transport fixture. These tones test decoding/playback, not voice quality.
final class CompanionVoiceFixture:URLProtocol {
    static func session()->URLSession {
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[Self.self];return URLSession(configuration:config)
    }
    static var enabled:Bool {ProcessInfo.processInfo.arguments.contains("--ui-companion-voice-fixture")}
    static func wave(seconds:Double=0.2)->Data {
        let samples=Int(seconds*24000),size=samples*2
        var data=Data("RIFF".utf8)
        func u32(_ n:Int) {var v=UInt32(n).littleEndian;withUnsafeBytes(of:&v) {data.append(contentsOf:$0)}}
        func u16(_ n:Int) {var v=UInt16(n).littleEndian;withUnsafeBytes(of:&v) {data.append(contentsOf:$0)}}
        u32(36+size);data.append(Data("WAVEfmt ".utf8));u32(16);u16(1);u16(1);u32(24000);u32(48000);u16(2);u16(16);data.append(Data("data".utf8));u32(size);data.append(Data(repeating:0,count:size));return data
    }
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        let failed=ProcessInfo.processInfo.arguments.contains("--ui-companion-voice-failure-fixture")
        let post=request.httpMethod=="POST"
        let status=post && failed ? 402:200
        let body=post ? Data("{\"output\":{\"audio\":{\"url\":\"https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/voice-ui.wav\"}}}".utf8):Self.wave(seconds:6)
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:"HTTP/1.1",headerFields:["Content-Type":post ? "application/json":"audio/wav"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:body);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif

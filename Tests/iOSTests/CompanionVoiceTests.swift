import XCTest
import CryptoKit
@testable import PersonalAssistant

private final class VoiceProtocol:URLProtocol {
    static var handler:((URLRequest)throws->(Int,Data))?
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        do {
            let (status,data)=try Self.handler!(request)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:"HTTP/1.1",headerFields:nil)!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        } catch {client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading() {}
}

final class CompanionVoiceTests:XCTestCase {
    private func session()->URLSession {let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[VoiceProtocol.self];return URLSession(configuration:c)}
    private func body(_ request:URLRequest) throws -> [String:Any] {
        let raw:Data
        if let bytes=request.httpBody {raw=bytes} else {
            let stream=try XCTUnwrap(request.httpBodyStream);stream.open();defer {stream.close()};var data=Data(),buffer=[UInt8](repeating:0,count:4096)
            while stream.hasBytesAvailable {let count=stream.read(&buffer,maxLength:buffer.count);if count<=0 {break};data.append(buffer,count:count)};raw=data
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with:raw) as? [String:Any])
    }
    func testRequestsUseOfficialAPIWithSeparateVoiceKeyAndDistinctSpeakers() throws {
        for voice in ["Cherry","Ethan"] {
            let request=try CompanionVoiceService.request(text:"我在呢，慢慢说。",voice:voice,credential:"voice-key")
            XCTAssertEqual(request.url,CompanionVoiceService.endpoint);XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer voice-key")
            let object=try body(request);XCTAssertEqual(object["model"] as? String,"qwen3-tts-flash")
            XCTAssertEqual((object["input"] as? [String:String])?["voice"],voice);XCTAssertNil(object["messages"])
        }
    }
    func testHeaderInjectionUnknownVoiceAndOversizedTextAreRejectedBeforeNetwork() {
        XCTAssertThrowsError(try CompanionVoiceService.request(text:"你好",voice:"Cherry",credential:"key\nInjected:yes"))
        XCTAssertThrowsError(try CompanionVoiceService.request(text:"你好",voice:"unknown",credential:"key"))
        XCTAssertThrowsError(try CompanionVoiceService.request(text:String(repeating:"字",count:601),voice:"Cherry",credential:"key"))
    }
    func testFullWaveDownloadDoesNotForwardCredentialsAndSupportsSeveralChunks() async throws {
        var calls=0,posts=0
        VoiceProtocol.handler={request in
            calls+=1
            if request.httpMethod=="POST" {
                posts+=1;let body=try self.body(request);let text=try XCTUnwrap((body["input"] as? [String:Any])?["text"] as? String);XCTAssertLessThanOrEqual(text.unicodeScalars.count,450)
                return (200,Data("{\"output\":{\"audio\":{\"url\":\"http://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/audio.wav?Expires=123\"}}}".utf8))
            }
            XCTAssertEqual(request.url?.scheme,"https");XCTAssertNil(request.value(forHTTPHeaderField:"Authorization"));return (200,CompanionVoiceFixture.wave())
        }
        let network=session();defer {network.invalidateAndCancel()}
        let clips=try await CompanionVoiceService(credential:"secret",session:network).synthesize(String(repeating:"我们慢慢来。",count:120),voice:"Ethan")
        XCTAssertGreaterThan(clips.count,1);XCTAssertEqual(calls,posts*2)
        let clip=try CompanionVoiceClip.validated(clips);XCTAssertGreaterThan(clip.duration,0)
    }
    func testQuotaFailureDoesNotDownloadOrAutomaticallyRetry() async {
        var calls=0;VoiceProtocol.handler={_ in calls+=1;return (402,Data("quota".utf8))}
        let network=session();defer {network.invalidateAndCancel()}
        do {_=try await CompanionVoiceService(credential:"key",session:network).synthesize("你好",voice:"Cherry");XCTFail()}catch {XCTAssertTrue(error.localizedDescription.contains("额度"))}
        XCTAssertEqual(calls,1)
    }
    func testProviderErrorInsideHTTP200IsNotAcceptedAsAudio() async {
        VoiceProtocol.handler={_ in (200,Data("{\"code\":\"InvalidApiKey\",\"output\":{}}".utf8))}
        let network=session();defer {network.invalidateAndCancel()}
        do {_=try await CompanionVoiceService(credential:"key",session:network).synthesize("你好",voice:"Cherry");XCTFail()}catch {}
    }
    func testDownloadRejectsUntrustedHostsCredentialsPortsAndProtocols() {
        for value in ["file:///etc/passwd","http://127.0.0.1/a","https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com.evil.test/a","https://user:pass@dashscope-result-bj.oss-cn-beijing.aliyuncs.com/a","https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com:444/a"] {XCTAssertThrowsError(try CompanionVoiceService.audioURL(value))}
    }
    func testMalformedWaveIsNotReportedAsSuccessfulVoice() async {
        VoiceProtocol.handler={request in
            if request.httpMethod=="POST" {return (200,Data("{\"output\":{\"audio\":{\"url\":\"https://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/a\"}}}".utf8))}
            return (200,Data("not audio".utf8))
        }
        let network=session();defer {network.invalidateAndCancel()}
        do {_=try await CompanionVoiceService(credential:"key",session:network).synthesize("你好",voice:"Cherry");XCTFail()}catch {XCTAssertTrue(error.localizedDescription.contains("文件"))}
    }
    func testEncryptedCacheReopensWithoutPersistingPlainWaveAndIsScopedByVoiceAndRoom() async throws {
        let key=try VaultCrypto.random(32),message=CompanionMessage(role:"assistant",content:"慢慢来。"),clip=try CompanionVoiceClip.validated([CompanionVoiceFixture.wave()])
        let id=CompanionVoiceCache.identifier(space:"female",message:message,voice:"Cherry")
        XCTAssertNotEqual(id,CompanionVoiceCache.identifier(space:"male",message:message,voice:"Cherry"));XCTAssertNotEqual(id,CompanionVoiceCache.identifier(space:"female",message:message,voice:"Ethan"))
        try await CompanionVoiceCache.shared.save(clip,id:id,key:key)
        let file=try PrivateFiles.url("companion-voice-"+id+".bin");defer {try? FileManager.default.removeItem(at:file)}
        let encrypted=try Data(contentsOf:file);XCTAssertFalse(encrypted.starts(with:Data("RIFF".utf8)))
        let saved=try await CompanionVoiceCache.shared.read(id,key:key);XCTAssertEqual(saved?.parts,clip.parts)
        let missing=try await CompanionVoiceCache.shared.read(id,key:VaultCrypto.random(32));XCTAssertNil(missing)
    }
    func testCorruptCacheIsRemovedSoMessageCanBeRegenerated() async throws {
        let key=try VaultCrypto.random(32),id=String(repeating:"a",count:64),file=try PrivateFiles.url("companion-voice-"+id+".bin")
        try Data("corrupt".utf8).write(to:file)
        let result=try await CompanionVoiceCache.shared.read(id,key:key);XCTAssertNil(result);XCTAssertFalse(FileManager.default.fileExists(atPath:file.path))
    }
}

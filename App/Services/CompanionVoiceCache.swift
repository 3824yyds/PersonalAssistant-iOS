import Foundation
import CryptoKit
import AVFoundation

struct CompanionVoiceClip:Codable,Sendable {
    let parts:[Data]
    let duration:Double
    var valid:Bool {!parts.isEmpty && parts.count<=8 && parts.reduce(0,{$0+$1.count})<=CompanionVoiceService.maximumBytes && duration.isFinite && duration>0 && duration<=600}
    static func validated(_ parts:[Data]) throws -> Self {
        var duration:Double=0
        for part in parts {
            let player=try AVAudioPlayer(data:part)
            guard player.duration.isFinite,player.duration>0 else {throw AppError.message("语音音频无法播放，请重试")};duration+=player.duration
        }
        let clip=Self(parts:parts,duration:duration)
        guard clip.valid else {throw AppError.message("语音音频无效，请查看文字或重试")};return clip
    }
}

actor CompanionVoiceCache {
    static let shared=CompanionVoiceCache()
    static func identifier(space:String,message:CompanionMessage,voice:String)->String {
        let components=["qwen3-tts-flash:v1",space,message.id,message.speakerID ?? "",voice,CompanionVoiceText.clean(message.content)]
        let data=(try? JSONEncoder().encode(components)) ?? Data()
        return SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()
    }
    private func file(_ id:String) throws -> URL {
        guard id.count==64,id.allSatisfy({$0.isHexDigit && !$0.isUppercase}) else {throw AppError.message("语音缓存标识无效")}
        return try PrivateFiles.url("companion-voice-"+id+".bin")
    }
    func read(_ id:String,key:Data) throws -> CompanionVoiceClip? {
        let url=try file(id)
        guard FileManager.default.fileExists(atPath:url.path) else {return nil}
        do {
            let encrypted=try PrivateFiles.boundedRead(url,maximum:12*1024*1024)
            let bytes=try AES.GCM.open(AES.GCM.SealedBox(combined:encrypted),using:SymmetricKey(data:key),authenticating:Data(id.utf8))
            let clip=try JSONDecoder().decode(CompanionVoiceClip.self,from:bytes)
            guard clip.valid else {throw AppError.message("缓存无效")}
            return clip
        } catch {try? FileManager.default.removeItem(at:url);return nil}
    }
    func save(_ clip:CompanionVoiceClip,id:String,key:Data) throws {
        guard clip.valid,key.count==32 else {throw AppError.message("资料库已锁定或语音无效")}
        let plain=try JSONEncoder().encode(clip)
        let encrypted=try AES.GCM.seal(plain,using:SymmetricKey(data:key),authenticating:Data(id.utf8)).combined!
        try encrypted.write(to:try file(id),options:[.atomic,.completeFileProtection])
        // A regenerable encrypted cache, separate from the 32MB vault and its backups.
        let directory=try PrivateFiles.directory()
        let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.fileSizeKey,.contentModificationDateKey]).filter {$0.lastPathComponent.hasPrefix("companion-voice-") && $0.pathExtension=="bin"}
        let entries=files.compactMap {url -> (URL,Int,Date)? in guard let values=try? url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey]) else {return nil};return (url,values.fileSize ?? 0,values.contentModificationDate ?? .distantPast)}.sorted {$0.2<$1.2}
        var total=entries.reduce(0,{$0+$1.1}),count=entries.count
        for (url,size,_) in entries where total>64*1024*1024 || count>100 {
            if url != (try file(id)) {try? FileManager.default.removeItem(at:url);total-=size;count-=1}
        }
    }
    func clear() throws {
        let files=try FileManager.default.contentsOfDirectory(at:PrivateFiles.directory(),includingPropertiesForKeys:nil)
        for file in files where file.lastPathComponent.hasPrefix("companion-voice-") && file.pathExtension=="bin" {try FileManager.default.removeItem(at:file)}
    }
}

import Foundation
import Combine
import AVFoundation

@MainActor final class CompanionVoiceController:NSObject,ObservableObject,AVAudioPlayerDelegate {
    @Published private(set) var processing=Set<String>()
    @Published private(set) var durations:[String:Double]=[:]
    @Published private(set) var errors:[String:String]=[:]
    @Published private(set) var playingID:String?
    @Published private(set) var configured=false
    private unowned let store:AppStore
    private let epoch:UUID
    private let space:CompanionSpace
    private var task:Task<Void,Never>?
    private var token=UUID()
    private var queue:[(CompanionMessage,CompanionPersona,CompanionVoiceSettings)]=[]
    private var manual=Set<String>()
    private var playback:[(String,CompanionVoiceClip,Double)]=[]
    private var current:(String,CompanionVoiceClip,Double)?
    private var part=0
    private var player:AVAudioPlayer?
    private var interruption:NSObjectProtocol?
    private var route:NSObjectProtocol?
    private var suppressAuto=false
    var visible=false
    private var unlocked:Bool {store.document != nil && store.epoch==epoch}
    init(store:AppStore,space:CompanionSpace) {
        self.store=store;self.space=space;epoch=store.epoch
        super.init();refreshConfiguration()
        interruption=NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) {[weak self] _ in Task {@MainActor in self?.stop()}}
        route=NotificationCenter.default.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) {[weak self] notification in
            let reason=notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason==AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {Task {@MainActor in self?.stop()}}
        }
    }
    deinit {if let interruption {NotificationCenter.default.removeObserver(interruption)};if let route {NotificationCenter.default.removeObserver(route)}}
    func refreshConfiguration() {
        #if DEBUG
        if CompanionVoiceFixture.enabled {configured=true;return}
        #endif
        configured=(try? Keychain.read("companion-qwen-tts")) != nil
    }
    private func credential() throws -> String {
        #if DEBUG
        if CompanionVoiceFixture.enabled {return "ui-voice-fixture"}
        #endif
        guard let data=try Keychain.read("companion-qwen-tts"),let value=String(data:data,encoding:.utf8),!value.isEmpty else {throw AppError.message("尚未配置自然语音，请打开语音设置领取免费额度并填写百炼 API Key")}
        return value
    }
    private func networkSession()->URLSession {
        #if DEBUG
        if CompanionVoiceFixture.enabled {return CompanionVoiceFixture.session()}
        #endif
        return CompanionVoiceNetworkPolicy.session()
    }
    func beginTurn() {stop();suppressAuto=false}
    func stop() {
        token=UUID();task?.cancel();task=nil;queue=[];manual=[];processing=[]
        stopPlayback();durations=[:];errors=[:]
    }
    private func stopPlayback() {
        player?.delegate=nil;player?.stop();player=nil;playingID=nil;playback=[];current=nil;part=0
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
    private func settings() throws -> CompanionVoiceSettings {try CompanionVoiceSettings.read(store.current)}
    func inspect(_ message:CompanionMessage,persona:CompanionPersona) async {
        guard unlocked,visible,durations[message.id]==nil,let config=try? settings() else {return}
        let stamp=token,key=store.key,id=CompanionVoiceCache.identifier(space:space.id,message:message,voice:config.voice(for:persona))
        if let clip=try? await CompanionVoiceCache.shared.read(id,key:key),unlocked,visible,token==stamp {durations[message.id]=clip.duration}
    }
    func enqueue(_ message:CompanionMessage,persona:CompanionPersona,play:Bool=false) {
        guard unlocked,visible,message.role=="assistant",!CompanionVoiceText.clean(message.content).isEmpty else {return}
        if play,playingID==message.id {suppressAuto=true;stopPlayback();return}
        if play {suppressAuto=true;stopPlayback();manual.insert(message.id)}
        if processing.contains(message.id) {return}
        errors[message.id]=nil
        do {
            let config=try settings()
            queue.append((message,persona,config));processing.insert(message.id)
            if task==nil {let stamp=token;task=Task {[weak self] in await self?.process(stamp)}}
        } catch {errors[message.id]="语音设置无效，请重新保存"}
    }
    private func process(_ stamp:UUID) async {
        defer {if token==stamp {task=nil}}
        while !queue.isEmpty,token==stamp,unlocked,visible,!Task.isCancelled {
            let (message,persona,config)=queue.removeFirst()
            let id=message.id,key=store.key,cacheID=CompanionVoiceCache.identifier(space:space.id,message:message,voice:config.voice(for:persona))
            do {
                let clip:CompanionVoiceClip
                if let cached=try await CompanionVoiceCache.shared.read(cacheID,key:key) {clip=cached}
                else {
                    guard unlocked,visible,token==stamp else {return}
                    guard store.cloudEnabled else {throw AppError.message("请先开启云端智能，再生成语音；已有文字不受影响")}
                    let secret=try credential()
                    let session=networkSession();defer {session.invalidateAndCancel()}
                    let parts=try await CompanionVoiceService(credential:secret,session:session).synthesize(message.content,voice:config.voice(for:persona))
                    try Task.checkCancellation();guard token==stamp,unlocked,visible else {return}
                    clip=try CompanionVoiceClip.validated(parts)
                    try await CompanionVoiceCache.shared.save(clip,id:cacheID,key:key)
                }
                try Task.checkCancellation();guard token==stamp,unlocked,visible else {return}
                durations[id]=clip.duration
                if manual.remove(id) != nil || (config.autoPlay && !suppressAuto) {playback.append((id,clip,config.rate));startNext()}
            } catch {
                guard token==stamp,unlocked,visible,!Task.isCancelled else {return}
                errors[id]=(error as? AppError)?.localizedDescription ?? "语音生成或下载失败，请检查网络后重试；文字回复已保留"
                manual.remove(id)
            }
            processing.remove(id)
        }
    }
    private func startNext() {
        guard player==nil,current==nil,!playback.isEmpty,unlocked,visible else {return}
        current=playback.removeFirst();part=0;playPart()
    }
    private func playPart() {
        guard let item=current,part<item.1.parts.count,unlocked,visible else {finishPlayback();return}
        do {
            let audio=AVAudioSession.sharedInstance();try audio.setCategory(.playback,mode:.spokenAudio);try audio.setActive(true)
            let next=try AVAudioPlayer(data:item.1.parts[part]);next.enableRate=true;next.rate=Float(item.2);next.delegate=self;next.prepareToPlay()
            player=next;playingID=item.0
            guard next.play() else {throw AppError.message("语音未能开始播放，请检查音频输出后重试")}
        } catch {errors[item.0]="语音未能播放，请检查音量和音频输出后重试";finishPlayback()}
    }
    private func finishPlayback() {
        player?.delegate=nil;player=nil;current=nil;playingID=nil;part=0
        if playback.isEmpty {try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)}else {startNext()}
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player:AVAudioPlayer,successfully flag:Bool) {
        Task {@MainActor [weak self] in
            guard let self,self.player === player else {return}
            self.player=nil
            if !flag {if let id=self.playingID {self.errors[id]="语音播放中断，请重试"};self.finishPlayback();return}
            self.part+=1;self.playPart()
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player:AVAudioPlayer,error:Error?) {
        Task {@MainActor [weak self] in guard let self,self.player === player else {return};if let id=self.playingID {self.errors[id]="语音文件无法播放，请重新生成"};self.finishPlayback()}
    }
}

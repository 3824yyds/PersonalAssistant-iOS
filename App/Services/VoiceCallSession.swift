import Foundation
import AVFoundation
import Combine

/// Alternates on-device recognition and system speech so playback is never fed back into the microphone.
@MainActor final class VoiceCallSession:NSObject,ObservableObject,AVSpeechSynthesizerDelegate {
    enum Phase:Equatable {case idle,connecting,listening,thinking,speaking,muted,paused,failed,ended}
    @Published private(set) var phase=Phase.idle
    @Published private(set) var isMuted=false
    @Published private(set) var transcript=""
    @Published private(set) var reply=""
    @Published private(set) var problem=""
    let speech=SpeechService()
    var onUtterance:((String)->Void)?
    var rate:Float=AVSpeechUtteranceDefaultSpeechRate
    private let synthesizer=AVSpeechSynthesizer()
    private var subscriptions=Set<AnyCancellable>()
    private var listeningTask:Task<Void,Never>?
    private var silenceTask:Task<Void,Never>?
    private var generation=UUID()
    private var active=false
    private var preview=false
    private var lastActivity=ProcessInfo.processInfo.systemUptime
    private var utterance:AVSpeechUtterance?

    override init() {
        super.init();synthesizer.delegate=self
        speech.$text.sink {[weak self] text in
            guard let self,self.active,self.phase == .listening else{return}
            self.transcript=text;self.lastActivity=ProcessInfo.processInfo.systemUptime
        }.store(in:&subscriptions)
        speech.$error.sink {[weak self] error in
            guard let self,let error,self.active,self.phase == .connecting || self.phase == .listening else{return}
            self.fail(error.replacingOccurrences(of:"请重新按住说话：",with:"请继续通话重试：").replacingOccurrences(of:"没有识别到文字，请靠近麦克风重新按住说话",with:"没有识别到文字，请靠近麦克风后点继续通话"))
        }.store(in:&subscriptions)
        speech.onFinal={[weak self] text in
            guard let self,self.active,!self.isMuted,self.phase == .listening else{return}
            self.silenceTask?.cancel();self.transcript=text;self.phase = .thinking
            self.onUtterance?(text)
        }
    }
    var status:String {
        switch phase {
        case .idle,.connecting:return "正在准备麦克风"
        case .listening:return "正在听"
        case .thinking:return "正在思考"
        case .speaking:return "正在说"
        case .muted:return "已静音"
        case .paused:return "通话已暂停"
        case .failed:return "暂时无法继续"
        case .ended:return "通话已结束"
        }
    }
    func start() {active=true;problem="";listen()}
    #if DEBUG
    func startPreview() {preview=true;active=true;phase = .listening}
    #endif
    private func listen() {
        guard active else{return}
        if isMuted {phase = .muted;return}
        if preview {phase = .listening;return}
        generation=UUID();let token=generation
        listeningTask?.cancel();silenceTask?.cancel();transcript="";phase = .connecting
        listeningTask=Task { [weak self] in
            guard let self else{return}
            await self.speech.start()
            guard !Task.isCancelled,self.active,self.generation==token else{return}
            guard self.speech.recording else {
                if self.phase != .failed {self.fail(self.speech.error ?? "麦克风未能启动，请重试")};return
            }
            self.lastActivity=ProcessInfo.processInfo.systemUptime;self.phase = .listening
            self.silenceTask=Task { [weak self] in
                while !Task.isCancelled {
                    do {try await Task.sleep(nanoseconds:200_000_000)}catch{return}
                    guard let self,self.active,self.generation==token,self.phase == .listening else{return}
                    let now=ProcessInfo.processInfo.systemUptime
                    if self.speech.meter.level>0.16 {self.lastActivity=now}
                    if !self.speech.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,now-self.lastActivity>1.3 {
                        self.speech.finish();return
                    }
                }
            }
        }
    }
    func finishTurn() {
        guard active,phase == .listening,!preview,!speech.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        silenceTask?.cancel();speech.finish()
    }
    func speak(_ text:String) {
        guard active,phase == .thinking else{return}
        let spoken=text.replacingOccurrences(of:"```[\\s\\S]*?```",with:"代码内容已保留在文字记录中。",options:.regularExpression)
            .replacingOccurrences(of:"\\[([^\\]]+)\\]\\([^)]*\\)",with:"$1",options:.regularExpression)
            .replacingOccurrences(of:"[#*_`>]",with:"",options:.regularExpression)
            .trimmingCharacters(in:.whitespacesAndNewlines)
        guard !spoken.isEmpty else{fail("没有收到可朗读的回复，请重试");return}
        reply=text;speech.cancel()
        do {
            let audio=AVAudioSession.sharedInstance()
            try audio.setCategory(.playback,mode:.spokenAudio,options:.duckOthers)
            try audio.setActive(true)
            let value=AVSpeechUtterance(string:spoken);value.voice=AVSpeechSynthesisVoice(language:"zh-CN");value.rate=rate
            utterance=value;phase = .speaking;synthesizer.speak(value)
        }catch{fail("朗读未能开始："+error.localizedDescription)}
    }
    func toggleMute() {
        isMuted.toggle()
        if preview {phase=isMuted ? .muted:.listening;return}
        if isMuted,phase == .connecting || phase == .listening {
            stopListening();phase = .muted
        }else if !isMuted,phase == .muted {listen()}
    }
    func interrupt() {
        guard active else{return}
        utterance=nil;synthesizer.stopSpeaking(at:.immediate)
        deactivatePlayback();listen()
    }
    func pause() {
        active=false;stopListening();utterance=nil;synthesizer.stopSpeaking(at:.immediate)
        deactivatePlayback();phase = .paused
    }
    func end() {pause();onUtterance=nil;phase = .ended}
    func fail(_ message:String) {
        phase = .failed;problem=message;stopListening();utterance=nil;synthesizer.stopSpeaking(at:.immediate);deactivatePlayback()
    }
    private func stopListening() {
        generation=UUID();listeningTask?.cancel();silenceTask?.cancel();listeningTask=nil;silenceTask=nil
        if !preview {speech.cancel()}
    }
    private func deactivatePlayback() {try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)}
    nonisolated func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didFinish utterance:AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self,self.active,self.utterance === utterance,self.phase == .speaking else{return}
            do {try await Task.sleep(nanoseconds:250_000_000)}catch{return}
            guard self.active,self.utterance === utterance,self.phase == .speaking else{return}
            self.utterance=nil;self.deactivatePlayback();self.listen()
        }
    }
}

import Foundation
import AVFoundation
import Combine

/// Alternates on-device recognition and system speech so playback is never fed back into the microphone.
@MainActor final class VoiceCallSession:NSObject,ObservableObject,AVSpeechSynthesizerDelegate {
    enum Phase:Equatable {case idle,connecting,listening,finishing,thinking,startingSpeech,speaking,muted,paused,failed,ended}
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
    private var detector=VoiceTurnDetector()
    private var finishingTask:Task<Void,Never>?
    private var synthesisStartTask:Task<Void,Never>?
    private var previewLevel=0.0
    private var utterance:AVSpeechUtterance?

    override init() {
        super.init();synthesizer.delegate=self
        speech.$text.removeDuplicates().sink {[weak self] text in
            self?.recognizedPartial(text)
        }.store(in:&subscriptions)
        speech.$error.sink {[weak self] error in
            guard let self,let error,self.active,self.phase == .connecting || self.phase == .listening || self.phase == .finishing else{return}
            if self.phase == .finishing,!self.transcript.isEmpty {self.acceptFinal(self.transcript);return}
            self.fail(error.replacingOccurrences(of:"请重新按住说话：",with:"请继续通话重试：").replacingOccurrences(of:"没有识别到文字，请靠近麦克风重新按住说话",with:"没有识别到文字，请靠近麦克风后点继续通话"))
        }.store(in:&subscriptions)
        speech.onFinal={[weak self] text in
            self?.acceptFinal(text)
        }
    }
    var status:String {
        switch phase {
        case .idle,.connecting:return "正在准备麦克风"
        case .listening:return "正在听"
        case .finishing:return "正在确认这句话"
        case .thinking:return "正在思考"
        case .startingSpeech:return "正在准备语音"
        case .speaking:return "正在说"
        case .muted:return "已静音"
        case .paused:return "通话已暂停"
        case .failed:return "暂时无法继续"
        case .ended:return "通话已结束"
        }
    }
    func start() {active=true;problem="";listen()}
    #if DEBUG
    func startPreview() {preview=true;active=true;listen()}
    func previewUtterance(_ text:String) {
        guard preview,active,!isMuted,phase == .listening else{return}
        // Exercise the production endpoint detector instead of jumping directly to a completed turn.
        previewLevel=0.95;recognizedPartial(text)
    }
    #endif
    private func listen() {
        guard active else{return}
        if isMuted {phase = .muted;return}
        generation=UUID();let token=generation
        listeningTask?.cancel();silenceTask?.cancel();finishingTask?.cancel()
        transcript="";detector=VoiceTurnDetector();previewLevel=0;phase = .connecting
        if preview {phase = .listening;monitorSilence(token:token);return}
        listeningTask=Task { [weak self] in
            guard let self else{return}
            await self.speech.start()
            guard !Task.isCancelled,self.active,self.generation==token else{return}
            guard self.speech.recording else {
                if self.phase != .failed {self.fail(self.speech.error ?? "麦克风未能启动，请重试")};return
            }
            self.phase = .listening;self.recognizedPartial(self.speech.text);self.monitorSilence(token:token)
        }
    }
    private func recognizedPartial(_ text:String) {
        guard active,phase == .listening || phase == .finishing else{return}
        transcript=text
        if phase == .listening {detector.observe(text:text,at:ProcessInfo.processInfo.systemUptime)}
    }
    private func monitorSilence(token:UUID) {
        silenceTask=Task { [weak self] in
            while !Task.isCancelled {
                do {try await Task.sleep(nanoseconds:200_000_000)}catch{return}
                guard let self,self.active,self.generation==token,self.phase == .listening else{return}
                let now=ProcessInfo.processInfo.systemUptime
                self.detector.observe(level:self.preview ? self.previewLevel:self.speech.meter.level,at:now)
                if self.detector.shouldFinish(at:now) {self.finishTurn();return}
            }
        }
    }
    func finishTurn() {
        guard active,phase == .listening,!transcript.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        phase = .finishing;silenceTask?.cancel()
        if preview {acceptFinal(transcript);return}
        let token=generation
        finishingTask=Task { [weak self] in
            do {try await Task.sleep(nanoseconds:2_200_000_000)}catch{return}
            guard let self,self.active,self.generation==token,self.phase == .finishing else{return}
            let text=self.speech.text.isEmpty ? self.transcript:self.speech.text
            self.speech.cancel();self.acceptFinal(text)
        }
        speech.finish()
    }
    private func acceptFinal(_ text:String) {
        guard active,!isMuted,phase == .listening || phase == .finishing else{return}
        let value=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.isEmpty else{fail("没有识别到文字，请继续通话后重试");return}
        silenceTask?.cancel();finishingTask?.cancel();finishingTask=nil
        transcript=value;phase = .thinking;onUtterance?(value)
    }

    func speak(_ text:String) {
        guard active,phase == .thinking else{return}
        let spoken=text.replacingOccurrences(of:"```[\\s\\S]*?```",with:"代码内容已保留在文字记录中。",options:.regularExpression)
            .replacingOccurrences(of:"\\[([^\\]]+)\\]\\([^)]*\\)",with:"$1",options:.regularExpression)
            .replacingOccurrences(of:"[#*_`>]",with:"",options:.regularExpression)
            .trimmingCharacters(in:.whitespacesAndNewlines)
        guard !spoken.isEmpty else{fail("没有收到可朗读的回复，请重试");return}
        reply=text
        if preview {phase = .speaking;return}
        speech.cancel()
        do {
            let audio=AVAudioSession.sharedInstance()
            try audio.setCategory(.playback,mode:.spokenAudio,options:.duckOthers)
            try audio.setActive(true)
            let value=AVSpeechUtterance(string:spoken);value.voice=AVSpeechSynthesisVoice(language:"zh-CN");value.rate=rate
            utterance=value;phase = .startingSpeech
            synthesisStartTask=Task { [weak self] in
                do {try await Task.sleep(nanoseconds:8_000_000_000)}catch{return}
                guard let self,self.active,self.utterance === value,self.phase == .startingSpeech else{return}
                self.fail("系统朗读未能启动，请检查系统语音资源后继续通话")
            }
            synthesizer.speak(value)
        }catch{fail("朗读未能开始："+error.localizedDescription)}
    }
    func toggleMute() {
        isMuted.toggle()
        if preview {if isMuted {stopListening();phase = .muted}else{listen()};return}
        if isMuted,phase == .connecting || phase == .listening || phase == .finishing {
            stopListening();phase = .muted
        }else if !isMuted,phase == .muted {listen()}
    }
    func interrupt() {
        guard active else{return}
        synthesisStartTask?.cancel();utterance=nil;synthesizer.stopSpeaking(at:.immediate)
        deactivatePlayback();listen()
    }
    func pause() {
        active=false;stopListening();synthesisStartTask?.cancel();utterance=nil;synthesizer.stopSpeaking(at:.immediate)
        deactivatePlayback();phase = .paused
    }
    func end() {pause();onUtterance=nil;phase = .ended}
    func fail(_ message:String) {
        phase = .failed;problem=message;stopListening();synthesisStartTask?.cancel();utterance=nil;synthesizer.stopSpeaking(at:.immediate);deactivatePlayback()
    }
    private func stopListening() {
        generation=UUID();listeningTask?.cancel();silenceTask?.cancel();finishingTask?.cancel();listeningTask=nil;silenceTask=nil;finishingTask=nil
        if !preview {speech.cancel()}
    }
    private func deactivatePlayback() {try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)}
    nonisolated func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didStart utterance:AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self,self.active,self.utterance === utterance,self.phase == .startingSpeech else{return}
            self.synthesisStartTask?.cancel();self.phase = .speaking
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didFinish utterance:AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self,self.active,self.utterance === utterance,(self.phase == .speaking || self.phase == .startingSpeech) else{return}
            do {try await Task.sleep(nanoseconds:250_000_000)}catch{return}
            guard self.active,self.utterance === utterance,(self.phase == .speaking || self.phase == .startingSpeech) else{return}
            self.synthesisStartTask?.cancel();self.utterance=nil;self.deactivatePlayback();self.listen()
        }
    }
}

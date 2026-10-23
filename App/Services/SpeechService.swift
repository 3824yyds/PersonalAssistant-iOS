import Foundation
import AVFoundation
import Speech
import Combine

@MainActor final class SpeechMeter:ObservableObject {
    @Published private(set) var level:Double=0
    private var last=Date.distantPast
    func update(_ value:Double) {
        guard Date().timeIntervalSince(last)>1.0/24 else {return}
        last=Date();level=value
    }
    func reset() {level=0}
}

@MainActor final class SpeechService:ObservableObject {
    @Published var recording=false
    @Published var finishing=false
    @Published var text=""
    @Published var error:String?
    let meter=SpeechMeter()
    private let engine=AVAudioEngine()
    private var recognition:SFSpeechRecognitionTask?
    private var request:SFSpeechAudioBufferRecognitionRequest?
    private var timer:Task<Void,Never>?
    private var tapped=false
    private var generation=UUID()
    var onFinal:((String)->Void)?

    func prepare() async -> Bool {
        let speechAllowed=await withCheckedContinuation {continuation in SFSpeechRecognizer.requestAuthorization {continuation.resume(returning:$0 == .authorized)}}
        let audioAllowed=await withCheckedContinuation {continuation in AVAudioApplication.requestRecordPermission {continuation.resume(returning:$0)}}
        guard speechAllowed && audioAllowed else {error="请到系统设置允许麦克风和语音识别权限";return false}
        return true
    }
    func start() async {
        cancel();error=nil;text=""
        let token=generation
        guard await prepare(),generation==token else {return}
        guard let recognizer=SFSpeechRecognizer(locale:Locale(identifier:"zh-CN")),recognizer.isAvailable else {error="普通话识别暂不可用，请检查系统语音语言设置";return}
        guard recognizer.supportsOnDeviceRecognition else {error="系统尚未准备好离线普通话资源，请先使用键盘听写，或到系统设置准备中文语音资源";return}
        do {
            let session=AVAudioSession.sharedInstance();try session.setCategory(.record,mode:.measurement,options:.duckOthers);try session.setActive(true)
            let request=SFSpeechAudioBufferRecognitionRequest();request.shouldReportPartialResults=true;request.requiresOnDeviceRecognition=true;request.taskHint = .dictation
            self.request=request
            let input=engine.inputNode,format=input.outputFormat(forBus:0)
            guard format.sampleRate>0 else {throw AppError.message("麦克风没有可用音频，请重试")}
            input.installTap(onBus:0,bufferSize:1024,format:format) { [weak self] buffer,_ in
                request.append(buffer)
                if let values=buffer.floatChannelData?[0] {
                    var sum:Float=0
                    for i in stride(from:0,to:Int(buffer.frameLength),by:8) {sum += values[i]*values[i]}
                    let count=max(1,Int(buffer.frameLength)/8)
                    let rms=sqrt(Double(sum)/Double(count)),level=min(1,max(0,(20*log10(max(rms,0.00001))+55)/45))
                    Task { @MainActor in guard self?.generation==token else {return};self?.meter.update(level) }
                }
            };tapped=true
            recognition=recognizer.recognitionTask(with:request) { [weak self] result,error in
                Task { @MainActor in
                    guard let self,self.generation==token else {return}
                    if let result {self.text=self.simplified(result.bestTranscription.formattedString);if result.isFinal {self.finishResult()}}
                    else if let error {
                        if self.finishing && !self.text.isEmpty {self.finishResult()}
                        else {let message=error.localizedDescription;self.cancel();self.error="语音识别中断，请重新按住说话："+message}
                    }
                }
            }
            engine.prepare();try engine.start();recording=true
            timer=Task {try? await Task.sleep(nanoseconds:55_000_000_000);if !Task.isCancelled,self.generation==token {self.finish()}}
        }catch {cancel();self.error="录音未能开始，请检查麦克风后重试："+error.localizedDescription}
    }
    func finish() {
        // Also cancels a pending permission/start operation when the finger is released early.
        guard recording else {if !finishing {cancel()};return}
        stopAudio();finishing=true;request?.endAudio();timer?.cancel();let token=generation
        timer=Task {try? await Task.sleep(nanoseconds:1_500_000_000);if !Task.isCancelled,self.generation==token {self.finishResult()}}
    }
    private func finishResult() {
        let value=text.trimmingCharacters(in:.whitespacesAndNewlines);cancel()
        if !value.isEmpty {onFinal?(value)}else{error="没有识别到文字，请靠近麦克风重新按住说话"}
    }
    private func stopAudio() {
        engine.stop();if tapped {engine.inputNode.removeTap(onBus:0);tapped=false};recording=false
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
    func cancel() {
        generation=UUID();timer?.cancel();timer=nil;recognition?.cancel();recognition=nil;request?.endAudio();request=nil
        finishing=false;stopAudio();meter.reset()
    }
    private func simplified(_ value:String)->String {value.applyingTransform(StringTransform("Traditional-Simplified"),reverse:false) ?? value}
}

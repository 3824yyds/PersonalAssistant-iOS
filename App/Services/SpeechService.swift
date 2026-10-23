import Foundation
import AVFoundation
import Speech
import Combine

@MainActor final class SpeechService: ObservableObject {
    @Published var recording = false
    @Published var text = ""
    @Published var error: String?
    private let engine = AVAudioEngine()
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var timer: Task<Void,Never>?
    private var tapped = false
    var onFinal: ((String)->Void)?
    func start() async {
        cancel(); error = nil; text = ""
        let speechAllowed = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning:$0 == .authorized) } }
        let audioAllowed = await withCheckedContinuation { continuation in AVAudioApplication.requestRecordPermission { continuation.resume(returning:$0) } }
        guard speechAllowed && audioAllowed else { error = "请到系统设置允许麦克风和语音识别权限"; return }
        guard let recognizer = SFSpeechRecognizer(locale:Locale(identifier:"zh-CN")), recognizer.isAvailable else { error = "中文语音识别暂不可用，请检查系统语音语言设置"; return }
        guard recognizer.supportsOnDeviceRecognition else { error = "这台设备尚不支持离线普通话识别，请先在系统设置中准备中文语音资源，或使用键盘听写"; return }
        do {
            let session = AVAudioSession.sharedInstance(); try session.setCategory(.record,mode:.measurement,options:.duckOthers); try session.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest(); request.shouldReportPartialResults = true; request.requiresOnDeviceRecognition = true; request.taskHint = .dictation
            self.request = request
            let input = engine.inputNode, format = input.outputFormat(forBus:0)
            guard format.sampleRate > 0 else { throw AppError.message("麦克风没有可用音频，请重试") }
            input.installTap(onBus:0,bufferSize:1024,format:format) { buffer,_ in request.append(buffer) }; tapped = true
            recognition = recognizer.recognitionTask(with:request) { result,error in
                Task { @MainActor in
                    if let result { self.text = self.simplified(result.bestTranscription.formattedString); if result.isFinal { self.finishResult() } }
                    else if let error { if self.recording { self.error = "语音识别中断，请重试或使用键盘听写：" + error.localizedDescription }; self.stopAudio() }
                }
            }
            engine.prepare(); try engine.start(); recording = true
            timer = Task { try? await Task.sleep(nanoseconds:55_000_000_000); if !Task.isCancelled { self.finish() } }
        } catch { self.error = error.localizedDescription; cancel() }
    }
    func finish() { stopAudio(); request?.endAudio(); timer?.cancel(); timer = Task { try? await Task.sleep(nanoseconds:3_000_000_000); if !Task.isCancelled { self.finishResult() } } }
    private func finishResult() { let value = text; cancel(); if !value.isEmpty { onFinal?(value) } }
    private func stopAudio() { engine.stop(); if tapped { engine.inputNode.removeTap(onBus:0); tapped = false }; recording = false; try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation) }
    func cancel() { timer?.cancel(); timer = nil; recognition?.cancel(); recognition = nil; request?.endAudio(); request = nil; stopAudio() }
    private func simplified(_ value: String) -> String { value.applyingTransform(StringTransform("Traditional-Simplified"),reverse:false) ?? value }
}

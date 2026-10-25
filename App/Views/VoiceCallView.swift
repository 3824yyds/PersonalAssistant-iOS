import SwiftUI
import AVFoundation
import Combine

struct VoiceCallView:View {
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var call=VoiceCallSession()
    @State private var awaitingReply:String?
    @State private var replyWaitTask:Task<Void,Never>?
    @State private var transcriptVisible=false
    @AppStorage("voice.showCaptions") private var captions=true
    @AppStorage("voice.rate") private var rate=0.5
    let onSend:(String)->Void
    private var modelName:String {store.cloudEnabled && store.hasAPIKey ? (store.model=="deepseek-v4-pro" ? "Pro":"Flash"):"本机回答"}
    var body:some View {
        VStack(spacing:0) {
            HStack {
                Button {transcriptVisible=true} label:{Image(systemName:"text.bubble").font(.system(size:20)).frame(width:44,height:44).appGlass(Circle(),interactive:true)}
                    .accessibilityLabel("查看通话文字").accessibilityIdentifier("voice.call.transcript")
                Spacer()
                VStack(spacing:3) {Text("语音对话").font(.subheadline.weight(.medium)).accessibilityIdentifier("voice.call.title");Text(modelName).font(.caption).foregroundStyle(.secondary)}
                Spacer()
                Menu {
                    Toggle("显示字幕",isOn:$captions)
                    Picker("朗读语速",selection:$rate) {Text("慢速").tag(0.42);Text("正常").tag(0.5);Text("稍快").tag(0.56)}
                } label:{Image(systemName:"slider.horizontal.3").font(.system(size:20)).frame(width:44,height:44).appGlass(Circle(),interactive:true)}.accessibilityLabel("语音选项")
            }.padding(.horizontal,16).padding(.top,8)
            Spacer(minLength:20)
            Button(action:orbAction) {VoiceCallOrb(meter:call.speech.meter,phase:call.phase).frame(width:240,height:240)}
                .buttonStyle(.plain).accessibilityLabel(call.phase == .speaking || call.phase == .thinking ? "打断回复，继续说话":"说完发送")
                .accessibilityIdentifier("voice.call.orb")
            VStack(spacing:10) {
                Text(call.status).font(.title3.weight(.medium)).accessibilityIdentifier("voice.call.status")
                if !call.problem.isEmpty {Text(call.problem).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)}
                else {Text(call.phase == .speaking || call.phase == .thinking ? "点一下云雾球，打断后继续说":"说完停顿片刻，自动发送").font(.caption).foregroundStyle(.secondary)}
                if call.phase == .failed || call.phase == .paused {Button("继续通话") {call.start()}.buttonStyle(.bordered).accessibilityIdentifier("voice.call.resume")}
                if captions {
                    Text(call.phase == .speaking ? call.reply:call.transcript).font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(4).multilineTextAlignment(.center).frame(minHeight:40).accessibilityIdentifier("voice.call.caption")
                }
            }.padding(.horizontal,28).padding(.top,28)
            Spacer(minLength:20)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-voice-call-fixture") {
                Button("模拟一句语音") {call.previewUtterance("你好")}.accessibilityIdentifier("voice.call.fixtureUtterance")
            }
            #endif
            HStack(spacing:24) {
                Button {call.toggleMute()} label:{Image(systemName:call.isMuted ? "mic.slash.fill":"mic.fill").font(.system(size:24)).frame(width:64,height:64).appGlass(Circle(),interactive:true)}
                    .accessibilityLabel(call.isMuted ? "取消静音":"静音麦克风").accessibilityValue(call.isMuted ? "已静音":"未静音").accessibilityIdentifier("voice.call.mute")
                Button {close()} label:{Image(systemName:"xmark").font(.system(size:26,weight:.medium)).foregroundStyle(.white).frame(width:64,height:64).background(.black,in:Circle())}
                    .accessibilityLabel("结束通话").accessibilityIdentifier("voice.call.end")
            }.padding(.bottom,24)
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background {ConversationBackground()}.appClearChrome()
            .onAppear {
                call.rate=Float(rate)
                call.onUtterance={text in
                    guard store.document != nil,!store.assistantBusy else{call.fail("当前对话尚未就绪，请稍后继续");return}
                    onSend(text);awaitingReply=store.activeReplyID
                    guard let id=awaitingReply,let task=store.activeTask else{call.fail(store.error ?? "这句话未能发送，请重试");return}
                    replyWaitTask=Task {
                        await task.value
                        guard !Task.isCancelled,awaitingReply==id,call.phase == .thinking else{return}
                        awaitingReply=nil
                        if let answer=store.messages.first(where:{$0.id==id}),!answer.content.isEmpty {call.speak(answer.content)}
                        else {call.fail(store.error ?? "没有收到回复，请继续通话后重试")}
                    }
                }
                store.speech=call.speech
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-voice-call-fixture") {call.startPreview();return}
                #endif
                call.start()
            }
            .onChange(of:rate) {_,value in call.rate=Float(value)}
            .onChange(of:scenePhase) {_,phase in
                // Permission alerts temporarily make the app inactive before any recording starts.
                if phase == .background || (phase == .inactive && call.phase != .connecting) {pause()}
            }
            .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.interruptionNotification)) {note in
                if let kind=note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,kind==AVAudioSession.InterruptionType.began.rawValue {pause()}
            }
            .onReceive(NotificationCenter.default.publisher(for:AVAudioSession.routeChangeNotification)) {note in
                if let reason=note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,reason==AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {pause()}
            }
            .onDisappear {cancelReply();call.end();if store.speech === call.speech {store.speech=nil}}
            .sheet(isPresented:$transcriptVisible) {
                NavigationStack {ScrollView {LazyVStack(alignment:.leading,spacing:18) {ForEach(store.messages) {message in
                    VStack(alignment:.leading,spacing:5) {Text(message.role=="user" ? "你":"助理").font(.caption).foregroundStyle(.secondary);Text(message.content).textSelection(.enabled)}.frame(maxWidth:.infinity,alignment:.leading)
                }}.padding()}.navigationTitle("通话文字").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.confirmationAction) {Button("完成") {transcriptVisible=false}}}}
            }
    }
    private func cancelReply() {
        replyWaitTask?.cancel();replyWaitTask=nil
        let owned=awaitingReply;awaitingReply=nil
        if let owned,store.activeReplyID==owned {store.cancelReply()}
    }
    private func pause() {cancelReply();call.pause()}
    private func close() {cancelReply();call.end();Task {await store.saveHistory()};dismiss()}
    private func orbAction() {
        if call.phase == .speaking || call.phase == .thinking {cancelReply();call.interrupt()}
        else if call.phase == .listening {call.finishTurn()}
    }
}
private struct VoiceCallOrb:View {
    @ObservedObject var meter:SpeechMeter
    let phase:VoiceCallSession.Phase
    var body:some View {
        AIOrb(active:phase == .listening || phase == .speaking || phase == .thinking)
            .scaleEffect(phase == .listening ? 1+meter.level*0.07:1)
            .animation(.easeOut(duration:0.15),value:meter.level)
    }
}

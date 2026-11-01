import SwiftUI

struct CompanionMessageBody:View {
    let message:CompanionMessage
    @ObservedObject var session:CompanionSession
    @ObservedObject var voice:CompanionVoiceController
    var configure:()->Void
    @Environment(\.colorScheme) private var scheme
    private var isVoice:Bool {message.role=="assistant" && (message.voiceRequested==true || voice.processing.contains(message.id) || voice.durations[message.id] != nil || voice.errors[message.id] != nil)}
    var body:some View {
        if isVoice {
            CompanionVoiceBubble(message:message,session:session,voice:voice,configure:configure)
        } else {
            Text(.init(WebEvidence.cited(CompanionGroupChat.text(message),sources:message.sources)))
                .padding(.horizontal,15).padding(.vertical,12)
                .background(message.role=="user" ? Theme.accent.opacity(0.12):Theme.panel(scheme).opacity(0.85),in:RoundedRectangle(cornerRadius:20))
                .accessibilityIdentifier("companion.message."+message.id)
        }
    }
}

private struct CompanionVoiceBubble:View {
    let message:CompanionMessage
    @ObservedObject var session:CompanionSession
    @ObservedObject var voice:CompanionVoiceController
    var configure:()->Void
    @Environment(\.colorScheme) private var scheme
    @State private var expanded=false
    private var working:Bool {voice.processing.contains(message.id)}
    private var playing:Bool {voice.playingID==message.id}
    private var transcriptVisible:Bool {expanded || session.data.profile.voiceMode != .voice || voice.errors[message.id] != nil || !voice.configured}
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:12) {
                Button {
                    if !voice.configured,voice.durations[message.id]==nil {configure()}else {session.requestVoice(message)}
                } label:{
                    HStack(spacing:12) {
                        if working {ProgressView().controlSize(.small)}else {Image(systemName:playing ? "stop.fill":"play.fill")}
                        Image(systemName:"waveform").font(.title3)
                        Text(working ? "正在生成语音":(voice.durations[message.id].map {"\(Int(ceil($0)))″"} ?? (voice.configured ? "点按生成语音":"配置自然语音"))).font(.subheadline.monospacedDigit())
                    }.frame(minWidth:140,minHeight:32,alignment:.leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(working).foregroundStyle(Theme.accent)
                    .accessibilityLabel(playing ? "停止语音":(working ? "正在生成语音":"播放伙伴语音")).accessibilityIdentifier("companion.voice.play."+message.id)
                if working {Button {voice.stop()} label:{Image(systemName:"xmark.circle")}.accessibilityLabel("取消语音生成")}
            }
            if let error=voice.errors[message.id] {
                Text(error).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("companion.voice.error")
                HStack {
                    Button("重试语音") {session.requestVoice(message)}.disabled(working)
                    Button("语音设置",action:configure)
                }.font(.caption)
            }
            if transcriptVisible {
                Text(.init(WebEvidence.cited(CompanionGroupChat.text(message),sources:message.sources))).accessibilityIdentifier("companion.message."+message.id)
            }
            if session.data.profile.voiceMode == .voice,voice.errors[message.id]==nil,voice.configured {
                Button(expanded ? "收起文字":"查看文字") {expanded.toggle()}.font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("companion.voice.transcript."+message.id)
            }
        }.padding(.horizontal,15).padding(.vertical,12).background(Theme.panel(scheme).opacity(0.9),in:RoundedRectangle(cornerRadius:20))
            .accessibilityIdentifier("companion.voice.bubble."+message.id)
            .task(id:message.id) {await voice.inspect(message,persona:CompanionPersona(rawValue:message.speakerID ?? "") ?? session.persona)}
    }
}

struct CompanionVoiceSettingsView:View {
    @ObservedObject var session:CompanionSession
    @EnvironmentObject private var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var config=CompanionVoiceSettings()
    @State private var mode:CompanionVoiceMode = .both
    @State private var secret=""
    @State private var saving=false
    @State private var configured=false
    @State private var notice:String?
    var body:some View {
        Form {
            Section {
                Picker("本聊天回复方式",selection:$mode) {ForEach(CompanionVoiceMode.allCases) {Text($0.title).tag($0)}}.accessibilityIdentifier("companion.voice.mode")
                Toggle("自动播放新语音",isOn:$config.autoPlay).accessibilityIdentifier("companion.voice.autoplay")
            } footer:{Text("选择语音后，伙伴会尽量用简短口语回复。生成失败时仍可查看完整文字。自动播放仅在聊天页打开时发生，群聊依次播放。")}
            Section("两位伙伴的声音") {
                Picker("女生声音",selection:$config.female) {ForEach(CompanionVoiceSettings.femaleVoices,id:\.self) {Text(CompanionVoiceSettings.label($0)).tag($0)}}.accessibilityIdentifier("companion.voice.female")
                Picker("男生声音",selection:$config.male) {ForEach(CompanionVoiceSettings.maleVoices,id:\.self) {Text(CompanionVoiceSettings.label($0)).tag($0)}}.accessibilityIdentifier("companion.voice.male")
                VStack(alignment:.leading,spacing:10) {
                    HStack {Text("播放语速");Spacer();Text(String(format:"%.1f倍",config.rate)).monospacedDigit().foregroundStyle(.secondary)}
                    Slider(value:$config.rate,in:0.8...1.2,step:0.1).accessibilityLabel("播放语速").accessibilityIdentifier("companion.voice.rate")
                }
            }
            Section {
                Label("阿里云千问自然语音",systemImage:"waveform")
                Text(configured ? "语音密钥已保存":"尚未配置语音服务").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("companion.voice.configuration")
                SecureField(configured ? "填写新密钥以替换（留空保留）":"北京地域百炼 API Key",text:$secret).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("companion.voice.key")
                Link("开通服务并领取免费额度",destination:URL(string:"https://bailian.console.aliyun.com/")!)
                Link("查看免费额度、有效期与价格",destination:URL(string:"https://help.aliyun.com/zh/model-studio/model-pricing")!)
                Link("如何获取 API Key",destination:URL(string:"https://help.aliyun.com/zh/model-studio/get-api-key")!)
            } footer:{Text("需要你自己的百炼账号。官方演示不能代替聊天语音接口，免费额度不是长期无限免费。此处使用北京地域 qwen3-tts-flash。可以在百炼开启免费额度用完即停，避免超额费用。")}
            Section {
                Text("语音合成仅发送这条回复的朗读文本，不发送整段聊天和伙伴记忆。密钥保存在本机钥匙串；音频在本机加密缓存，换声音后再次生成会消耗额度。语音缓存不放入资料库备份，恢复后可由文字重新生成。分享或导出聊天时也不包含密钥。").font(.footnote).foregroundStyle(.secondary)
                Button("清理本机语音缓存") {Task {session.voice.stop();do {try await CompanionVoiceCache.shared.clear();notice="语音缓存已清理，聊天文字保留"}catch {notice="语音缓存未能清理，请重试"}}}.disabled(saving)
                if configured {Button("移除语音密钥",role:.destructive) {session.removeVoiceKey();configured=false;secret=""}}
            }
            if let notice {Section {Text(notice).font(.footnote).foregroundStyle(.secondary)}}
            if let error=session.error {Section {Text(error).font(.footnote).foregroundStyle(.red)}}
        }.scrollContentBackground(.hidden).background {ConversationBackground()}.navigationTitle("伙伴语音").navigationBarTitleDisplayMode(.inline)
            .onAppear {do {config=try CompanionVoiceSettings.read(store.current)}catch {notice="原语音设置无法读取，请重新选择后保存"};mode=session.data.profile.voiceReply ?? .both;session.voice.refreshConfiguration();configured=session.voice.configured}
            .onDisappear {secret=""}
            .interactiveDismissDisabled(saving)
            .disabled(saving)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}}
                ToolbarItem(placement:.confirmationAction) {Button("保存") {saving=true;Task {let saved=await session.saveVoiceSettings(config,mode:mode,secret:secret);saving=false;if saved {secret="";dismiss()}}}.accessibilityIdentifier("companion.voice.save")}
            }
    }
}

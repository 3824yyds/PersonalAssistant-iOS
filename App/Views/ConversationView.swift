import UIKit
import SwiftUI

private struct BottomPreference:PreferenceKey {
    static let defaultValue:CGFloat=0
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat) {value=nextValue()}
}
struct ConversationView:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.colorScheme) var scheme
    @StateObject var speech=SpeechService()
    var input:String {get {store.chatDraft} nonmutating set {store.chatDraft=newValue}}
    var finance:Bool {store.financeMode}
    @State var voiceMode=false
    @State var holding=false
    @State var gestureStarted=false
    @State var voiceAction=VoiceReleaseAction.send
    @State var pendingVoice:VoiceReleaseAction?
    @Environment(\.scenePhase) private var scenePhase
    @State var history=false
    @State var modelMenu=false
    @State var follow=true
    @State var viewport:CGFloat=0
    @State var availableModels=["deepseek-chat","deepseek-reasoner"]
    @FocusState var focused:Bool
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:12) {
                Picker("对话模式",selection:Binding(get:{finance},set:{value in Task {await store.newChat(finance:value)}})) {Text("聊天").tag(false);Text("财务咨询").tag(true)}.pickerStyle(.segmented).disabled(store.assistantBusy)
                Button {focused=false;history=true} label:{Image(systemName:"clock.arrow.circlepath").font(.system(size:19)).frame(width:36,height:36)}.accessibilityLabel("历史对话")
            }.padding(.horizontal,16).padding(.bottom,10)
            GeometryReader {geometry in
                ScrollViewReader {proxy in
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:22) {
                            if store.messages.isEmpty {welcome}
                            ForEach(store.messages) {message in ChatBubble(message:message,working:store.assistantBusy && message.id==store.messages.last?.id)}
                            Color.clear.frame(height:1).id("latest").background(GeometryReader {g in Color.clear.preference(key:BottomPreference.self,value:g.frame(in:.named("conversationScroll")).minY)})
                        }.padding(16)
                    }.coordinateSpace(name:"conversationScroll").scrollDismissesKeyboard(.interactively)
                        .onPreferenceChange(BottomPreference.self) {y in follow=y<geometry.size.height+80}
                        .onChange(of:store.messages.last?.content) {_,_ in if follow {proxy.scrollTo("latest",anchor:.bottom)}}
                        .onChange(of:store.messages.count) {_,_ in if follow {proxy.scrollTo("latest",anchor:.bottom)}}
                        .overlay(alignment:.bottom) {if !follow && !store.messages.isEmpty {Button {follow=true;withAnimation(Theme.normal) {proxy.scrollTo("latest",anchor:.bottom)}} label:{Label("回到最新",systemImage:"arrow.down").font(.caption).padding(10).background(.regularMaterial,in:Capsule())}.padding(.bottom,8)}}
                }
            }
            composer.layoutPriority(1)
        }
            .background(Theme.background(scheme)).navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {if !finance {ToolbarItem(placement:.topBarLeading) {Menu {
                ForEach(availableModels,id:\.self) {m in Button {Task {await store.setting("model",.string(m))}} label:{HStack {Text(modelLabel(m));if store.model==m {Image(systemName:"checkmark")}}}}
                Button("刷新可用模型") {Task {do {availableModels=try await AIService.models()}catch{store.present(error)}}}
            } label:{HStack(spacing:4) {Text(modelLabel(store.model)).font(.system(size:15,weight:.semibold));Image(systemName:"chevron.down").font(.system(size:9,weight:.semibold))}}.disabled(store.assistantBusy)}}}
            .onAppear {store.speech=speech;speech.onFinal={text in let action=pendingVoice;pendingVoice=nil;holding=false;store.voiceCapture=nil;if action == .send {let draft=input;input=text;send();input=draft}else{input+=(input.isEmpty ? "":" ")+text;voiceMode=false;focused=true}};if !availableModels.contains(store.model) {availableModels.append(store.model)}}
            .onChange(of:speech.error) {_,error in if let error {cancelVoice();store.error=error;speech.error=nil}}
            .onDisappear {cancelVoice();speech.onFinal=nil;if store.speech === speech {store.speech=nil}}
            .onChange(of:scenePhase) {_,phase in if phase != .active {cancelVoice()}}
            .sheet(isPresented:$history) {NavigationStack {ChatHistoryView {session in Task {await store.newChat(finance:session.finance ?? finance);store.messages=session.messages;store.activeSessionID=session.id;history=false}}}.environmentObject(store)}
    }
    var composer:some View {
        HStack(alignment:.bottom,spacing:8) {
            Button {
                focused=false;voiceMode.toggle()
                if voiceMode {Task {_=await speech.prepare()}}
            } label:{Image(systemName:voiceMode ? "keyboard":"waveform").font(.system(size:20)).frame(width:36,height:42)}
                .accessibilityLabel(voiceMode ? "切换键盘输入":"切换语音输入").disabled(store.assistantBusy || speech.finishing)
            if voiceMode {
                Text(holding ? "松开发送文字":"按住 说话").font(.system(size:16,weight:.medium)).frame(maxWidth:.infinity,minHeight:42)
                    .background(Theme.accent.opacity(holding ? 0.16:0.04),in:Capsule()).contentShape(Capsule())
                    .gesture(voiceGesture).accessibilityLabel("按住说话").accessibilityAddTraits(.isButton)
                    .accessibilityHint("左滑取消，右滑转文字。也可使用开始录音、完成录音和取消录音操作")
                    .accessibilityAction(named:Text("开始录音")) {beginVoice()}
                    .accessibilityAction(named:Text("完成录音")) {endVoice(.text)}
                    .accessibilityAction(named:Text("取消录音")) {cancelVoice()}
            } else {
                TextField(finance ? "问问你的财务状况…":"发消息…",text:$store.chatDraft,axis:.vertical).lineLimit(1...6).font(.system(size:15)).padding(.vertical,11).focused($focused).accessibilityIdentifier("chat.input")
            }
            Menu {
                Section("对话模式") {
                    Button {if finance {Task {await store.newChat(finance:false)}}} label:{Label("聊天",systemImage:finance ? "bubble.left.and.bubble.right":"checkmark")}
                    Button {if !finance {Task {await store.newChat(finance:true)}}} label:{Label("财务咨询",systemImage:finance ? "checkmark":"chart.bar.xaxis")}
                }
                Section("对话") {
                    Button("新对话",systemImage:"square.and.pencil") {focused=false;Task {await store.newChat()}}.accessibilityIdentifier("chat.menu.new")
                    Button("历史对话",systemImage:"clock.arrow.circlepath") {focused=false;history=true}.accessibilityIdentifier("chat.menu.history")
                }
            } label:{Image(systemName:"plus").font(.system(size:20)).frame(width:36,height:42)}.accessibilityLabel("聊天功能").disabled(store.assistantBusy || holding || speech.finishing)
            if !voiceMode {
                Button {if store.assistantBusy {store.cancelReply()}else{send()}} label:{Image(systemName:store.assistantBusy ? "stop.fill":"arrow.up").font(.system(size:16,weight:.semibold)).frame(width:34,height:34).background(Theme.accent,in:Circle()).foregroundStyle(.white)}.accessibilityLabel(store.assistantBusy ? "停止回复":"发送").disabled(!store.assistantBusy && input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).padding(.bottom,4)
            }
        }.padding(.horizontal,8).padding(.vertical,4).appGlass(RoundedRectangle(cornerRadius:24)).padding(.horizontal,12).padding(.bottom,8)
    }
    var voiceGesture:some Gesture {
        DragGesture(minimumDistance:0,coordinateSpace:.global)
            .onChanged {value in
                if !gestureStarted {beginVoice()}
                guard holding else {return}
                let action=VoiceGesture.action(horizontal:value.translation.width,vertical:value.translation.height)
                if voiceAction != action {voiceAction=action;store.voiceCapture=VoiceCaptureState(action:action);UISelectionFeedbackGenerator().selectionChanged()}
            }
            .onEnded {_ in gestureStarted=false;guard holding else {return};endVoice(voiceAction)}
    }
    func beginVoice() {
        guard !store.assistantBusy,!speech.finishing else {return}
        focused=false;holding=true;gestureStarted=true;voiceAction = .send;pendingVoice=nil
        store.voiceCapture=VoiceCaptureState();UIImpactFeedbackGenerator(style:.light).impactOccurred()
        Task {await speech.start();if !speech.recording && !speech.finishing {holding=false;store.voiceCapture=nil}}
    }
    func endVoice(_ action:VoiceReleaseAction) {
        holding=false
        if action == .cancel {cancelVoice();return}
        guard speech.recording else {cancelVoice();return}
        pendingVoice=action;store.voiceCapture=VoiceCaptureState(action:action,finishing:true);speech.finish()
    }
    func cancelVoice() {pendingVoice=nil;holding=false;gestureStarted=false;store.voiceCapture=nil;speech.cancel()}
    var welcome:some View {
        VStack(alignment:.leading,spacing:22) {
            AIOrb().frame(width:44,height:44).padding(.top,12)
            Text(finance ? "一起理清你的财务":"今天想聊点什么？").font(.system(size:23,weight:.semibold))
            let suggestions=finance ? ["分析我本月的收支","我的信用卡还款压力大吗？","帮我制定月度预算","我有哪些财务风险？"]:["你是谁？","帮我润色一段文字","这个应用怎么记账？","帮我写一段代码"]
            ForEach(suggestions,id:\.self) {text in Button {input=text;send()} label:{HStack {Text(text).font(.system(size:14));Spacer();Image(systemName:"arrow.up.left").font(.caption)}.padding(14).background(Theme.panel(scheme),in:RoundedRectangle(cornerRadius:14))}.buttonStyle(.plain)}
            if store.cloudEnabled && store.hasAPIKey {Text(finance ? "云端已开启：问题、近期对话和相关财务资料会原文发送至 DeepSeek，可在个人详情关闭。":"云端已开启：问题和近期对话会发送至 DeepSeek，可在个人详情关闭。").font(.caption2).foregroundStyle(.secondary)}
        }.padding(.bottom,16)
    }
    func modelLabel(_ m:String)->String {switch m {case "deepseek-chat":return "DeepSeek Chat";case "deepseek-reasoner":return "DeepSeek Reasoner";case "deepseek-flash":return "DeepSeek Flash";case "deepseek-v4-pro":return "DeepSeek Pro";default:return m}}
    func send() {
        let question=input.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !question.isEmpty,!store.assistantBusy else{return}
        guard question.count<=20000 else {store.error="消息过长，请分段发送";return}
        input="";focused=false;follow=true
        let previous=store.messages,epoch=store.epoch,d=store.current,mode=finance,cloud=store.cloudEnabled && store.hasAPIKey,model=store.model
        store.messages.append(ChatMessage(role:"user",content:question))
        let answerID=UUID().uuidString;store.activeReplyID=answerID;store.messages.append(ChatMessage(id:answerID,role:"assistant",content:"",source:cloud ? "云端回答":"本机回答"));store.assistantBusy=true
        store.activeTask=Task {
            defer {if store.epoch==epoch && store.activeReplyID==answerID {store.assistantBusy=false;store.activeReplyID=nil}}
            do {
                let (text,source)=try await AIService.reply(question,finance:mode,document:d,history:previous,cloud:cloud,model:model) {partial in guard store.epoch==epoch,store.activeReplyID==answerID,let i=store.messages.firstIndex(where:{$0.id==answerID}) else{return};store.messages[i].content=partial}
                try Task.checkCancellation();guard store.epoch==epoch,store.activeReplyID==answerID,let i=store.messages.firstIndex(where:{$0.id==answerID}) else{return};store.messages[i].content=text;store.messages[i].source=source;await store.saveHistory()
            }catch is CancellationError {if store.epoch==epoch,let i=store.messages.firstIndex(where:{$0.id==answerID}),store.messages[i].content.isEmpty {store.messages.remove(at:i)}}
            catch {if !Task.isCancelled,store.epoch==epoch,store.activeReplyID==answerID {store.messages.removeAll {$0.id==answerID};store.present(error)}}
        }
    }
}
struct ChatBubble:View {
    var message:ChatMessage,working:Bool
    @Environment(\.colorScheme) var scheme
    var body:some View {
        HStack(alignment:.top,spacing:8) {
            if message.role=="user" {Spacer(minLength:36)}else{AIOrb(active:working).frame(width:23,height:23)}
            VStack(alignment:.leading,spacing:8) {
                if message.role != "user" {Text(message.source).font(.system(size:10)).foregroundStyle(.secondary)}
                VStack(alignment:.leading,spacing:10) {
                    if message.content.isEmpty && working {Text("正在思考…").font(.subheadline).foregroundStyle(.secondary).padding(.vertical,4)}
                    else {MarkdownBody(text:message.content)}
                }.padding(13).background(message.role=="user" ? Theme.accent.opacity(0.09):Theme.panel(scheme),in:RoundedRectangle(cornerRadius:17,style:.continuous)).clipShape(RoundedRectangle(cornerRadius:17,style:.continuous)).aiActivity(working,cornerRadius:17)
                if message.role != "user" && !working {Button {UIPasteboard.general.string=message.content;UIImpactFeedbackGenerator(style:.light).impactOccurred()} label:{Image(systemName:"doc.on.doc").font(.system(size:13)).frame(width:32,height:30)}.foregroundStyle(.secondary).accessibilityLabel("复制回答")}
            }.frame(maxWidth:.infinity,alignment:message.role=="user" ? .trailing:.leading)
            if message.role != "user" {Spacer(minLength:6)}
        }.contextMenu {Button("复制",systemImage:"doc.on.doc") {UIPasteboard.general.string=message.content}}
    }
}
struct MarkdownBody:View {
    var text:String
    var body:some View {
        let blocks=text.components(separatedBy:"```")
        VStack(alignment:.leading,spacing:10) {
            ForEach(Array(blocks.enumerated()),id:\.offset) {i,block in
                if i%2==1 {
                    let code=block.components(separatedBy:"\n").dropFirst().joined(separator:"\n")
                    VStack(alignment:.leading,spacing:8) {HStack {Text(block.components(separatedBy:"\n").first ?? "代码").font(.caption);Spacer();Button("复制") {UIPasteboard.general.string=code}.font(.caption)};ScrollView(.horizontal) {Text(code).font(.system(size:12,design:.monospaced)).textSelection(.enabled)}}.padding(10).background(.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:10))
                } else {
                    let lines=block.components(separatedBy:"\n")
                    ForEach(Array(lines.enumerated()),id:\.offset) {_,line in
                        if line.hasPrefix("|") {if line.range(of:#"^\|[\s:|\-]+\|$"#,options:.regularExpression)==nil {ScrollView(.horizontal,showsIndicators:false) {HStack(spacing:0) {ForEach(Array(line.split(separator:"|",omittingEmptySubsequences:true).enumerated()),id:\.offset) {_,cell in Text(String(cell).trimmingCharacters(in:.whitespaces)).font(.system(size:12)).monospacedDigit().frame(minWidth:105,alignment:.leading).padding(7)}}}.background(.primary.opacity(0.025))}}
                        else if line.hasPrefix("# ") {Text(String(line.dropFirst(2))).font(.system(size:19,weight:.semibold)).padding(.vertical,4)}
                        else if line.hasPrefix("## ") {Text(String(line.dropFirst(3))).font(.system(size:16,weight:.semibold)).padding(.top,5)}
                        else if !line.isEmpty {Text((try? AttributedString(markdown:line,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(line)).font(.system(size:14)).lineSpacing(5).textSelection(.enabled)}
                    }
                }
            }
        }
    }
}
struct ChatHistoryView:View {
    @Environment(\.colorScheme) var scheme
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    var select:(ChatSession)->Void
    @State var query=""
    @State var renaming:ChatSession?
    @State var title=""
    @State var rename=false
    var sessions:[ChatSession] {store.sessions.filter {query.isEmpty || ($0.title+$0.messages.map(\.content).joined()).localizedCaseInsensitiveContains(query)}}
    var body:some View {List {
        Button("新对话",systemImage:"plus") {Task {await store.newChat();dismiss()}}
        ForEach(sessions) {s in Button {select(s)} label:{VStack(alignment:.leading,spacing:6) {Text(s.title).font(.subheadline).foregroundStyle(.primary);Text(s.messages.last?.content ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)}}.buttonStyle(.plain).contextMenu {Button("重命名",systemImage:"pencil") {renaming=s;title=s.title;rename=true}}.swipeActions(allowsFullSwipe:false) {Button(role:.destructive) {store.sessions.removeAll {$0.id==s.id};if store.activeSessionID==s.id {store.messages=[];store.activeSessionID=UUID().uuidString};Task {await store.saveHistory()}} label:{Label("删除",systemImage:"trash")}}}
    }.scrollContentBackground(.hidden).background(Theme.background(scheme)).searchable(text:$query,prompt:"搜索标题和对话").navigationTitle("历史对话").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.confirmationAction) {Button("完成") {dismiss()}}}
        .alert("重命名对话",isPresented:$rename) {TextField("标题",text:$title);Button("取消",role:.cancel) {};Button("保存") {if let s=renaming,let i=store.sessions.firstIndex(where:{$0.id==s.id}),!title.isEmpty {store.sessions[i].title=String(title.prefix(100));Task {await store.saveHistory()}}}}
    }
}

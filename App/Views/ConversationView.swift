import UIKit
import SwiftUI
import PhotosUI

private struct BottomPreference:PreferenceKey {
    static let defaultValue:CGFloat=0
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat) {value=nextValue()}
}
struct ConversationView:View {
    var onBack:(()->Void)?
    @Binding var sheet:RootSheet?
    @EnvironmentObject var store:AppStore
    @Environment(\.colorScheme) var scheme
    @StateObject var speech=SpeechService()
    var input:String {get {store.chatDraft} nonmutating set {store.chatDraft=newValue}}
    var finance:Bool {store.financeMode}
    @AppStorage("chat.webSearchEnabled") private var webSearch=true
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
    @State var availableModels=["deepseek-flash","deepseek-v4-pro"]
    @State private var photoPicker=false
    @State private var loadingPhotos=false
    @State private var selectedPhotos:[PhotosPickerItem]=[]
    @State private var photoTask:Task<Void,Never>?
    @State private var preferences=false
    @State private var greeting=""
    @State private var openedItem:ChatCreatedItem?
    @AppStorage("chat.lastGreeting") private var lastGreeting=""
    @AppStorage("chat.lastFinanceGreeting") private var lastFinanceGreeting=""
    @State var focused=false
    @State private var composerVisible=false
    private var composerAvailable:Bool {composerVisible && sheet == nil && !history && !preferences && openedItem == nil && !photoPicker && !modelMenu}
    var body:some View {
        VStack(spacing:0) {
            header
            GeometryReader {geometry in
                ScrollViewReader {proxy in
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:22) {
                            if store.messages.isEmpty {welcome.frame(minHeight:max(0,geometry.size.height-32))}
                            ForEach(store.messages) {message in ChatBubble(message:message,working:store.assistantBusy && message.id==store.messages.last?.id,onOpen:{openedItem=$0},onSave:{saveAnswer(message)})}
                            Color.clear.frame(height:1).id("latest").background(GeometryReader {g in Color.clear.preference(key:BottomPreference.self,value:g.frame(in:.named("conversationScroll")).minY)})
                        }.padding(16)
                    }.coordinateSpace(name:"conversationScroll").scrollDismissesKeyboard(.interactively)
                        .onPreferenceChange(BottomPreference.self) {y in follow=y<geometry.size.height+80}
                        .onChange(of:store.messages.last?.content) {_,_ in if follow {proxy.scrollTo("latest",anchor:.bottom)}}
                        .onChange(of:store.messages.count) {_,_ in if follow {proxy.scrollTo("latest",anchor:.bottom)}}
                        .overlay(alignment:.bottom) {if !follow && !store.messages.isEmpty {Button {follow=true;withAnimation(Theme.normal) {proxy.scrollTo("latest",anchor:.bottom)}} label:{Label("回到最新",systemImage:"arrow.down").font(.caption).padding(10).background(.regularMaterial,in:Capsule())}.padding(.bottom,8)}}
                }
            }.clipped()
            VStack(spacing:8) {attachmentPreview;modePicker;composer}.layoutPriority(1)
        }
            .background {ConversationBackground()}.appClearChrome().toolbar(.hidden,for:.navigationBar).appErrorScope()
            .onAppear {
                composerVisible=true;refreshGreeting()
                #if DEBUG
                DebugFixtures.showThinking(in:store);DebugFixtures.showSearchResults(in:store)
                #endif
                store.speech=speech;speech.onFinal={text in let action=pendingVoice;pendingVoice=nil;holding=false;store.voiceCapture=nil;if action == .send {let draft=input;input=text;send();input=draft}else{input+=(input.isEmpty ? "":" ")+text;voiceMode=false;focused=true}};if !availableModels.contains(store.model) {availableModels.append(store.model)}
            }
            .onChange(of:speech.error) {_,error in if let error {cancelVoice();store.error=error;speech.error=nil}}
            .onDisappear {composerVisible=false;dismissComposer();photoTask?.cancel();cancelVoice();speech.onFinal=nil;if store.speech === speech {store.speech=nil}}
            .onChange(of:sheet != nil) {_,presented in if presented {dismissComposer()}}
            .onChange(of:history) {_,presented in if presented {dismissComposer()}}
            .onChange(of:preferences) {_,presented in if presented {dismissComposer()}}
            .onChange(of:openedItem != nil) {_,presented in if presented {dismissComposer()}}
            .onChange(of:store.model) {_,value in if !DeepSeekModels.supportsImages(value) {photoTask?.cancel();loadingPhotos=false;selectedPhotos=[];store.chatImages=[];photoPicker=false}}
            .photosPicker(isPresented:$photoPicker,selection:$selectedPhotos,maxSelectionCount:ChatImage.maximumCount,matching:.images)
            .onChange(of:selectedPhotos) {_,photos in loadPhotos(photos)}
            .onChange(of:scenePhase) {_,phase in if phase != .active {cancelVoice()}}
            .onChange(of:store.financeMode) {_,_ in refreshGreeting()}
            .sheet(isPresented:$preferences) {NavigationStack {ChatPreferencesView()}.environmentObject(store)}
            .sheet(item:$openedItem) {receipt in NavigationStack {createdDestination(receipt)}.appErrorScope().environmentObject(store)}
            .sheet(isPresented:$history) {NavigationStack {ChatHistoryView {session in Task {await store.newChat(finance:session.finance ?? finance);store.messages=session.messages;store.activeSessionID=session.id;history=false}}}.environmentObject(store)}
    }
    var header:some View {
        HStack(spacing:8) {
            Button {dismissComposer();onBack?()} label:{Image(systemName:"chevron.left").font(.system(size:19)).frame(width:44,height:44).appGlass(Circle(),interactive:true)}.buttonStyle(.plain).accessibilityLabel("返回")
                Button {dismissComposer();modelMenu=true} label:{HStack(spacing:5) {Text(modelLabel(store.model)).lineLimit(1).minimumScaleFactor(0.8);Image(systemName:"chevron.down").font(.system(size:9))}.font(.system(size:14,weight:.medium)).padding(.horizontal,12).frame(height:44).appGlass(Capsule(),interactive:true)}
                    .popover(isPresented:$modelMenu,attachmentAnchor:.rect(.bounds),arrowEdge:.top) {modelChoices.presentationCompactAdaptation(.popover)}
                    .accessibilityIdentifier("chat.model").disabled(store.assistantBusy)
            Spacer(minLength:0)
            HeaderControls(sheet:$sheet)
        }.padding(.horizontal,12).padding(.top,4).padding(.bottom,10)
    }
    private var modelChoices:some View {
        VStack(spacing:0) {ForEach(availableModels,id:\.self) {model in
            Button {modelMenu=false;Task {await store.setting("model",.string(model))}} label:{
                HStack(spacing:12) {Text(modelLabel(model)).font(.system(size:16)).lineLimit(1).foregroundStyle(.primary);Spacer(minLength:12);Image(systemName:"checkmark").foregroundStyle(Theme.accent).opacity(store.model==model ? 1:0).accessibilityHidden(true)}.padding(.horizontal,18).frame(height:46).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("chat.model.option."+model).accessibilityLabel(modelLabel(model)).accessibilityValue(store.model==model ? "已选择":"未选择").accessibilityAddTraits(store.model==model ? .isSelected:[])
        }}.frame(width:240).padding(.vertical,6)
    }
    var modePicker:some View {
        HStack(spacing:8) {mode("聊天",finance:false);mode("财务咨询",finance:true)}.padding(.top,6)
    }
    func mode(_ title:String,finance target:Bool)->some View {
        Button {dismissComposer();if finance != target {Task {await store.newChat(finance:target)}}} label:{
            Text(title).font(.system(size:13,weight:finance==target ? .medium:.regular)).foregroundStyle(.primary)
                .padding(.horizontal,18).frame(height:32)
                .background {if finance==target {Capsule().fill(Theme.panel(scheme)).overlay {Capsule().strokeBorder(.primary.opacity(0.08),lineWidth:0.5)}}}
        }.buttonStyle(.plain).accessibilityIdentifier(target ? "chat.mode.finance":"chat.mode.chat")
            .accessibilityAddTraits(finance==target ? .isSelected:[]).disabled(store.assistantBusy || holding || speech.finishing)
    }
    var composer:some View {
        HStack(alignment:.bottom,spacing:8) {
            Menu {
                if DeepSeekModels.supportsImages(store.model) {
                    Section {Button("上传图片",systemImage:"photo") {dismissComposer();photoPicker=true}.accessibilityIdentifier("chat.menu.photos")} footer:{Text("最多 4 张。图片随消息发送给 DeepSeek Flash，并保存在本机加密聊天记录中。")}
                }
                Section {
                    Toggle(isOn:$webSearch) {Label("联网搜索",systemImage:"globe")}.accessibilityIdentifier("chat.webSearch")
                } footer:{Text("按需查询最新信息，搜索与抓取分别为 5 元／千次成功请求。")}
                Section("对话") {
                    Button("回复风格",systemImage:"slider.horizontal.3") {dismissComposer();preferences=true}.accessibilityIdentifier("chat.menu.preferences")
                    Button("新对话",systemImage:"square.and.pencil") {dismissComposer();Task {await store.newChat()}}.accessibilityIdentifier("chat.menu.new")
                    Button("历史对话",systemImage:"clock.arrow.circlepath") {dismissComposer();history=true}.accessibilityIdentifier("chat.menu.history")
                }
            } label:{Image(systemName:"plus").font(.system(size:20)).frame(width:36,height:42)}.accessibilityLabel("聊天功能").disabled(store.assistantBusy || holding || speech.finishing)
            if voiceMode {
                Text(holding ? "松开发送文字":"按住 说话").font(.system(size:16,weight:.medium)).frame(maxWidth:.infinity,minHeight:42)
                    .background(Theme.accent.opacity(holding ? 0.16:0.04),in:Capsule()).contentShape(Capsule())
                    .gesture(voiceGesture).accessibilityLabel("按住说话").accessibilityAddTraits(.isButton)
                    .accessibilityHint("左滑取消，右滑转文字。也可使用开始录音、完成录音和取消录音操作")
                    .accessibilityAction(named:Text("开始录音")) {beginVoice()}
                    .accessibilityAction(named:Text("完成录音")) {endVoice(.text)}
                    .accessibilityAction(named:Text("取消录音")) {cancelVoice()}
            } else {
                ComposingTextInput(text:$store.chatDraft,isFocused:Binding(get:{focused && composerAvailable},set:{requested in if requested && !composerAvailable {dismissComposer()}else{focused=requested}}),placeholder:finance ? "问问你的财务状况…":"发消息…")
            }
            Button {
                dismissComposer();voiceMode.toggle()
                if voiceMode {Task {_=await speech.prepare()}}
            } label:{Image(systemName:voiceMode ? "keyboard":"mic").font(.system(size:20)).frame(width:36,height:42)}
                .accessibilityLabel(voiceMode ? "切换键盘输入":"切换语音输入").disabled(store.assistantBusy || holding || speech.finishing)
            if (!voiceMode && (!input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !store.chatImages.isEmpty)) || store.assistantBusy {
                Button {if store.assistantBusy {store.cancelReply()}else{send()}} label:{Image(systemName:store.assistantBusy ? "stop.fill":"arrow.up").font(.system(size:16,weight:.semibold)).frame(width:34,height:34).background(Theme.accent,in:Circle()).foregroundStyle(.white)}.accessibilityLabel(store.assistantBusy ? "停止回复":"发送").disabled(loadingPhotos).padding(.bottom,4)
            }
        }.padding(.horizontal,8).padding(.vertical,4).appGlass(RoundedRectangle(cornerRadius:24)).padding(.horizontal,12).padding(.bottom,8)
    }
    @ViewBuilder private var attachmentPreview:some View {
        if loadingPhotos {ProgressView("正在准备图片…").font(.caption)}
        if !store.chatImages.isEmpty {
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:10) {ForEach(store.chatImages) {image in
                    if let preview=UIImage(data:image.jpeg) {
                        Image(uiImage:preview).resizable().scaledToFill().frame(width:64,height:64).clipShape(RoundedRectangle(cornerRadius:12))
                            .overlay(alignment:.topTrailing) {Button {store.chatImages.removeAll {$0.id==image.id}} label:{Image(systemName:"xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white,.black.opacity(0.7)).padding(3)}.accessibilityLabel("移除图片")}
                    }
                }}.padding(.horizontal,16)
            }.accessibilityIdentifier("chat.attachments")
        }
    }
    private func loadPhotos(_ photos:[PhotosPickerItem]) {
        photoTask?.cancel();guard !photos.isEmpty else {return};loadingPhotos=true
        let epoch=store.epoch,session=store.activeSessionID
        photoTask=Task {
            defer {loadingPhotos=false}
            do {
                var images:[ChatImage]=[]
                for item in photos.prefix(ChatImage.maximumCount) {
                    try Task.checkCancellation()
                    guard let data=try await item.loadTransferable(type:Data.self) else {throw AppError.message("无法从相册读取图片")}
                    let image=try await Task.detached(priority:.userInitiated) {try ChatImageService.prepare(data)}.value
                    images.append(image)
                }
                try Task.checkCancellation()
                guard store.epoch==epoch,store.activeSessionID==session,DeepSeekModels.supportsImages(store.model) else {return}
                store.chatImages=images
            } catch is CancellationError {} catch {store.present(error)}
        }
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
        dismissComposer();holding=true;gestureStarted=true;voiceAction = .send;pendingVoice=nil
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
        VStack(spacing:18) {
            AIOrb(active:true).frame(width:88,height:88).accessibilityIdentifier("assistant.orb")
            Text(greeting).font(.system(size:28,weight:.regular)).multilineTextAlignment(.center).frame(maxWidth:290)
        }.frame(maxWidth:.infinity).accessibilityElement(children:.contain).accessibilityIdentifier("assistant.greeting")
    }
    private func refreshGreeting() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-layout-fixture") {greeting=finance ? "一起理清你的财务":"今天心情怎么样？";return}
        #endif
        greeting=ChatGreetings.next(after:finance ? lastFinanceGreeting:lastGreeting,finance:finance)
        if finance {lastFinanceGreeting=greeting} else {lastGreeting=greeting}
    }
    func modelLabel(_ m:String)->String {switch m {case "deepseek-chat":return "DeepSeek Chat";case "deepseek-reasoner":return "DeepSeek Reasoner";case "deepseek-flash":return "DeepSeek Flash";case "deepseek-v4-pro":return "DeepSeek Pro";default:return m}}
    private func dismissComposer() {
        focused=false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
    }
    func send() {
        dismissComposer()
        let images=store.chatImages
        var question=input.trimmingCharacters(in:.whitespacesAndNewlines)
        guard (!question.isEmpty || !images.isEmpty),!store.assistantBusy,!loadingPhotos else{return}
        if question.isEmpty {question="请描述并分析这些图片。"}
        if !images.isEmpty {
            guard DeepSeekModels.supportsImages(store.model),store.cloudEnabled,store.hasAPIKey else {store.error="图片理解需要选择 DeepSeek Flash，并开启云端智能、配置 API Key";return}
            let stored=store.messages.flatMap {$0.images ?? []}.reduce(0) {$0+$1.jpeg.count}
            guard stored+images.reduce(0,{$0+$1.jpeg.count})<=12*1024*1024 else {store.error="本对话图片较多，请新建对话后继续发送";return}
        }
        guard question.count<=20000 else {store.error="消息过长，请分段发送";return}
        input="";focused=false;follow=true
        let previous=store.messages,epoch=store.epoch,d=store.current,mode=finance,cloud=store.cloudEnabled && store.hasAPIKey,model=store.model,searchEnabled=webSearch
        let user=ChatMessage(role:"user",content:question,images:images.isEmpty ? nil:images)
        store.messages.append(user);store.chatImages=[];selectedPhotos=[]
        let answerID=UUID().uuidString;store.activeReplyID=answerID;store.messages.append(ChatMessage(id:answerID,role:"assistant",content:"",source:cloud ? "云端回答":"本机回答"));store.assistantBusy=true
        let actions=ChatActionService(store:store,question:question,history:previous,images:images)
        let session=store.activeSessionID
        store.activeTask=Task {
            defer {if store.epoch==epoch && store.activeReplyID==answerID {store.assistantBusy=false;store.activeReplyID=nil}}
            do {
                let response:(String,String)
                if let local=try await savePreviousNote(question,previous:previous,actions:actions) {response=local}
                else {response=try await AIService.reply(question,finance:mode,document:d,history:previous,cloud:cloud,model:model,webSearch:searchEnabled,images:images,localTools:actions.schemas,actionInstruction:actions.instruction,onTool:{name,arguments in
                    let result=try await actions.perform(name,arguments:arguments)
                    if store.epoch==epoch,store.activeSessionID==session,!actions.created.isEmpty {finishAnswer(answerID,text:actions.confirmedText(""),source:"应用已确认保存",created:actions.created,after:user.id)}
                    return result
                },onPartial:{partial in
                    guard store.epoch==epoch,store.activeReplyID==answerID,let i=store.messages.firstIndex(where:{$0.id==answerID}) else{return};store.messages[i].content=partial
                },onSources:{sources in
                    guard store.epoch==epoch,store.activeReplyID==answerID,let i=store.messages.firstIndex(where:{$0.id==answerID}) else{return};store.messages[i].sources=sources
                },onStatus:{status in
                    guard store.epoch==epoch,store.activeReplyID==answerID,let i=store.messages.firstIndex(where:{$0.id==answerID}) else{return};store.messages[i].source=status
                })}
                let (text,source)=response
                if actions.created.isEmpty {try Task.checkCancellation()}
                guard store.epoch==epoch,store.activeSessionID==session else{return}
                finishAnswer(answerID,text:actions.confirmedText(text),source:actions.created.isEmpty ? source:"应用已确认保存",created:actions.created)
                await store.saveHistory()
            } catch {
                if store.epoch==epoch,store.activeSessionID==session,!actions.created.isEmpty {
                    finishAnswer(answerID,text:actions.confirmedText("")+"\n本轮后续回复未完成，已保存的资料不会丢失。",source:"应用已确认保存",created:actions.created);await store.saveHistory()
                } else if error is CancellationError {if store.epoch==epoch,let i=store.messages.firstIndex(where:{$0.id==answerID}),store.messages[i].content.isEmpty {store.messages.remove(at:i)}}
                else if !Task.isCancelled,store.epoch==epoch,store.activeReplyID==answerID {store.messages.removeAll {$0.id==answerID};if !images.isEmpty {store.messages.removeAll {$0.id==user.id};store.chatImages=images;input=question};store.present(error)}
            }
        }
    }
    private func savePreviousNote(_ question:String,previous:[ChatMessage],actions:ChatActionService) async throws -> (String,String)? {
        guard ChatActions.savesPreviousNote(question),actions.allowed==[.note],let message=previous.last(where:{$0.role=="assistant" && !$0.content.isEmpty}),(message.createdItems ?? []).isEmpty else{return nil}
        let draft=ChatActions.noteDraft(message.content)
        let response=try await actions.perform("create_note",arguments:String(decoding:JSONEncoder().encode(draft),as:UTF8.self))
        return (response.bool("saved") ? "备忘录已保存。":response.text("message"),"本机保存")
    }
    private func finishAnswer(_ id:String,text:String,source:String,created:[ChatCreatedItem],after userID:String?=nil) {
        if let index=store.messages.firstIndex(where:{$0.id==id}) {store.messages[index].content=text;store.messages[index].source=source;store.messages[index].createdItems=created.isEmpty ? nil:created}
        else if !created.isEmpty {let index=userID.flatMap {id in store.messages.firstIndex {$0.id==id}}.map {$0+1} ?? store.messages.endIndex;store.messages.insert(ChatMessage(id:id,role:"assistant",content:text,source:source,createdItems:created),at:index)}
    }
    private func saveAnswer(_ message:ChatMessage) {
        guard !store.assistantBusy,!store.busy else{return}
        var draft=ChatActions.noteDraft(message.content);draft.set("folder",store.noteFolder)
        let id=UUID().uuidString.lowercased()
        Task {do {
            let (_,receipt)=try ChatActions.create(draft,kind:.note,id:id,in:store.current,source:"")
            if await store.commit({$0=try ChatActions.create(draft,kind:.note,id:id,in:$0,source:"").0}) {
                if let index=store.messages.firstIndex(where:{$0.id==message.id}) {store.messages[index].createdItems=(store.messages[index].createdItems ?? [])+[receipt]}
                await store.saveHistory();openedItem=receipt
            }
        }catch{store.present(error)}}
    }
    @ViewBuilder private func createdDestination(_ receipt:ChatCreatedItem)->some View {
        if receipt.kind == .note,let note=store.current.notes.first(where:{$0.id==receipt.id && $0.int("deletedAt")==0}) {NoteEditor(note:note)}
        else if let record=store.current.records.first(where:{$0.id==receipt.id}) {
            if receipt.kind == .reminder {ReminderEditor(reminder:record)}else{RecordEditor(record:record)}
        } else {ContentUnavailableView("记录已移除",systemImage:"tray").toolbar {ToolbarItem(placement:.confirmationAction) {Button("完成") {openedItem=nil}}}}
    }
}
struct ChatBubble:View {
    var message:ChatMessage,working:Bool
    var onOpen:((ChatCreatedItem)->Void)?=nil
    var onSave:(()->Void)?=nil
    @Environment(\.colorScheme) var scheme
    var body:some View {
        HStack(alignment:.top,spacing:8) {
            if message.role=="user" {Spacer(minLength:36)}else{AIOrb(active:working).frame(width:23,height:23)}
            VStack(alignment:.leading,spacing:8) {
                if message.role != "user" {Text(message.source).font(.system(size:10)).foregroundStyle(.secondary)}
                VStack(alignment:.leading,spacing:10) {
                    if let images=message.images,!images.isEmpty {
                        ForEach(images) {image in if let preview=UIImage(data:image.jpeg) {Image(uiImage:preview).resizable().scaledToFit().frame(maxWidth:220,maxHeight:220).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityLabel("已发送的图片")}}
                    }
                    if message.content.isEmpty && working {Text("正在思考…").font(.subheadline).aiText(revealing:true).padding(.vertical,4)}
                    else {MarkdownBody(text:WebEvidence.cited(message.content,sources:message.sources ?? [])).aiText(revealing:working && message.role != "user")}
                }.padding(message.role=="user" ? 13:0)
                    .background(message.role=="user" ? Theme.accent.opacity(0.09):.clear,in:RoundedRectangle(cornerRadius:17,style:.continuous))
                if message.role != "user",let sources=message.sources,!sources.isEmpty {WebSourcesView(sources:sources)}
                if let created=message.createdItems {ForEach(created) {receipt in
                    Button {onOpen?(receipt)} label:{HStack(spacing:10) {Image(systemName:receipt.kind == .note ? "note.text":receipt.kind == .reminder ? "bell":"creditcard");VStack(alignment:.leading,spacing:4) {Text(receipt.title).font(.subheadline.weight(.medium));Text(receipt.label+" · "+receipt.detail).font(.caption).foregroundStyle(.secondary)};Spacer(minLength:0);Image(systemName:"chevron.right").font(.caption)}.padding(12).background(.background.opacity(0.75),in:RoundedRectangle(cornerRadius:14))}.buttonStyle(.plain).accessibilityIdentifier("chat.created."+receipt.kind.rawValue)
                }}
                if message.role != "user",!working,!message.content.isEmpty,(message.createdItems ?? []).isEmpty,let onSave {Button("保存为备忘录",systemImage:"note.text.badge.plus",action:onSave).font(.caption).accessibilityIdentifier("chat.saveNote")}
                if message.role != "user" && !working {Button {UIPasteboard.general.string=message.content;UIImpactFeedbackGenerator(style:.light).impactOccurred()} label:{Image(systemName:"doc.on.doc").font(.system(size:13)).frame(width:32,height:30)}.foregroundStyle(.secondary).accessibilityLabel("复制回答")}
            }.frame(maxWidth:.infinity,alignment:message.role=="user" ? .trailing:.leading)
            if message.role != "user" {Spacer(minLength:6)}
        }.contextMenu {Button("复制",systemImage:"doc.on.doc") {UIPasteboard.general.string=message.content}}
    }
}
struct ConversationBackground:View {
    @Environment(\.colorScheme) private var scheme
    var body:some View {
        GeometryReader {proxy in Theme.background(scheme).overlay(alignment:.bottom) {
            Rectangle().fill(LinearGradient(colors:[.clear,Color(red:0.55,green:0.78,blue:1).opacity(scheme == .dark ? 0.10:0.32)],startPoint:.top,endPoint:.bottom)).frame(height:proxy.size.height*0.58)
        }}.ignoresSafeArea().allowsHitTesting(false)
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

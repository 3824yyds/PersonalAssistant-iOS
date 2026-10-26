import SwiftUI
import UIKit

private enum CompanionPanel: String, Identifiable { case profile, memory; var id:String {rawValue} }

struct CompanionAvatar: View {
    var size:CGFloat = 36
    var body:some View {
        Image("CompanionAvatar").resizable().scaledToFill().frame(width:size,height:size).clipShape(Circle())
            .overlay {Circle().strokeBorder(.white.opacity(0.85),lineWidth:1)}.accessibilityLabel("伙伴头像")
    }
}

struct CompanionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store:AppStore
    @StateObject private var session:CompanionSession
    @State private var panel:CompanionPanel?
    @State private var focused=false
    @State private var clearHistory=false
    @State private var follow=true
    init(store:AppStore) {_store=ObservedObject(wrappedValue:store);_session=StateObject(wrappedValue:CompanionSession(store:store))}
    var body:some View {
        VStack(spacing:0) {
            header
            conversation
            if !session.cloudAvailable {
                Label("伙伴聊天需要开启云端智能并配置 DeepSeek",systemImage:"network").font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.bottom,6)
            }
            if let error=session.error {
                VStack(alignment:.leading,spacing:6) {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        if session.data.messages.last?.role=="user" {Button("重试这句话") {session.error=nil;session.retryLast()}}
                        Spacer();Button("收起") {session.error=nil}
                    }.font(.footnote)
                }.padding(12).background(Theme.panel(scheme),in:RoundedRectangle(cornerRadius:14)).padding(.horizontal,14).padding(.bottom,8)
                    .accessibilityIdentifier("companion.error")
            }
            if !session.busy,session.error==nil,session.data.messages.last?.role=="user" {
                HStack {Text("这句话还没有回复").foregroundStyle(.secondary);Spacer();Button("重试这句话") {session.retryLast()}}
                    .font(.footnote).padding(.horizontal,18).padding(.bottom,8)
            }
            composer
        }.background {ConversationBackground()}.appClearChrome().toolbar(.hidden,for:.navigationBar).appErrorScope()
            .task {
                session.active=phase == .active
                await session.open()
                while !Task.isCancelled {
                    do {try await Task.sleep(nanoseconds:3_000_000_000)} catch {return}
                    session.tick()
                }
            }
            .onDisappear {dismissKeyboard();session.close()}
            .onChange(of:phase) {_,value in session.active=value == .active;if value != .active {session.cancel()}else{session.touch()}}
            .onChange(of:focused) {_,value in session.editing=value;session.touch()}
            .onChange(of:session.draft) {_,_ in session.touch()}
            .onChange(of:panel) {_,value in session.panelOpen=value != nil || clearHistory;session.touch()}
            .onChange(of:clearHistory) {_,value in session.panelOpen=value || panel != nil;session.touch()}
            .sheet(item:$panel) {value in
                NavigationStack {
                    if value == .profile {CompanionProfileView(session:session)}else{CompanionMemoryView(session:session)}
                }.environmentObject(store)
            }
            .confirmationDialog("清理此页聊天？人物资料和记忆会保留。",isPresented:$clearHistory,titleVisibility:.visible) {
                Button("清理聊天",role:.destructive) {Task {_=await session.update {$0.messages=[];$0.awaitingProactiveReply=false;$0.lastProactive=Date()}}}
            }
    }
    private var header:some View {
        HStack(spacing:8) {
            Button {dismissKeyboard();session.close();dismiss()} label:{Image(systemName:"chevron.left").font(.system(size:19)).frame(width:44,height:44).appGlass(Circle(),interactive:true)}
                .buttonStyle(.plain).accessibilityLabel("返回普通聊天").accessibilityIdentifier("companion.back")
            Spacer(minLength:4)
            Button {open(.profile)} label:{HStack(spacing:8) {CompanionAvatar(size:32);VStack(alignment:.leading,spacing:2) {Text(session.title).font(.headline).lineLimit(1).accessibilityIdentifier("companion.title");Text("Flash · 文字伙伴").font(.caption2).foregroundStyle(.secondary)}}}
                .buttonStyle(.plain).accessibilityIdentifier("companion.profile").disabled(session.busy || store.busy)
            Spacer(minLength:4)
            HStack(spacing:0) {
                Button {open(.memory)} label:{Image(systemName:"bookmark").frame(width:40,height:44)}.accessibilityLabel("你们的记忆").accessibilityIdentifier("companion.memory")
                Menu {
                    Button("她的资料",systemImage:"person.crop.circle") {open(.profile)}
                    Button("你们的记忆",systemImage:"bookmark") {open(.memory)}
                    Button("清理聊天",systemImage:"trash",role:.destructive) {dismissKeyboard();clearHistory=true}
                } label:{Image(systemName:"ellipsis").frame(width:40,height:44)}.accessibilityLabel("伙伴更多功能")
            }.appGlass(Capsule(),interactive:true).disabled(session.busy || store.busy)
        }.padding(.horizontal,12).padding(.top,4).padding(.bottom,10)
    }
    private func dismissKeyboard() {focused=false;UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)}
    private func open(_ value:CompanionPanel) {dismissKeyboard();session.touch();panel=value}
    private var conversation:some View {
        ScrollViewReader {proxy in
            ScrollView {
                LazyVStack(alignment:.leading,spacing:20) {
                    ForEach(session.data.messages) {message in
                        VStack(spacing:16) {
                            if showDate(message) {Text(message.date.formatted(date:.abbreviated,time:.shortened)).font(.caption2).foregroundStyle(.secondary).frame(maxWidth:.infinity)}
                            bubble(message)
                        }
                    }
                    if session.busy {
                        HStack(alignment:.top,spacing:10) {
                            CompanionAvatar()
                            VStack(alignment:.leading,spacing:10) {
                                if !session.partial.isEmpty {Text(session.partial).textSelection(.enabled)}
                                HStack(spacing:8) {ProgressView().controlSize(.small);Text(session.status).font(.caption).foregroundStyle(.secondary)}
                            }.padding(14).background(Theme.panel(scheme).opacity(0.85),in:RoundedRectangle(cornerRadius:20))
                            Spacer(minLength:24)
                        }.accessibilityIdentifier("companion.working")
                    }
                    Color.clear.frame(height:1).id("companion.latest")
                }.padding(.horizontal,16).padding(.vertical,12)
            }.scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(DragGesture(minimumDistance:10).onChanged {_ in follow=false;session.touch()})
                .task(id:session.data.messages.count) {
                    guard follow else{return};do {try await Task.sleep(nanoseconds:40_000_000)}catch{return}
                    guard follow,session.visible else{return};proxy.scrollTo("companion.latest",anchor:.bottom)
                }
                .task(id:session.partial) {
                    guard follow,!session.partial.isEmpty else{return};do {try await Task.sleep(nanoseconds:40_000_000)}catch{return}
                    guard follow,session.visible else{return};proxy.scrollTo("companion.latest",anchor:.bottom)
                }
                .task(id:focused) {
                    guard focused else{return};follow=true;do {try await Task.sleep(nanoseconds:250_000_000)}catch{return}
                    guard session.visible else{return};proxy.scrollTo("companion.latest",anchor:.bottom)
                }
                .overlay(alignment:.bottom) {
                    if !follow {Button {follow=true;proxy.scrollTo("companion.latest",anchor:.bottom)} label:{Label("回到最新",systemImage:"arrow.down").font(.caption).padding(10).appGlass(Capsule(),interactive:true)}.padding(8)}
                }
        }.clipped()
    }
    private func showDate(_ message:CompanionMessage)->Bool {
        guard let index=session.data.messages.firstIndex(where:{$0.id==message.id}),index>0 else{return true}
        return !Calendar.current.isDate(message.date,inSameDayAs:session.data.messages[index-1].date)
    }
    private func bubble(_ message:CompanionMessage)->some View {
        HStack(alignment:.top,spacing:10) {
            if message.role=="user" {Spacer(minLength:38)}else{CompanionAvatar()}
            VStack(alignment:.leading,spacing:8) {
                Text(.init(WebEvidence.cited(message.content,sources:message.sources))).textSelection(.enabled)
                    .padding(.horizontal,15).padding(.vertical,12)
                    .background(message.role=="user" ? Theme.accent.opacity(0.12):Theme.panel(scheme).opacity(0.85),in:RoundedRectangle(cornerRadius:20))
                    .accessibilityIdentifier("companion.message.\(message.id)")
                if let name=message.renamedTo,CompanionRules.canUndoName(message,data:session.data) {
                    HStack(spacing:8) {Text("名字已更新为「\(name)」");Button("撤销") {Task {await session.undoName(message)}}.disabled(session.busy || store.busy)}
                        .font(.caption).foregroundStyle(Theme.accent).padding(.horizontal,5)
                }
                if let name=message.nameProposal,session.data.messages.last?.id==message.id {
                    Button("就叫“\(name)”") {Task {await session.confirmName(message)}}.font(.subheadline).buttonStyle(.bordered).disabled(session.busy || store.busy).accessibilityIdentifier("companion.name.confirm")
                }
                if let id=message.memoryID,let memory=session.data.memories.first(where:{$0.id==id}) {
                    HStack(alignment:.top,spacing:6) {Image(systemName:"bookmark");Text("已记住："+memory.text);Button("撤销") {Task {await session.undoMemory(message)}}.disabled(session.busy || store.busy)}
                        .font(.caption).foregroundStyle(Theme.accent).padding(.horizontal,5)
                }
                if !message.sources.isEmpty {WebSourcesView(sources:message.sources).font(.caption)}
                if message.source.hasPrefix("联网") {Text(message.date.formatted(date:.abbreviated,time:.shortened)+" · "+message.source).font(.caption2).foregroundStyle(.secondary).padding(.horizontal,5)}
            }
            if message.role != "user" {Spacer(minLength:24)}
        }.frame(maxWidth:.infinity,alignment:message.role=="user" ? .trailing:.leading)
    }
    private var composer:some View {
        HStack(alignment:.bottom,spacing:10) {
            ComposingTextInput(text:$session.draft,isFocused:$focused,placeholder:session.data.profile.name.map {"和\($0)说点什么…"} ?? "说点什么…",accessibilityID:"companion.input")
            Button {
                if session.busy {session.cancel()}else{dismissKeyboard();follow=true;session.send()}
            } label:{Image(systemName:session.busy ? "stop.fill":"arrow.up").font(.system(size:18,weight:.semibold)).frame(width:38,height:38).background(Theme.accent,in:Circle()).foregroundStyle(.white)}
                .accessibilityLabel(session.busy ? "停止伙伴回复":"发送给伙伴").accessibilityIdentifier("companion.send")
                .disabled(!session.busy && (store.busy || session.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)).padding(.bottom,2)
        }.padding(.horizontal,12).padding(.vertical,7).appGlass(RoundedRectangle(cornerRadius:26))
            .padding(.horizontal,14).padding(.bottom,8)
    }
}

struct CompanionProfileView:View {
    @ObservedObject var session:CompanionSession
    @Environment(\.dismiss) private var dismiss
    @State private var edit=false
    @State private var memory=false
    var body:some View {
        Form {
            Section {
                VStack(spacing:12) {CompanionAvatar(size:100);Text(session.title).font(.title2.bold());Text("女性").font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity).padding(.vertical,12).listRowBackground(Color.clear)
            }
            Section("性格") {Text(session.data.profile.personality)}
            Section {
                Picker("聊天语气",selection:Binding(get:{session.data.profile.effectiveTone()},set:{tone in Task {_=await session.update {$0.profile.tone=tone;$0.profile.gentleUntil=nil}}})) {
                    ForEach(CompanionTone.allCases) {tone in Text(tone.title).tag(tone)}
                }.accessibilityIdentifier("companion.tone")
            } footer:{Text("也可以直接说“嘴再毒一点”或“今天别损我”。今天收敛后，明天恢复平常语气。认真求助时会优先照顾你的感受。")}
            Section("形象") {Text(session.data.profile.appearance)}
            Section {
                Toggle("主动接话",isOn:Binding(get:{session.data.profile.proactive},set:{value in Task {_=await session.update {$0.profile.proactive=value}}})).accessibilityIdentifier("companion.proactive")
                Toggle("需要时联网查询",isOn:Binding(get:{session.data.profile.web},set:{value in Task {_=await session.update {$0.profile.web=value}}})).accessibilityIdentifier("companion.web")
            } footer:{Text("聊天使用 DeepSeek Flash，需要联网并产生 API 费用。会发送当前消息、近期对话、少量相关旧对话和记忆，不发送整份笔记或账本。按需搜索另有费用，搜索词仅使用必要公开关键词。主动接话只在此页打开时发生。")}
            Section {Button {memory=true} label:{Label("查看你们的记忆",systemImage:"bookmark")}}
            if let error=session.error {Section {Text(error).font(.footnote).foregroundStyle(.red)}}
        }.scrollContentBackground(.hidden).background {ConversationBackground()}.navigationTitle("她的资料").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.topBarLeading) {Button("完成") {dismiss()}};ToolbarItem(placement:.topBarTrailing) {Button("编辑") {edit=true}.accessibilityIdentifier("companion.profile.edit")}}
            .sheet(isPresented:$edit) {NavigationStack {CompanionProfileEditor(session:session)}}
            .navigationDestination(isPresented:$memory) {CompanionMemoryView(session:session)}
    }
}

private struct CompanionProfileEditor:View {
    @ObservedObject var session:CompanionSession
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var appearance=""
    @State private var personality=""
    @State private var saving=false
    @State private var error:String?
    var body:some View {
        Form {
            Section("名字") {TextField("尚未取名",text:$name).accessibilityIdentifier("companion.name.editor")}
            Section("外貌与服装") {TextEditor(text:$appearance).frame(minHeight:130)}
            Section("性格") {TextEditor(text:$personality).frame(minHeight:85)}
            Section {Text("这些资料会用于她的自我描述。更换穿搭时可以在此修改。").font(.footnote).foregroundStyle(.secondary)}
            if let error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("编辑她的资料").navigationBarTitleDisplayMode(.inline)
            .onAppear {name=session.data.profile.name ?? "";appearance=session.data.profile.appearance;personality=session.data.profile.personality}
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}.disabled(saving)}
                ToolbarItem(placement:.confirmationAction) {Button("保存") {save()}.disabled(saving)}
            }.interactiveDismissDisabled(saving)
    }
    private func save() {
        let clean=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard clean.isEmpty || CompanionRules.cleanName(clean) != nil else {error="名字请使用1到20个字符";return}
        saving=true
        Task {
            let saved=await session.update {state in
                let nextName=clean.isEmpty ? nil:clean
                if state.profile.name != nextName {for i in state.messages.indices {state.messages[i].renamedFrom=nil;state.messages[i].renamedTo=nil}}
                state.profile.name=nextName;state.profile.appearance=appearance.trimmingCharacters(in:.whitespacesAndNewlines);state.profile.personality=personality.trimmingCharacters(in:.whitespacesAndNewlines)
            }
            saving=false;if saved {dismiss()}else{error=session.error}
        }
    }
}

struct CompanionMemoryView:View {
    @ObservedObject var session:CompanionSession
    @Environment(\.dismiss) private var dismiss
    @State private var category="preference"
    @State private var editing:CompanionMemory?
    var body:some View {
        List {
            Section {Picker("记忆分类",selection:$category) {Text("关于你").tag("preference");Text("聊过的事").tag("topic")}.pickerStyle(.segmented).listRowBackground(Color.clear)}
            if filtered.isEmpty {Section {Text("还没有这类记忆。你可以说“记住：…”或手动添加。").foregroundStyle(.secondary)}}
            ForEach(filtered) {memory in
                Button {editing=memory} label:{
                    VStack(alignment:.leading,spacing:6) {Text(memory.text).foregroundStyle(.primary);Text(memory.date.formatted(date:.abbreviated,time:.omitted)+" · "+(memory.quote.isEmpty ? "手动添加":"来自聊天")).font(.caption).foregroundStyle(.secondary)}.padding(.vertical,5)
                }.swipeActions {Button("删除",role:.destructive) {Task {await session.removeMemory(memory.id)}}}
            }
            Section {Button {editing=CompanionMemory(text:"",kind:category)} label:{Label("添加记忆",systemImage:"plus")}.accessibilityIdentifier("companion.memory.add")}
            if let error=session.error {Section {Text(error).font(.footnote).foregroundStyle(.red)}}
        }.scrollContentBackground(.hidden).background {ConversationBackground()}.navigationTitle("记忆").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.topBarTrailing) {Button("完成") {dismiss()}}}
            .sheet(item:$editing) {memory in NavigationStack {CompanionMemoryEditor(session:session,memory:memory)}}
    }
    private var filtered:[CompanionMemory] {Array(session.data.memories.filter {$0.kind==category}.reversed())}
}

private struct CompanionMemoryEditor:View {
    @ObservedObject var session:CompanionSession
    @Environment(\.dismiss) private var dismiss
    @State var memory:CompanionMemory
    @State private var saving=false
    @State private var error:String?
    var body:some View {
        Form {
            Section("记忆内容") {TextEditor(text:$memory.text).frame(minHeight:140).accessibilityIdentifier("companion.memory.text")}
            Section {Picker("分类",selection:$memory.kind) {Text("关于你").tag("preference");Text("聊过的事").tag("topic")}}
            if !memory.quote.isEmpty {Section("聊天依据") {Text(memory.quote).font(.footnote).foregroundStyle(.secondary)}}
            if let error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("编辑记忆").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}.disabled(saving)};ToolbarItem(placement:.confirmationAction) {Button("保存") {save()}.disabled(saving)}}
            .interactiveDismissDisabled(saving)
    }
    private func save() {
        let text=memory.text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty,text.count<=300 else {error="记忆请输入1到300字";return}
        memory.text=text;saving=true
        Task {let saved=await session.update {state in if let index=state.memories.firstIndex(where:{$0.id==memory.id}) {state.memories[index]=memory}else{state.memories.append(memory)}};saving=false;if saved {dismiss()}else{error=session.error}}
    }
}

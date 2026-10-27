import SwiftUI

struct CompanionHubView:View {
    @ObservedObject var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var rooms:[CompanionGroup]=[]
    @State private var creating=false
    @State private var createdSpace:CompanionSpace?
    @State private var pendingCreated:String?
    @State private var error:String?
    @State private var deleting:CompanionGroup?
    @State private var confirmDelete=false
    @State private var profiles:[CompanionPersona:CompanionProfile]=[:]
    private func profile(_ p:CompanionPersona)->CompanionProfile {profiles[p] ?? p.initial.profile}
    var body:some View {
        List {
            Section("单独聊天") {
                ForEach(CompanionPersona.allCases) {persona in
                    NavigationLink(value:CompanionSpace.direct(persona)) {
                        HStack(spacing:14) {CompanionAvatar(size:54,persona:persona);VStack(alignment:.leading,spacing:5) {Text(profile(persona).name ?? persona.label).font(.headline);Text(persona == .male ? "温柔稳重，耐心倾听与安慰":"热情亲近，愿意主动接话").font(.caption).foregroundStyle(.secondary)}}.padding(.vertical,7)
                    }.accessibilityIdentifier("companion.hub."+persona.rawValue)
                }
            }
            Section {
                ForEach(rooms) {room in
                    NavigationLink(value:CompanionSpace.group(room.id)) {HStack(spacing:12) {Image(systemName:"person.2.fill").font(.title2).foregroundStyle(Theme.accent);VStack(alignment:.leading,spacing:4) {Text(room.data.profile.title);Text(room.members.map {profile($0).name ?? $0.label}.joined(separator:"、")).font(.caption).foregroundStyle(.secondary)}}}
                        .accessibilityIdentifier("companion.hub.group."+room.id)
                        .swipeActions {Button("删除",role:.destructive) {deleting=room;confirmDelete=true}}
                }
                Button {creating=true} label:{Label("创建群聊",systemImage:"plus.bubble")}.accessibilityIdentifier("companion.group.create")
            } header:{Text("群聊")} footer:{Text("私聊与群聊分别保存对话、记忆和相处习惯。私聊内容不会自动带入群里。")}
            if let error {Section {Text(error).foregroundStyle(.red)}}
        }.scrollContentBackground(.hidden).background {ConversationBackground()}.navigationTitle("伙伴")
            .toolbar {ToolbarItem(placement:.topBarLeading) {Button("返回") {dismiss()}.accessibilityIdentifier("companion.hub.back")}}
            .onAppear {reload()}
            .navigationDestination(for:CompanionSpace.self) {space in CompanionView(store:store,space:space)}
            .sheet(isPresented:$creating,onDismiss:{if let id=pendingCreated {pendingCreated=nil;reload();createdSpace = .group(id)}}) {NavigationStack {CompanionGroupCreateView(store:store) {id in pendingCreated=id;creating=false}}}
            .navigationDestination(item:$createdSpace) {space in CompanionView(store:store,space:space)}
            .confirmationDialog("删除这个群聊？群内消息、记忆和习惯会删除，两位伙伴的私聊保留。",isPresented:$confirmDelete,titleVisibility:.visible) {
                Button("删除群聊",role:.destructive) {Task {guard let room=deleting else {return};if await store.commit({try CompanionDirectory.remove(room.id,in:&$0)}) {reload()}else{error=store.error}}}
            }
    }
    private func reload() {do {rooms=try CompanionDirectory.groups(store.current);profiles=Dictionary(uniqueKeysWithValues:CompanionPersona.allCases.map {($0,(try? CompanionDirectory.read(.direct($0),in:store.current).profile) ?? $0.initial.profile)})} catch {self.error=error.localizedDescription}}
}

private struct CompanionGroupCreateView:View {
    @ObservedObject var store:AppStore
    var created:(String)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var name="伙伴群聊"
    @State private var selected=Set(CompanionPersona.allCases)
    @State private var saving=false
    @State private var error:String?
    var body:some View {
        Form {
            Section("群名称") {TextField("1到20字",text:$name).accessibilityIdentifier("companion.group.name")}
            Section("邀请伙伴") {ForEach(CompanionPersona.allCases) {p in Toggle(isOn:Binding(get:{selected.contains(p)},set:{if $0 {selected.insert(p)}else{selected.remove(p)}})) {HStack {CompanionAvatar(size:38,persona:p);Text((try? CompanionDirectory.read(.direct(p),in:store.current).profile.name) ?? p.label)}}}}
            Section {Text("直接像平常一样聊天，伙伴会结合称呼、引用和上下文接话。每轮最多两位各接一句，不会无限互聊。回复与需要时的发言判断会产生模型用量；群内只使用共享聊天与群内记忆。") .font(.footnote).foregroundStyle(.secondary)}
            if let error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("创建群聊").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}.disabled(saving)};ToolbarItem(placement:.confirmationAction) {Button("创建") {save()}.disabled(saving || selected.isEmpty || CompanionRules.cleanName(name)==nil).accessibilityIdentifier("companion.group.confirm")}}
            .interactiveDismissDisabled(saving)
    }
    private func save() {
        saving=true
        Task {var id:String?
            let saved=await store.commit {document in id=try CompanionDirectory.create(name:name,members:CompanionPersona.allCases.filter {selected.contains($0)},in:&document).id}
            saving=false;if saved,let id {created(id);dismiss()}else{error=store.error ?? "群聊未能保存"}
        }
    }
}

struct CompanionGroupInfoView:View {
    @ObservedObject var session:CompanionSession
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var saving=false
    var body:some View {
        Form {
            Section("群名称") {TextField("群名称",text:$name)}
            Section("群成员") {ForEach(session.members) {p in HStack {CompanionAvatar(size:42,persona:p);VStack(alignment:.leading) {Text(session.profile(p).title);Text(p.gender).font(.caption).foregroundStyle(.secondary)}}}}
            Section {NavigationLink("群里的相处习惯") {CompanionGrowthView(session:session)}}
            Section {Text("直接叫名字或回复某条消息，就能和对应伙伴聊；对大家说话时，两位可以自然接话。每轮每位最多一句，不会无限互聊。共享记忆与私聊分开，形象与基础性格沿用各自资料。改名请到对应私聊。") .font(.footnote).foregroundStyle(.secondary)}
            if let error=session.error {Text(error).foregroundStyle(.red)}
        }.navigationTitle("群聊信息").navigationBarTitleDisplayMode(.inline).onAppear {name=session.title}
            .toolbar {ToolbarItem(placement:.cancellationAction) {Button("完成") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("保存") {saving=true;Task {if let clean=CompanionRules.cleanName(name),await session.update({$0.profile.name=clean}) {dismiss()};saving=false}}.disabled(saving || CompanionRules.cleanName(name)==nil)}}
    }
}

struct CompanionGrowthView:View {
    @ObservedObject var session:CompanionSession
    @State private var editing:CompanionExperience?
    var body:some View {
        List {
            Section {Toggle("积累相处习惯",isOn:Binding(get:{session.data.profile.growthEnabled != false},set:{value in Task {_=await session.update {$0.profile.growthEnabled=value}}}))} footer:{Text("从你明确的长期反馈里积累，例如“以后少用反问”。一次情绪、临时要求或别人的话不改变性格。当前聊天空间的习惯与其它私聊、群聊分开。")}
            ForEach(session.data.experiences ?? []) {note in
                Section(session.profile(CompanionPersona(rawValue:note.ownerID) ?? session.persona).title) {
                    Text(note.text);Text("依据："+note.quote).font(.caption).foregroundStyle(.secondary)
                    HStack {Button("修改") {editing=note};Spacer();Button("删除",role:.destructive) {Task {_=await session.update {$0.experiences?.removeAll {$0.id==note.id}}}}}
                }
            }
            if (session.data.experiences ?? []).isEmpty {Text("还没有积累相处习惯。你可以直接告诉这位伙伴，希望以后怎样与你聊天。").foregroundStyle(.secondary)}
        }.navigationTitle("相处习惯").navigationBarTitleDisplayMode(.inline)
            .sheet(item:$editing) {note in NavigationStack {CompanionExperienceEditor(session:session,note:note)}}
    }
}

private struct CompanionExperienceEditor:View {
    @ObservedObject var session:CompanionSession
    let note:CompanionExperience
    @Environment(\.dismiss) private var dismiss
    @State private var text=""
    var body:some View {Form {TextEditor(text:$text).frame(minHeight:150);Text("原始依据："+note.quote).font(.caption).foregroundStyle(.secondary)}.navigationTitle("修改习惯").onAppear {text=note.text}.toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("保存") {Task {if await session.update({data in if let index=data.experiences?.firstIndex(where:{$0.id==note.id}) {data.experiences?[index].text=text.trimmingCharacters(in:.whitespacesAndNewlines)}}) {dismiss()}}}.disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || text.count>160 || session.busy)}}}
}

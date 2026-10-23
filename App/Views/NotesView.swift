import UIKit
import SwiftUI
import Vision
import VisionKit

struct NotesView:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.colorScheme) var scheme
    @State var query=""
    @State var scope="active"
    @State var editing:Item?
    @State var creating=false
    var notes:[Item] {store.current.notes.filter {n in (scope=="trash" ? n.int("deletedAt")>0:scope=="archived" ? n.bool("archived") && n.int("deletedAt")==0:!n.bool("archived") && n.int("deletedAt")==0) && (query.isEmpty || (n.text("title")+n.text("body")+n.text("folder")).localizedCaseInsensitiveContains(query))}.sorted {a,b in a.bool("pinned")==b.bool("pinned") ? a.int("updatedAt")>b.int("updatedAt"):a.bool("pinned")}}
    var body:some View {
        List {
            if notes.isEmpty {EmptyState(icon:"note.text",title:query.isEmpty ? "记下此刻的想法":"没有找到笔记",subtitle:query.isEmpty ? "点右下角＋，开始写第一篇笔记":"换个关键词再试试").listRowBackground(Color.clear).listRowSeparator(.hidden)}
            ForEach(notes) {n in
                Button {editing=n} label:{VStack(alignment:.leading,spacing:7) {
                    HStack(spacing:6) {if n.bool("pinned") {Image(systemName:"pin.fill").font(.caption2).foregroundStyle(Theme.accent)};Text(n.text("title")).font(.system(size:15,weight:.semibold)).foregroundStyle(.primary).lineLimit(1);Spacer()}
                    Text(NoteText.snippet(n.text("body"))).font(.system(size:13)).foregroundStyle(.secondary).lineLimit(2)
                    Text(Date(timeIntervalSince1970:Double(n.int("updatedAt"))/1000).formatted(.dateTime.month().day())+" · "+n.text("folder",fallback:"收件箱")).font(.system(size:10)).foregroundStyle(.tertiary)
                }.padding(.vertical,8).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityIdentifier("note.row.\(n.id)")
                    .swipeActions(edge:.trailing,allowsFullSwipe:false) {Button(role:.destructive) {mutate(n,key:"deletedAt",value:.int(Clock.milliseconds))} label:{Label("删除",systemImage:"trash")};if scope=="trash" {Button {mutate(n,key:"deletedAt",value:.int(0))} label:{Label("恢复",systemImage:"arrow.uturn.backward")}.tint(Theme.accent)}}
                    .contextMenu {Button(n.bool("pinned") ? "取消置顶":"置顶",systemImage:"pin") {mutate(n,key:"pinned",value:.bool(!n.bool("pinned")))};Button(n.bool("archived") ? "移出归档":"归档",systemImage:"archivebox") {mutate(n,key:"archived",value:.bool(!n.bool("archived")))}}
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background {Theme.background(scheme).ignoresSafeArea()}.appClearChrome()
            .searchable(text:$query,prompt:"搜索笔记").navigationTitle(scope=="trash" ? "最近删除":scope=="archived" ? "已归档":"笔记").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.topBarLeading) {Menu {Button("全部笔记") {scope="active"};Button("已归档") {scope="archived"};Button("最近删除") {scope="trash"};Button("新建笔记",systemImage:"plus") {creating=true}} label:{Image(systemName:"line.3.horizontal.decrease").accessibilityLabel("笔记筛选")}}}
            .sheet(item:$editing) {n in NavigationStack {NoteEditor(note:n)}.environmentObject(store)}
            .sheet(isPresented:$creating) {NavigationStack {NoteEditor()}.environmentObject(store)}
    }
    func mutate(_ note:Item,key:String,value:JSONValue) {var n=note;n.raw[key]=value;n.set("updatedAt",Clock.milliseconds);Task {await store.commit {$0.upsert(n,in:"notes")}}}
}

struct NoteEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var scheme
    var note:Item?
    @State var noteID=UUID().uuidString.lowercased()
    @State var title=""
    @State var bodyText=""
    @State var folder="收件箱"
    @State var tools=false
    @State var working=false
    @State private var aiMode:String?
    @State var scanner=false
    @State var dirty=false
    @State private var proposal:NoteAIProposal?
    @State var confirmClose=false
    @State var savedTitle=""
    @State var savedBody=""
    @State var undo:(String,String)?
    @State var task:Task<Void,Never>?
    @State var operationID=UUID()
    @State var draftTask:Task<Void,Never>?
    @State var draftLoaded=false
    @State var recovery:Item?
    @State var recoverPrompt=false
    var body:some View {
        VStack(spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    if let proposal {
                        Text(proposal.displayed.title).font(.system(size:21,weight:.semibold))
                            .aiText(initial:proposal.replacesSource).accessibilityIdentifier("note.proposal.title")
                        VStack(alignment:.leading,spacing:16) {
                            if !proposal.replacesSource {Text(proposal.source.body).font(.system(size:15)).lineSpacing(7);Divider()}
                            MarkdownBody(text:proposal.result.body).aiText(initial:true)
                                .accessibilityIdentifier("note.proposal.body")
                            if !proposal.evidence.isEmpty {
                                DisclosureGroup("查看原文依据") {ForEach(Array(proposal.evidence.enumerated()),id:\.offset) {_,quote in Text(quote).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)}}
                            }
                        }.frame(maxWidth:.infinity,minHeight:320,alignment:.topLeading)
                    } else {
                        if working && aiMode=="润色" {TextSkeleton(text:title,font:UIFont.systemFont(ofSize:21,weight:.semibold),lineSpacing:0).accessibilityIdentifier("note.title.skeleton")}
                        else {TextField("标题",text:$title,axis:.vertical).font(.system(size:21,weight:.semibold)).lineLimit(1...4).accessibilityIdentifier("note.title").disabled(working)}
                        if working && aiMode != nil {TextSkeleton(text:bodyText).frame(minHeight:320,alignment:.topLeading).accessibilityIdentifier("note.body.skeleton")}
                        else {TextField("记录你的想法…",text:$bodyText,axis:.vertical).font(.system(size:15)).lineSpacing(7).frame(minHeight:320,alignment:.topLeading).accessibilityIdentifier("note.body").disabled(working)}
                    }
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively)
            AppGlassGroup {VStack(spacing:10) {
                if working {ProcessingBar(label:"正在整理笔记").padding(.horizontal,16)}
                if tools && !working && proposal==nil {ScrollView(.horizontal,showsIndicators:false) {HStack(spacing:8) {aiButton("润色","wand.and.stars");aiButton("摘要","text.alignleft");aiButton("要点","list.bullet");aiButton("会议纪要","person.2");aiButton("行动清单","checklist")}.padding(.horizontal,16)}.transition(.move(edge:.bottom).combined(with:.opacity))}
                HStack {
                    if let pending=proposal {
                        Button("取消") {proposal=nil}.accessibilityIdentifier("note.proposal.cancel")
                        Spacer()
                        Button("采纳") {adopt(pending)}.fontWeight(.semibold)
                            .padding(.horizontal,20).padding(.vertical,10).appGlass(Capsule(),interactive:true,tinted:true).foregroundStyle(.white)
                            .accessibilityIdentifier("note.proposal.adopt")
                    } else {
                        if !working {Button {withAnimation(Theme.normal) {tools.toggle()}} label:{HStack(spacing:6) {AIOrb().frame(width:20,height:20);Text("AI 工具").font(.caption.weight(.medium));Image(systemName:tools ? "chevron.down":"chevron.up").font(.system(size:10))}.padding(10).appGlass(Capsule(),interactive:true)}.buttonStyle(.plain)}
                        if working {Button("取消") {cancelOperation()}.font(.caption)}
                        Spacer()
                        if undo != nil && !working {Button {if let previous=undo {title=previous.0;bodyText=previous.1;undo=nil}} label:{Image(systemName:"arrow.uturn.backward")}.accessibilityLabel("撤销采用")}
                        Button {if VNDocumentCameraViewController.isSupported {scanner=true} else {store.error="这台设备不支持文稿扫描"}} label:{Image(systemName:"text.viewfinder").frame(width:38,height:38)}.accessibilityLabel("拍照识字").disabled(working)
                    }
                }.padding(.horizontal,16)
            }.padding(.vertical,8)}
        }.background {Theme.background(scheme).ignoresSafeArea()}.appClearChrome().navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction) {Button("关闭") {if proposal != nil {proposal=nil}else if title != savedTitle || bodyText != savedBody {confirmClose=true}else{dismiss()}}};ToolbarItem(placement:.confirmationAction) {Button("保存") {save()}.disabled(store.busy || working || proposal != nil || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}
            .interactiveDismissDisabled(working || proposal != nil || title != savedTitle || bodyText != savedBody)
            .confirmationDialog("保存笔记后再关闭？",isPresented:$confirmClose,titleVisibility:.visible) {Button("保存并关闭") {save()}.disabled(working || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty);Button("放弃更改",role:.destructive) {draftTask?.cancel();try? FileManager.default.removeItem(at:PrivateFiles.url("note-draft.pavault"));dismiss()};Button("继续编辑",role:.cancel) {}}
            .onAppear {load()}.onChange(of:title) {_,_ in scheduleDraft()}.onChange(of:bodyText) {_,_ in scheduleDraft()}
            .onDisappear {cancelOperation();draftTask?.cancel()}
            .confirmationDialog("找到未保存的笔记草稿",isPresented:$recoverPrompt,titleVisibility:.visible) {Button("恢复草稿") {if let n=recovery {title=n.text("title");bodyText=n.text("body")}};Button("保留已保存内容",role:.cancel) {}}
            .sheet(isPresented:$scanner) {DocumentScanner {images in scanner=false;task=Task {working=true;defer{working=false};do {let result=try await OCRService.recognize(images);bodyText+=(bodyText.isEmpty ? "":"\n")+result}catch{store.present(error)}}} onCancel:{scanner=false}}
    }
    func aiButton(_ mode:String,_ icon:String)->some View {Button {run(mode)} label:{Label(mode,systemImage:icon).font(.caption).padding(.horizontal,12).padding(.vertical,9).appGlass(Capsule(),interactive:true)}.buttonStyle(.plain).disabled(working)}
    func load() {
        guard !draftLoaded else{return};draftLoaded=true
        if let n=note {noteID=n.id;title=n.text("title");bodyText=n.text("body");folder=n.text("folder",fallback:"收件箱")}
        #if DEBUG
        if DebugFixtures.motion {title="周末计划";bodyText="想去公园走走。\n和朋友吃顿饭。\n也留一点时间休息。";working=true;aiMode="润色"}
        if DebugFixtures.proposals {title="周末计划";bodyText="想去公园走走。\n和朋友吃顿饭。\n也留一点时间休息。"}
        #endif
        savedTitle=title;savedBody=bodyText
        let key=store.key,id=note?.id ?? "new"
        if let bytes=try? PrivateFiles.boundedRead(PrivateFiles.url("note-draft.pavault")),let plain=try? VaultCrypto.decrypt(bytes,key:key),let draft=try? JSONDecoder().decode(Item.self,from:plain),draft.text("slot")==id,draft.int("baseUpdatedAt")==((note?.int("updatedAt")) ?? 0) {recovery=draft;recoverPrompt=true}
    }
    func scheduleDraft() {
        guard draftLoaded,!recoverPrompt,store.document != nil else{return};draftTask?.cancel()
        guard title != savedTitle || bodyText != savedBody else {
            try? FileManager.default.removeItem(at:PrivateFiles.url("note-draft.pavault"));dirty=false;return
        };dirty=true
        let draft=Item(["slot":.string(note?.id ?? "new"),"baseUpdatedAt":.int(note?.int("updatedAt") ?? 0),"title":.string(title),"body":.string(bodyText)]),key=store.key,salt=store.salt
        draftTask=Task {do {try await Task.sleep(nanoseconds:750_000_000);try Task.checkCancellation();let plain=try JSONEncoder().encode(draft);try PrivateFiles.write(VaultCrypto.encrypt(plain,key:key,salt:salt),name:"note-draft.pavault")}catch{}}
    }
    func save() {
        guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {store.error="请填写笔记标题";return}
        var n=note ?? Item(["id":.string(noteID),"createdAt":.int(Clock.milliseconds)]);n.set("title",title);n.set("body",bodyText);n.set("updatedAt",Clock.milliseconds);n.set("folder",folder)
        Task {if await store.commit({$0.upsert(n,in:"notes")}) {draftTask?.cancel();try? FileManager.default.removeItem(at:PrivateFiles.url("note-draft.pavault"));dismiss()}}
    }
    func run(_ mode:String) {
        guard !working,proposal==nil else {return}
        #if DEBUG
        if DebugFixtures.proposals {proposal=DebugFixtures.proposal(mode:mode,title:title,body:bodyText);tools=false;return}
        #endif
        guard !bodyText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {store.error="请先填写笔记正文";return}
        guard store.cloudEnabled && store.hasAPIKey else {store.error="笔记润色与整理使用云端，请先在个人详情配置 DeepSeek 并开启云端智能";return}
        let epoch=store.epoch,source=bodyText,originalTitle=title,model=store.model
        let operation=UUID();operationID=operation;aiMode=mode;working=true;tools=false
        task=Task {defer{if operationID==operation {working=false;aiMode=nil}};do {
            let sourceVersion=NoteTextVersion(title:originalTitle,body:source)
            let pending:NoteAIProposal
            if mode=="润色" {
                let result=try await AIService.polish(title:originalTitle,body:source,model:model)
                pending=NoteAIProposal(mode:mode,source:sourceVersion,result:NoteTextVersion(title:result.0,body:result.1))
            } else {
                let result=try await AIService.noteAction(source,mode:mode,model:model)
                pending=NoteAIProposal(mode:mode,source:sourceVersion,result:NoteTextVersion(title:originalTitle,body:result.body),evidence:result.evidence)
            }
            try Task.checkCancellation()
            guard operationID==operation,store.epoch==epoch else {return}
            proposal=pending
        }catch{if operationID==operation,store.epoch==epoch {store.present(error)}}}
    }
    func adopt(_ pending:NoteAIProposal) {
        guard let adopted=pending.adopting(over:NoteTextVersion(title:title,body:bodyText)) else {
            proposal=nil;store.error="原文已更改，请重新运行 AI 工具";return
        }
        undo=(title,bodyText);title=adopted.title;bodyText=adopted.body;proposal=nil
    }
    func cancelOperation() {operationID=UUID();task?.cancel();task=nil;working=false;aiMode=nil}
}

enum OCRService {
    static func recognize(_ images:[UIImage]) async throws -> String {
        try await Task.detached(priority:.userInitiated) {
            var output:[String]=[]
            for image in images {
                try Task.checkCancellation()
                guard let cg=image.cgImage else {continue}
                let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.recognitionLanguages=["zh-Hans","en-US"];request.usesLanguageCorrection=true
                try VNImageRequestHandler(cgImage:cg,options:[:]).perform([request])
                output.append((request.results ?? []).compactMap {$0.topCandidates(1).first?.string}.joined(separator:"\n"))
            }
            let result=output.joined(separator:"\n\n");guard !result.isEmpty else {throw AppError.message("没有识别出文字，请在光线充足处重新拍摄")};return result
        }.value
    }
}
struct DocumentScanner:UIViewControllerRepresentable {
    var onResult:([UIImage])->Void,onCancel:()->Void
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeUIViewController(context:Context)->VNDocumentCameraViewController {let c=VNDocumentCameraViewController();c.delegate=context.coordinator;return c}
    func updateUIViewController(_ uiViewController:VNDocumentCameraViewController,context:Context) {}
    final class Coordinator:NSObject,VNDocumentCameraViewControllerDelegate {
        let parent:DocumentScanner
        init(_ parent:DocumentScanner) {self.parent=parent}
        func documentCameraViewControllerDidCancel(_ controller:VNDocumentCameraViewController) {parent.onCancel()}
        func documentCameraViewController(_ controller:VNDocumentCameraViewController,didFailWithError error:Error) {parent.onCancel()}
        func documentCameraViewController(_ controller:VNDocumentCameraViewController,didFinishWith scan:VNDocumentCameraScan) {parent.onResult((0..<min(10,scan.pageCount)).map {scan.imageOfPage(at:$0)})}
    }
}

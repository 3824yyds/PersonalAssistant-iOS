import UIKit
import SwiftUI
import Vision
import VisionKit
import PhotosUI
import UniformTypeIdentifiers

struct NotesView:View {
    @Binding var sheet:RootSheet?
    @EnvironmentObject var store:AppStore
    @Environment(\.colorScheme) var scheme
    @State var query=""
    @State var scope="active"
    @State var editing:Item?
    @State var creating=false
    @State private var folderFilter=""
    @State private var addingFolder=false
    @State private var folderName=""
    @State private var deleting:Item?
    @AppStorage("notes.sort") private var sort="updated"
    @AppStorage("notes.gallery") private var gallery=false
    var folders:[String] {Array(Set(["收件箱"]+store.current.notes.map {$0.text("folder",fallback:"收件箱")}+store.current.root.strings("noteFolders"))).sorted()}
    var notes:[Item] {store.current.notes.filter {note in
        (scope=="trash" ? note.int("deletedAt")>0:scope=="archived" ? note.bool("archived") && note.int("deletedAt")==0:!note.bool("archived") && note.int("deletedAt")==0)
        && (folderFilter.isEmpty || note.text("folder",fallback:"收件箱")==folderFilter)
        && (query.isEmpty || (NoteContent.text(note)+note.text("folder")).localizedCaseInsensitiveContains(query))
    }.sorted {a,b in
        if a.bool("pinned") != b.bool("pinned") {return a.bool("pinned")}
        if sort=="title" {return a.text("title").localizedStandardCompare(b.text("title")) == .orderedAscending}
        return a.int(sort=="created" ? "createdAt":"updatedAt")>b.int(sort=="created" ? "createdAt":"updatedAt")
    }}
    var groups:[String] {notes.reduce(into:[]) {result,note in let name=NoteContent.group(note);if !result.contains(name) {result.append(name)}}}
    var pageTitle:String {scope=="trash" ? "最近删除":scope=="archived" ? "已归档":folderFilter.isEmpty ? "备忘录":folderFilter}
    var body:some View {
        VStack(spacing:0) {
            PageHeader(title:"",sheet:$sheet) {
                Menu {
                    Section("文件夹") {Button("全部备忘录") {folderFilter="";scope="active"};ForEach(folders,id:\.self) {folder in Button(folder) {folderFilter=folder;scope="active"}};Button("新建文件夹",systemImage:"folder.badge.plus") {addingFolder=true}}
                    Section {Button("已归档") {scope="archived"};Button("最近删除") {scope="trash"}}
                    Section {Picker("排序",selection:$sort) {Text("修改日期").tag("updated");Text("创建日期").tag("created");Text("标题").tag("title")};Toggle("画廊视图",isOn:$gallery)}
                } label:{Image(systemName:"folder").accessibilityLabel("笔记筛选")}
            }
            if gallery && !notes.isEmpty {
                ScrollView {VStack(alignment:.leading,spacing:16) {
                    heading
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {ForEach(notes) {note in noteRow(note).padding(14).frame(maxWidth:.infinity,minHeight:150,alignment:.topLeading).background(Theme.panel(scheme),in:RoundedRectangle(cornerRadius:18))}}
                }.padding(16)}.clipped()
            } else {
                List {
                    heading.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top:4,leading:0,bottom:12,trailing:0))
                    if notes.isEmpty {EmptyState(icon:"note.text",title:query.isEmpty ? "记下此刻的想法":"没有找到笔记",subtitle:query.isEmpty ? "点右下角＋，开始写第一篇笔记":"换个关键词再试试").listRowBackground(Color.clear).listRowSeparator(.hidden)}
                    ForEach(groups,id:\.self) {group in
                        Section {ForEach(notes.filter {NoteContent.group($0)==group}) {note in noteRow(note)}} header:{Text(group).font(.title3.weight(.bold)).foregroundStyle(.primary).textCase(nil)}
                    }
                }.listStyle(.insetGrouped).scrollContentBackground(.hidden).clipped()
            }
            FloatingSearchField(text:$query,prompt:"搜索备忘录")
        }.background {Theme.background(scheme).ignoresSafeArea()}.appClearChrome().toolbar(.hidden,for:.navigationBar)
            .sheet(item:$editing) {note in NavigationStack {NoteEditor(note:note)}.environmentObject(store)}
            .sheet(isPresented:$creating) {NavigationStack {NoteEditor(initialFolder:store.noteFolder)}.environmentObject(store)}
            .onChange(of:folderFilter) {_,value in store.noteFolder=value.isEmpty ? "收件箱":value}
            .alert("新建文件夹",isPresented:$addingFolder) {TextField("名称",text:$folderName);Button("取消",role:.cancel) {};Button("创建") {let name=folderName.trimmingCharacters(in:.whitespacesAndNewlines);guard !name.isEmpty,name.count<=100 else {return};Task {if await store.commit({document in document.root.raw["noteFolders"] = .array(Array(Set(document.root.strings("noteFolders")+[name])).sorted().map(JSONValue.string))}) {folderFilter=name;folderName=""}}}}
            .confirmationDialog("永久删除这篇备忘录？",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}}),titleVisibility:.visible) {Button("永久删除",role:.destructive) {guard let note=deleting else{return};Task {await store.commit {$0.notes.removeAll {$0.id==note.id}}};deleting=nil}}
    }
    private var heading:some View {VStack(alignment:.leading,spacing:4) {Text(pageTitle).font(.largeTitle.bold());Text("\(notes.count)个备忘录").font(.subheadline).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)}
    private func noteRow(_ note:Item)->some View {
        Button {editing=note} label:{VStack(alignment:.leading,spacing:5) {
            HStack {if note.bool("pinned") {Image(systemName:"pin.fill").font(.caption).foregroundStyle(.yellow)};Text(note.text("title")).font(.system(size:17,weight:.semibold)).foregroundStyle(.primary).lineLimit(1);Spacer(minLength:0)}
            HStack(spacing:7) {Text(Date(timeIntervalSince1970:Double(note.int("updatedAt"))/1000).formatted(.dateTime.month().day())).font(.subheadline);Text(note.text("body").isEmpty ? (note.items("attachments").isEmpty ? "无更多文本":"含附件"):NoteText.snippet(note.text("body"))).font(.subheadline).lineLimit(1)}.foregroundStyle(.secondary)
            if !note.items("checklist").isEmpty {Text("清单 \(note.items("checklist").filter {$0.bool("done")}.count)/\(note.items("checklist").count)").font(.caption).foregroundStyle(.secondary)}
            if let attachment=note.items("attachments").first,let data=Data(base64Encoded:attachment.text("kind")=="drawing" ? attachment.text("preview"):attachment.text("data")),let image=UIImage(data:data) {Image(uiImage:image).resizable().scaledToFill().frame(height:gallery ? 100:45).clipped().clipShape(RoundedRectangle(cornerRadius:7))}
        }.padding(.vertical,5).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityIdentifier("note.row.\(note.id)")
            .swipeActions(edge:.trailing,allowsFullSwipe:false) {
                if scope=="trash" {Button("恢复") {mutate(note,key:"deletedAt",value:.int(0))}.tint(Theme.accent);Button("永久删除",role:.destructive) {deleting=note}}
                else {Button(role:.destructive) {mutate(note,key:"deletedAt",value:.int(Clock.milliseconds))} label:{Label("删除",systemImage:"trash")}}
            }.contextMenu {
                Button(note.bool("pinned") ? "取消置顶":"置顶",systemImage:"pin") {mutate(note,key:"pinned",value:.bool(!note.bool("pinned")))}
                Menu("移到文件夹",systemImage:"folder") {ForEach(folders,id:\.self) {folder in Button(folder) {mutate(note,key:"folder",value:.string(folder))}}}
                Button(note.bool("archived") ? "移出归档":"归档",systemImage:"archivebox") {mutate(note,key:"archived",value:.bool(!note.bool("archived")))}
            }
    }
    func mutate(_ note:Item,key:String,value:JSONValue) {var n=note;n.raw[key]=value;n.set("updatedAt",Clock.milliseconds);Task {await store.commit {$0.upsert(n,in:"notes")}}}
}

struct NoteEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var scheme
    var note:Item?
    var initialFolder="收件箱"
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
    @State private var richText=""
    @State private var checklist:[Item]=[]
    @State private var tables:[Item]=[]
    @State private var attachments:[Item]=[]
    @State private var savedExtras=Item()
    @State private var pinned=false
    @State private var archived=false
    @State private var baseNote:Item?
    @State private var formatting:NoteFormatCommand?
    @State private var tableEditing:Item?
    @State private var drawingEditing:Item?
    @State private var newDrawing=false
    @State private var photoPicker=false
    @State private var photos:[PhotosPickerItem]=[]
    @State private var files=false
    @State private var previewAttachment:Item?
    @State private var scannerText=false
    @State private var folderPrompt=false
    @State private var photoTask:Task<Void,Never>?
    @State private var undoRich=""
    @FocusState private var checklistFocus:String?
    private var extras:Item {Item(["folder":.string(folder),"richText":.string(richText),"pinned":.bool(pinned),"archived":.bool(archived),"checklist":.array(checklist.map {.object($0.raw)}),"tables":.array(tables.map {.object($0.raw)}),"attachments":.array(attachments.map {.object($0.raw)})])}
    private var hasChanges:Bool {title != savedTitle || bodyText != savedBody || extras != savedExtras}
    private var canSave:Bool {!title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !bodyText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || checklist.contains {!$0.text("text").isEmpty} || !tables.isEmpty || !attachments.isEmpty}
    var body:some View {
        drawingSheets.appErrorScope()
            .sheet(item:$previewAttachment) {attachment in NoteAttachmentPreview(attachment:attachment)}
            .alert("文件夹",isPresented:$folderPrompt) {TextField("名称",text:$folder);Button("完成") {if folder.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {folder="收件箱"}}}
    }
    private var editorScroll:some View {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text(Date(timeIntervalSince1970:Double(baseNote?.int("updatedAt",fallback:Clock.milliseconds) ?? Clock.milliseconds)/1000).formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity)
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
                        else {NoteRichText(text:$bodyText,richText:$richText,command:formatting).frame(minHeight:320,alignment:.topLeading).disabled(working)}
                    }
                    if proposal==nil {structuredContent.disabled(working)}
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively)
    }
    private var editorFooter:some View {
            AppGlassGroup {VStack(spacing:10) {
                if working {ProcessingBar(label:"正在整理笔记").padding(.horizontal,16)}
                if tools && !working && proposal==nil {ScrollView(.horizontal,showsIndicators:false) {HStack(spacing:8) {aiButton("润色","wand.and.stars");aiButton("摘要","text.alignleft");aiButton("要点","list.bullet");aiButton("会议纪要","person.2");aiButton("行动清单","checklist")}.padding(.horizontal,16)}.accessibilityIdentifier("note.ai.tools").transition(.move(edge:.bottom).combined(with:.opacity))}
                HStack {
                    if let pending=proposal {
                        Button("取消") {proposal=nil}.accessibilityIdentifier("note.proposal.cancel")
                        Spacer()
                        Button("采纳") {adopt(pending)}.fontWeight(.semibold)
                            .padding(.horizontal,20).padding(.vertical,10).appGlass(Capsule(),interactive:true,tinted:true).foregroundStyle(.white)
                            .accessibilityIdentifier("note.proposal.adopt")
                    } else {
                        if !working {Button {withAnimation(Theme.normal) {tools.toggle()}} label:{HStack(spacing:6) {AIOrb().frame(width:20,height:20);if undo==nil {Text("AI").font(.caption.weight(.medium));Image(systemName:tools ? "chevron.down":"chevron.up").font(.system(size:10))}}.padding(10).appGlass(Capsule(),interactive:true)}.buttonStyle(.plain).accessibilityLabel("AI 工具").accessibilityIdentifier("note.ai.tools.toggle")}
                        if working {Button("取消") {cancelOperation()}.font(.caption)}
                        Spacer()
                        if undo != nil && !working {Button {if let previous=undo {title=previous.0;bodyText=previous.1;richText=undoRich;undo=nil}} label:{Image(systemName:"arrow.uturn.backward")}.accessibilityLabel("撤销采用")}
                        if !working {editingTools}
                    }
                }.padding(.horizontal,16)
            }.padding(.vertical,8)}
    }
    @ToolbarContentBuilder private var editorToolbar:some ToolbarContent {
                ToolbarItem(placement:.cancellationAction) {Button {proposal=nil;cancelOperation();if hasChanges && canSave {save()}else{dismiss()}} label:{Image(systemName:"chevron.left")}.accessibilityLabel("关闭")}
                ToolbarItemGroup(placement:.topBarTrailing) {
                    ShareLink(item:NoteContent.text(snapshot())) {Image(systemName:"square.and.arrow.up")}.disabled(!canSave || working)
                    Menu {
                        Button(pinned ? "取消置顶":"置顶",systemImage:"pin") {pinned.toggle()}
                        Button("移到文件夹",systemImage:"folder") {folderPrompt=true}
                        Button(archived ? "移出归档":"归档",systemImage:"archivebox") {archived.toggle()}
                        if baseNote != nil {Button("删除备忘录",role:.destructive) {var value=snapshot();value.set("deletedAt",Clock.milliseconds);Task {if await store.commit({$0.upsert(value,in:"notes")}) {dismiss()}}}}
                    } label:{Image(systemName:"ellipsis")}.accessibilityLabel("备忘录选项").disabled(working || proposal != nil)
                    Button {UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil);save(close:false)} label:{Image(systemName:"checkmark").fontWeight(.semibold).frame(width:32,height:32).background(Color(red:0.89,green:0.68,blue:0),in:Circle()).foregroundStyle(.white)}.accessibilityLabel("保存").disabled(store.busy || working || proposal != nil || !canSave)
                }
    }
    private var editorSurface:some View {
        VStack(spacing:0) {editorScroll;editorFooter}
            .background {Color(uiColor:.systemBackground).ignoresSafeArea()}
            .appClearChrome().navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {editorToolbar}
            .interactiveDismissDisabled(working || proposal != nil || hasChanges)
    }
    private var observedEditor:some View {
        editorSurface
            .onAppear {load()}
            .onChange(of:title) {_,_ in scheduleDraft()}
            .onChange(of:bodyText) {_,_ in scheduleDraft()}
            .onChange(of:extras) {_,_ in scheduleDraft()}
            .onDisappear {photoTask?.cancel();cancelOperation();draftTask?.cancel()}
            .confirmationDialog("找到未保存的笔记草稿",isPresented:$recoverPrompt,titleVisibility:.visible) {
                Button("恢复草稿") {if let value=recovery {title=value.text("title");bodyText=value.text("body");loadExtras(value)}}
                Button("保留已保存内容",role:.cancel) {}
            }
    }
    private var importSheets:some View {
        observedEditor
            .sheet(isPresented:$scanner) {DocumentScanner(onResult:processScan,onCancel:{scanner=false})}
            .photosPicker(isPresented:$photoPicker,selection:$photos,maxSelectionCount:4,matching:.images)
            .onChange(of:photos) {_,items in importPhotos(items)}
            .fileImporter(isPresented:$files,allowedContentTypes:[.item],allowsMultipleSelection:false) {result in
                do {if let url=try result.get().first {try appendFile(url)}} catch {store.present(error)}
            }
    }
    private var drawingSheets:some View {
        importSheets
            .sheet(item:$tableEditing) {table in NavigationStack {NoteTableEditor(original:table,onSave:saveTable)}}
            .sheet(isPresented:$newDrawing) {NavigationStack {NoteDrawingEditor {data,preview in saveDrawing(data,preview:preview)}}}
            .sheet(item:$drawingEditing) {drawing in NavigationStack {NoteDrawingEditor(initial:Data(base64Encoded:drawing.text("data"))) {data,preview in saveDrawing(data,preview:preview,id:drawing.id)}}}
    }
    private func saveTable(_ value:Item) {
        if let index=tables.firstIndex(where:{$0.id==value.id}) {tables[index]=value}else{tables.append(value)}
    }
    private func processScan(_ images:[UIImage]) {
        scanner=false
        task=Task {
            working=true;defer{working=false}
            do {
                if scannerText {let result=try await OCRService.recognize(images);bodyText+=(bodyText.isEmpty ? "":"\n")+result}
                else {for image in images {if let data=image.jpegData(compressionQuality:0.85) {try appendImage(data,name:"扫描文稿.jpg")}}}
            } catch {store.present(error)}
        }
    }
    private var editingTools:some View {
        HStack(spacing:8) {
            Menu {ForEach(NoteFormat.allCases,id:\.self) {format in Button(format.rawValue) {formatting=NoteFormatCommand(action:format)}}} label:{Image(systemName:"textformat").frame(width:28,height:38)}.accessibilityLabel("格式")
            Button {addChecklist()} label:{Image(systemName:"checklist").frame(width:28,height:38)}.accessibilityLabel("添加清单")
            Button {tableEditing=NoteContent.table()} label:{Image(systemName:"tablecells").frame(width:28,height:38)}.accessibilityLabel("添加表格")
            Menu {
                Button("选取照片",systemImage:"photo") {photoPicker=true}
                Button("附加文件",systemImage:"doc") {files=true}
                Button("扫描文稿",systemImage:"doc.viewfinder") {startScan(text:false)}
                Button("扫描文字",systemImage:"text.viewfinder") {startScan(text:true)}
            } label:{Image(systemName:"paperclip").frame(width:28,height:38)}.accessibilityLabel("添加附件")
            Button {newDrawing=true} label:{Image(systemName:"pencil.tip.crop.circle").frame(width:28,height:38)}.accessibilityLabel("手绘")
        }.padding(.horizontal,6).appGlass(Capsule(),interactive:true)
    }
    private var structuredContent:some View {
        VStack(alignment:.leading,spacing:18) {
            ForEach(checklist) {item in
                HStack(alignment:.top,spacing:10) {
                    Button {if let index=checklist.firstIndex(where:{$0.id==item.id}) {checklist[index].set("done",!item.bool("done"))}} label:{Image(systemName:item.bool("done") ? "checkmark.circle.fill":"circle").foregroundStyle(item.bool("done") ? Color.yellow:.secondary).font(.title3)}.accessibilityLabel(item.bool("done") ? "取消勾选":"勾选清单")
                    TextField("清单项",text:Binding(get:{checklist.first {$0.id==item.id}?.text("text") ?? ""},set:{text in if let index=checklist.firstIndex(where:{$0.id==item.id}) {checklist[index].set("text",text)}}),axis:.vertical).accessibilityIdentifier("note.checklist."+item.id).strikethrough(item.bool("done")).focused($checklistFocus,equals:item.id).onSubmit {addChecklist()}
                }.contextMenu {Button("删除清单项",role:.destructive) {checklist.removeAll {$0.id==item.id}}}
            }
            ForEach(tables) {table in
                let cells=NoteContent.cells(table)
                ScrollView(.horizontal,showsIndicators:false) {
                    Grid(horizontalSpacing:0,verticalSpacing:0) {ForEach(cells.indices,id:\.self) {row in GridRow {ForEach(cells[row].indices,id:\.self) {column in Text(cells[row][column].isEmpty ? " ":cells[row][column]).font(.body).frame(minWidth:100,minHeight:36,alignment:.leading).padding(7).border(.secondary.opacity(0.3),width:0.5)}}}}
                }.contentShape(Rectangle()).onTapGesture {tableEditing=table}.accessibilityLabel("编辑表格")
                    .contextMenu {Button("编辑表格") {tableEditing=table};Button("删除表格",role:.destructive) {tables.removeAll {$0.id==table.id}}}
            }
            ForEach(attachments) {attachment in
                Button {
                    if attachment.text("kind")=="drawing" {drawingEditing=attachment}else{previewAttachment=attachment}
                } label:{
                    VStack(alignment:.leading,spacing:6) {
                        if let data=Data(base64Encoded:attachment.text("kind")=="drawing" ? attachment.text("preview"):attachment.text("data")),let image=UIImage(data:data) {Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:240).clipShape(RoundedRectangle(cornerRadius:12))}
                        else {Label(attachment.text("name"),systemImage:"doc.fill").padding(14).frame(maxWidth:.infinity,alignment:.leading).background(.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:12))}
                        Text(attachment.text("name")).font(.caption).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain).contextMenu {Button("移除附件",role:.destructive) {attachments.removeAll {$0.id==attachment.id}}}
            }
        }
    }
    private func addChecklist() {guard checklist.count<500 else{return};let item=Item.make(["text":.string(""),"done":.bool(false)]);checklist.append(item);checklistFocus=item.id}
    private func startScan(text:Bool) {if VNDocumentCameraViewController.isSupported {scannerText=text;scanner=true}else{store.error="这台设备不支持文稿扫描"}}
    private func appendAttachment(_ item:Item) throws {
        var next=snapshot();next.set("attachments",items:attachments+[item]);try NoteContent.validate(next);attachments.append(item)
    }
    private func appendImage(_ data:Data,name:String) throws {
        let prepared=try ChatImageService.prepare(data)
        try appendAttachment(Item.make(["name":.string(name),"kind":.string("image"),"mime":.string("image/jpeg"),"data":.string(prepared.jpeg.base64EncodedString())]))
    }
    private func appendFile(_ url:URL) throws {
        let access=url.startAccessingSecurityScopedResource();defer{if access {url.stopAccessingSecurityScopedResource()}}
        let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size<=5*1024*1024 else {throw AppError.message("单个附件不能超过 5 MB")}
        let data=try Data(contentsOf:url,options:.mappedIfSafe)
        guard data.count<=5*1024*1024 else {throw AppError.message("单个附件不能超过 5 MB")}
        try appendAttachment(Item.make(["name":.string(String(url.lastPathComponent.prefix(200))),"kind":.string("file"),"mime":.string(UTType(filenameExtension:url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"),"data":.string(data.base64EncodedString())]))
    }
    private func importPhotos(_ items:[PhotosPickerItem]) {
        photoTask?.cancel();guard !items.isEmpty else{return};let epoch=store.epoch
        photoTask=Task {do {for item in items {try Task.checkCancellation();guard let data=try await item.loadTransferable(type:Data.self) else {continue};let image=try await Task.detached {try ChatImageService.prepare(data)}.value;try Task.checkCancellation();guard store.epoch==epoch else{return};try appendAttachment(Item.make(["name":.string("照片.jpg"),"kind":.string("image"),"mime":.string("image/jpeg"),"data":.string(image.jpeg.base64EncodedString())]))}}catch is CancellationError {}catch{store.present(error)}}
    }
    private func saveDrawing(_ data:Data,preview:Data,id:String?=nil) {
        let item=Item(["id":.string(id ?? UUID().uuidString.lowercased()),"name":.string("手绘.pkdrawing"),"kind":.string("drawing"),"data":.string(data.base64EncodedString()),"preview":.string(preview.base64EncodedString())])
        do {var proposed=snapshot();var values=attachments.filter {$0.id != item.id};values.append(item);proposed.set("attachments",items:values);try NoteContent.validate(proposed);attachments=values}catch{store.present(error)}
    }
    private func loadExtras(_ value:Item) {folder=value.text("folder",fallback:"收件箱");richText=value.text("richText");checklist=value.items("checklist");tables=value.items("tables");attachments=value.items("attachments");pinned=value.bool("pinned");archived=value.bool("archived")}
    private func snapshot()->Item {
        var value=baseNote ?? Item(["id":.string(noteID),"createdAt":.int(Clock.milliseconds)])
        for (key,item) in extras.raw {value.raw[key]=item}
        let candidate=title.trimmingCharacters(in:.whitespacesAndNewlines)
        let fallback=bodyText.split(separator:"\n").first.map(String.init) ?? checklist.first(where:{!$0.text("text").isEmpty})?.text("text") ?? attachments.first?.text("name") ?? (tables.isEmpty ? "新建备忘录":"表格")
        value.set("title",String((candidate.isEmpty ? fallback:candidate).prefix(200)));value.set("body",bodyText);value.set("updatedAt",Clock.milliseconds)
        return value
    }
    func aiButton(_ mode:String,_ icon:String)->some View {Button {run(mode)} label:{Label(mode,systemImage:icon).font(.caption).padding(.horizontal,12).padding(.vertical,9).appGlass(Capsule(),interactive:true)}.buttonStyle(.plain).disabled(working)}
    func load() {
        guard !draftLoaded else{return};draftLoaded=true
        baseNote=note
        folder=initialFolder
        if let n=note {noteID=n.id;title=n.text("title");bodyText=n.text("body");loadExtras(n)}
        #if DEBUG
        if DebugFixtures.motion {title="周末计划";bodyText="想去公园走走。\n和朋友吃顿饭。\n也留一点时间休息。";working=true;aiMode="润色"}
        if DebugFixtures.proposals {title="周末计划";bodyText="想去公园走走。\n和朋友吃顿饭。\n也留一点时间休息。"}
        #endif
        savedTitle=title;savedBody=bodyText;savedExtras=extras
        let key=store.key,id=note?.id ?? "new"
        if let bytes=try? PrivateFiles.boundedRead(PrivateFiles.url("note-draft.pavault")),let plain=try? VaultCrypto.decrypt(bytes,key:key),let draft=try? JSONDecoder().decode(Item.self,from:plain),draft.text("slot")==id,draft.int("baseUpdatedAt")==((note?.int("updatedAt")) ?? 0) {recovery=draft;recoverPrompt=true}
    }
    func scheduleDraft() {
        guard draftLoaded,!recoverPrompt,store.document != nil else{return};draftTask?.cancel()
        guard hasChanges else {
            try? FileManager.default.removeItem(at:PrivateFiles.url("note-draft.pavault"));dirty=false;return
        };dirty=true
        var draft=extras;draft.set("slot",baseNote?.id ?? "new");draft.set("baseUpdatedAt",baseNote?.int("updatedAt") ?? 0);draft.set("title",title);draft.set("body",bodyText)
        let key=store.key,salt=store.salt
        draftTask=Task {do {try await Task.sleep(nanoseconds:750_000_000);try Task.checkCancellation();let plain=try JSONEncoder().encode(draft);try PrivateFiles.write(VaultCrypto.encrypt(plain,key:key,salt:salt),name:"note-draft.pavault")}catch{}}
    }
    func save(close:Bool=true) {
        guard canSave else {return}
        let value=snapshot()
        Task {if await store.commit({$0.upsert(value,in:"notes")}) {draftTask?.cancel();try? FileManager.default.removeItem(at:PrivateFiles.url("note-draft.pavault"));baseNote=value;title=value.text("title");savedTitle=title;savedBody=bodyText;savedExtras=extras;if close {dismiss()}}}
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
        undo=(title,bodyText);undoRich=richText;richText="";title=adopted.title;bodyText=adopted.body;proposal=nil
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

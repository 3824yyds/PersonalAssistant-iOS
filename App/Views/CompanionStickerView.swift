import SwiftUI
import PhotosUI
import UIKit

struct CompanionStickerImage:View {
    let sticker:CompanionSticker
    var data:CompanionData?=nil
    var size:CGFloat=136
    var body:some View {
        Group {
            if let custom=data?.customStickers?.first(where:{$0.id==sticker.id}),let image=CompanionStickerPhoto.thumbnail(custom) {Image(uiImage:image).resizable().scaledToFit()}
            else if sticker.id.hasPrefix("custom:") {Image(systemName:"photo").resizable().scaledToFit().padding(25)}
            else {Image(sticker.asset).resizable().scaledToFit()}
        }.frame(width:size,height:size)
            .accessibilityLabel("表情包，"+sticker.description).accessibilityIdentifier("companion.sticker.image."+sticker.id)
    }
}

private struct StickerImport:Identifiable {let id=UUID();let image:Data}

struct CompanionStickerDock:View {
    @ObservedObject var session:CompanionSession
    @Environment(\.colorScheme) private var scheme
    var keyboard:()->Void
    @State private var mine=false
    @State private var photo:PhotosPickerItem?
    @State private var loading=false
    @State private var imported:StickerImport?
    @State private var photoTask:Task<Void,Never>?
    private var items:[CompanionSticker] {mine ? (session.data.customStickers ?? []).filter {!$0.archived}.map(\.descriptor):session.data.builtinStickers}
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:18) {
                Button {mine=false;session.touch()} label:{Label("伙伴",systemImage:"face.smiling").font(.subheadline).foregroundStyle(mine ? Color.secondary:Theme.accent)}.accessibilityIdentifier("companion.stickers.builtin")
                Button {mine=true;session.touch()} label:{Label("我的",systemImage:"heart").font(.subheadline).foregroundStyle(mine ? Theme.accent:Color.secondary)}.accessibilityIdentifier("companion.stickers.mine")
                Spacer()
                if loading {ProgressView().controlSize(.small)}
                addButton
                Button(action:keyboard) {Image(systemName:"keyboard").frame(width:34,height:38)}.accessibilityLabel("收起表情并打开键盘")
            }.padding(.horizontal,18).padding(.vertical,5)
            Divider()
            ScrollView {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:72))],spacing:12) {
                    ForEach(items) {sticker in
                        Button {session.sendSticker(sticker)} label:{
                            VStack(spacing:4) {CompanionStickerImage(sticker:sticker,data:session.data,size:66);Text(sticker.title).font(.caption2).lineLimit(1)}
                                .frame(maxWidth:.infinity).padding(.vertical,4).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(session.busy)
                            .accessibilityLabel("发送"+sticker.title+"表情包").accessibilityHint(sticker.meaning).accessibilityIdentifier("companion.sticker.send."+sticker.id)
                            .contextMenu {
                                if sticker.id.hasPrefix("custom:") {
                                    let allowed=session.data.customStickers?.first(where:{$0.id==sticker.id})?.allowAssistant ?? false
                                    Button(allowed ? "不让伙伴使用":"允许伙伴使用") {Task {await session.setStickerAllowed(sticker.id,!allowed)}}
                                    Button("移除表情",role:.destructive) {Task {await session.removeSticker(sticker.id)}}
                                }
                            }
                    }
                }.padding(.horizontal,14).padding(.vertical,12)
                if mine && items.isEmpty {Text("点击右上角＋，把照片添加为表情包。").font(.footnote).foregroundStyle(.secondary).padding(20)}
            }.frame(height:242)
        }.background(Theme.panel(scheme).opacity(0.85)).accessibilityElement(children:.contain).accessibilityIdentifier("companion.sticker.dock")
            .sheet(item:$imported) {item in NavigationStack {CompanionStickerEditor(session:session,image:item.image) {mine=true}}}
            .onChange(of:photo) {_,value in load(value)}
            .onDisappear {photoTask?.cancel();loading=false}
    }
    @ViewBuilder private var addButton:some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-custom-sticker-fixture") {
            Button {
                if let image=UIImage(named:"CompanionAvatar")?.pngData(),let prepared=try? CompanionStickerPhoto.prepare(image) {imported=StickerImport(image:prepared)}
            } label:{Image(systemName:"plus").frame(width:34,height:38)}.accessibilityLabel("添加照片表情").accessibilityIdentifier("companion.sticker.add").disabled(session.busy)
        } else {nativePhotoButton}
        #else
        nativePhotoButton
        #endif
    }
    private var nativePhotoButton:some View {
        PhotosPicker(selection:$photo,matching:.images,photoLibrary:.shared()) {Image(systemName:"plus").frame(width:34,height:38)}
            .accessibilityLabel("添加照片表情").accessibilityIdentifier("companion.sticker.add").disabled(session.busy || loading)
    }
    private func load(_ item:PhotosPickerItem?) {
        photoTask?.cancel();guard let item else {return};loading=true;session.touch()
        photoTask=Task {
            defer {loading=false;photo=nil}
            do {
                guard let bytes=try await item.loadTransferable(type:Data.self) else {throw AppError.message("照片未能载入，请重试")}
                let prepared=try await Task.detached(priority:.userInitiated) {try CompanionStickerPhoto.prepare(bytes)}.value
                try Task.checkCancellation();guard session.visible else {return};imported=StickerImport(image:prepared)
            } catch is CancellationError {} catch {session.error=error.localizedDescription}
        }
    }
}

private struct CompanionStickerEditor:View {
    @ObservedObject var session:CompanionSession
    let image:Data
    var onSaved:()->Void
    @Environment(\.dismiss) private var dismiss
    @State private var title=""
    @State private var meaning=""
    @State private var allow=true
    @State private var saving=false
    var body:some View {
        Form {
            Section {
                if let photo=UIImage(data:image) {Image(uiImage:photo).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:180)}
                TextField("表情名称",text:$title).accessibilityIdentifier("companion.sticker.title")
                TextField("它表达什么意思？",text:$meaning,axis:.vertical).lineLimit(2...4).accessibilityIdentifier("companion.sticker.meaning")
            } footer:{Text("名称最多16字，含义最多120字，例如“捂脸苦笑，表示无奈”。")}
            Section {
                Toggle("允许伙伴使用这张表情",isOn:$allow)
            } footer:{Text("照片保存在本机加密资料中；对话只发送名称和含义。移除已发过的表情时，聊天原图会保留。")}
            if let error=session.error {Section {Text(error).foregroundStyle(.red)}}
        }.navigationTitle("添加表情").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}.disabled(saving)}
                ToolbarItem(placement:.confirmationAction) {Button("保存") {save()}.disabled(saving || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || title.count>16 || meaning.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || meaning.count>120).accessibilityIdentifier("companion.sticker.save")}
            }.interactiveDismissDisabled(saving)
    }
    private func save() {
        saving=true;session.error=nil
        let sticker=CompanionCustomSticker(title:title.trimmingCharacters(in:.whitespacesAndNewlines),meaning:meaning.trimmingCharacters(in:.whitespacesAndNewlines),image:image,allowAssistant:allow)
        Task {if await session.addSticker(sticker) {onSaved();dismiss()};saving=false}
    }
}

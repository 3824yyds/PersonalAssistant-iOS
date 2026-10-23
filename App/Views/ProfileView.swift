import SwiftUI
import PhotosUI
import ImageIO

struct ProfilePortrait:View {
    @EnvironmentObject var store:AppStore
    @State private var image:UIImage?
    var size:CGFloat=32
    var preset:String {store.current.settings.text("profileAvatar",fallback:"cat")}
    var encoded:String {store.current.settings.text("profilePng")}
    var body:some View {
        Group {
            if preset=="custom",let image {Image(uiImage:image).resizable().scaledToFill()}
            else {Image("Profile"+(["cat","bear","fox","owl"].contains(preset) ? preset.capitalized:"Cat")).resizable().scaledToFill()}
        }.frame(width:size,height:size).clipShape(Circle()).aspectRatio(1,contentMode:.fit).accessibilityHidden(true)
            .task(id:encoded) {
                guard encoded.count<=3_000_000,let data=Data(base64Encoded:encoded) else {image=nil;return}
                image=await Task.detached(priority:.userInitiated) {AvatarImage.thumbnail(data)}.value
            }
    }
}

enum AvatarImage {
    static func thumbnail(_ data:Data) -> UIImage? {
        guard data.count<=8*1024*1024,let source=CGImageSourceCreateWithData(data as CFData,nil),
              let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:512] as CFDictionary) else {return nil}
        return UIImage(cgImage:cg)
    }
    @MainActor static func squarePNG(_ image:UIImage) -> Data? {
        let format=UIGraphicsImageRendererFormat();format.scale=1
        return UIGraphicsImageRenderer(size:CGSize(width:512,height:512),format:format).pngData { _ in
            let scale=max(512/image.size.width,512/image.size.height)
            let size=CGSize(width:image.size.width*scale,height:image.size.height*scale)
            image.draw(in:CGRect(x:(512-size.width)/2,y:(512-size.height)/2,width:size.width,height:size.height))
        }
    }
}

struct ProfileView:View {
    @EnvironmentObject var store:AppStore
    @State private var photo:PhotosPickerItem?
    @State private var loading=false
    @State private var selectionID=UUID()
    let choices=[("cat","小猫"),("bear","小熊"),("fox","狐狸"),("owl","猫头鹰")]
    var body:some View {
        Form {
            Section {HStack {Spacer();ProfilePortrait(size:96);Spacer()}.padding(.vertical,18)}
            Section("选择头像") {
                HStack(spacing:0) {ForEach(choices,id:\.0) {id,title in
                    Button {selectionID=UUID();Task {await store.setting("profileAvatar",.string(id))}} label:{
                        VStack(spacing:8) {
                            Image("Profile"+id.capitalized).resizable().scaledToFill().frame(width:52,height:52).clipShape(Circle())
                                .overlay {Circle().strokeBorder(store.current.settings.text("profileAvatar",fallback:"cat")==id ? Theme.accent:.clear,lineWidth:3)}
                            Text(title).font(.caption).foregroundStyle(.primary)
                        }.frame(maxWidth:.infinity)
                    }.buttonStyle(.plain).accessibilityLabel("使用"+title+"头像")
                }}.padding(.vertical,8)
            }
            Section {
                PhotosPicker(selection:$photo,matching:.images,photoLibrary:.shared()) {Label(loading ? "正在处理照片…":"从相册选择",systemImage:"photo")}.disabled(loading || store.busy)
                if store.current.settings.text("profileAvatar") != "custom",!store.current.settings.text("profilePng").isEmpty {Button("使用上次的照片") {selectionID=UUID();Task {await store.setting("profileAvatar",.string("custom"))}}}
            } footer:{Text("头像保存在本机加密资料库中。")}
        }.navigationTitle("个人头像").navigationBarTitleDisplayMode(.inline)
            .onChange(of:photo) {_,item in
                guard let item else {return};let token=UUID(),epoch=store.epoch;selectionID=token;loading=true
                Task {defer {loading=false};do {
                    guard let data=try await item.loadTransferable(type:Data.self),data.count<=8*1024*1024,
                          let image=await Task.detached(priority:.userInitiated,operation:{AvatarImage.thumbnail(data)}).value,
                          let png=AvatarImage.squarePNG(image) else {throw AppError.message("照片无法读取，请选择 8 MB 以内的有效图片")}
                    guard selectionID==token,epoch==store.epoch else {return}
                    await store.commit {var settings=$0.settings;settings.set("profileAvatar","custom");settings.set("profilePng",png.base64EncodedString());$0.settings=settings}
                }catch {store.present(error)}}
            }
    }
}

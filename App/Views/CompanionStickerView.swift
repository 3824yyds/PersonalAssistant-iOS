import SwiftUI

struct CompanionStickerImage:View {
    let sticker:CompanionSticker
    var size:CGFloat=136
    var body:some View {
        Image(sticker.asset).resizable().scaledToFit().frame(width:size,height:size)
            .accessibilityLabel("表情包，"+sticker.description)
            .accessibilityIdentifier("companion.sticker.image."+sticker.id)
    }
}

struct CompanionStickerPicker:View {
    @ObservedObject var session:CompanionSession
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text("点一张发送给她，输入框里的草稿会保留。").font(.footnote).foregroundStyle(.secondary)
                LazyVGrid(columns:[GridItem(.adaptive(minimum:100))],spacing:20) {
                    ForEach(CompanionSticker.all) {sticker in
                        Button {
                            session.sendSticker(sticker);dismiss()
                        } label:{
                            VStack(spacing:6) {CompanionStickerImage(sticker:sticker,size:90);Text(sticker.title).font(.subheadline)}
                                .frame(maxWidth:.infinity).padding(.vertical,8).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(session.busy)
                            .accessibilityLabel("发送"+sticker.title+"表情包")
                            .accessibilityHint(sticker.meaning)
                            .accessibilityIdentifier("companion.sticker.send."+sticker.id)
                    }
                }
                Text("她知道这套表情包的含义，也会结合上下文理解你发来的 emoji。可以在她的资料中关闭她的自动表情包。").font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }.navigationTitle("表情包").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction) {Button("完成") {dismiss()}}}
    }
}

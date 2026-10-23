import SwiftUI

struct HeaderControls:View {
    @Binding var sheet:RootSheet?
    var body:some View {
        HStack(spacing:20) {
            Button {sheet = .wallet} label:{Image(systemName:"creditcard").font(.system(size:21)).frame(width:28,height:32)}.accessibilityLabel("卡包与资产")
            Button {sheet = .profile} label:{ProfilePortrait(size:30)}.accessibilityLabel("个人详情")
        }.buttonStyle(.plain).padding(.horizontal,12).frame(height:44).appGlass(Capsule(),interactive:true)
    }
}
/// The header has no full-width surface. Scrolling content is clipped below its bounds.
struct PageHeader<Leading:View>:View {
    var title:String
    @Binding var sheet:RootSheet?
    @ViewBuilder var leading:()->Leading
    var body:some View {
        HStack {
            leading().font(.system(size:19)).frame(width:44,height:44).appGlass(Circle(),interactive:true)
            Spacer(minLength:0)
            HeaderControls(sheet:$sheet)
        }.overlay {Text(title).font(.system(size:17,weight:.semibold)).allowsHitTesting(false)}
            .padding(.horizontal,16).padding(.top,4).padding(.bottom,10)
    }
}
struct FloatingSearchField:View {
    @Binding var text:String
    var prompt:String
    var body:some View {
        HStack(spacing:10) {
            Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt,text:$text).font(.system(size:15)).textInputAutocapitalization(.never)
            if !text.isEmpty {Button {text=""} label:{Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary)}.accessibilityLabel("清除搜索")}
        }.padding(.horizontal,15).frame(height:46).appGlass(Capsule())
            .padding(.horizontal,28).padding(.top,8).padding(.bottom,14)
    }
}

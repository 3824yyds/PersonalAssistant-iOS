import SwiftUI
import UIKit

struct MainNavigation:View {
    @Binding var selection:Int
    @Binding var expanded:Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Namespace private var highlight
    @State private var dragging:Int?
    private let tabs=[("笔记","note.text"),("账本","book.closed"),("提醒","bell"),("助理","bubble.left.and.bubble.right")]
    private var active:Int {dragging ?? selection}
    var body:some View {
        HStack(spacing:4) {
            HStack(spacing:0) {
                ForEach(0..<tabs.count,id:\.self) {index in
                    Button {select(index)} label:{
                        VStack(spacing:3) {
                            Image(systemName:tabs[index].1).font(.system(size:19,weight:.medium)).symbolVariant(active==index ? .fill:.none)
                            Text(tabs[index].0).font(.system(size:10,weight:active==index ? .semibold:.medium))
                        }.foregroundStyle(active==index ? Theme.accent:Color.primary.opacity(0.78))
                            .frame(maxWidth:.infinity,minHeight:48)
                            .background {
                                if active==index {Capsule().fill(.primary.opacity(scheme == .dark ? 0.16:0.065))
                                    .overlay {Capsule().strokeBorder(.white.opacity(scheme == .dark ? 0.08:0.5),lineWidth:0.5)}
                                    .matchedGeometryEffect(id:"active",in:highlight)
                                    .scaleEffect(dragging==nil ? 1:1.06)}
                            }.contentShape(Capsule())
                    }.buttonStyle(.plain).accessibilityLabel(tabs[index].0).accessibilityAddTraits(selection==index ? .isSelected:[])
                }
            }.overlay {GeometryReader {proxy in Color.clear.preference(key:NavigationWidth.self,value:proxy.size.width)}}
                .onPreferenceChange(NavigationWidth.self) {width=$0}
                .simultaneousGesture(DragGesture(minimumDistance:8).onChanged {value in
                    guard width>0 else {return}
                    let index=min(3,max(0,Int(value.location.x/(width/4))))
                    if dragging != index {withAnimation(reduced ? nil:Theme.normal) {dragging=index};UISelectionFeedbackGenerator().selectionChanged()}
                }.onEnded {_ in if let index=dragging {select(index)};dragging=nil})
            if selection != 3 {
                Button {withAnimation(reduced ? nil:Theme.normal) {expanded.toggle()};UIImpactFeedbackGenerator(style:.light).impactOccurred()} label:{
                    Image(systemName:"plus").font(.system(size:22,weight:.regular)).rotationEffect(.degrees(expanded ? 45:0))
                        .frame(width:44,height:44).appGlass(Circle(),interactive:true,tinted:true).foregroundStyle(.white)
                }.buttonStyle(.plain).accessibilityLabel(expanded ? "收起快捷操作":"展开快捷操作").padding(.horizontal,8)
            }
        }.padding(4).appGlass(Capsule()).accessibilityIdentifier("main.navigation")
            .padding(.horizontal,12).padding(.bottom,4)
    }
    @State private var width:CGFloat=0
    private func select(_ index:Int) {
        expanded=false
        withAnimation(reduced ? nil:Theme.normal) {selection=index}
    }
}
private struct NavigationWidth:PreferenceKey {
    static let defaultValue:CGFloat=0
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat) {value=nextValue()}
}

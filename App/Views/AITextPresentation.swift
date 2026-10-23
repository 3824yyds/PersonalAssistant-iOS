import SwiftUI
import UIKit

struct SkeletonTextMetrics {
    var bars:[CGRect]
    var lineCount:Int
    var height:CGFloat
}
enum SkeletonTextLayout {
    /// TextKit measures actual wraps and explicit/empty lines at the editor's font and width.
    static func measure(_ text:String,width:CGFloat,font:UIFont,lineSpacing:CGFloat)->SkeletonTextMetrics {
        guard !text.isEmpty,width>0 else {return SkeletonTextMetrics(bars:[],lineCount:0,height:font.lineHeight)}
        let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=lineSpacing
        let storage=NSTextStorage(string:text,attributes:[.font:font,.paragraphStyle:paragraph])
        let manager=NSLayoutManager(),container=NSTextContainer(size:CGSize(width:max(font.pointSize,width),height:.greatestFiniteMagnitude))
        container.lineFragmentPadding=0;manager.addTextContainer(container);storage.addLayoutManager(manager)
        manager.ensureLayout(for:container)
        var bars:[CGRect]=[],count=0
        let height=max(8,min(13,font.pointSize*0.6))
        manager.enumerateLineFragments(forGlyphRange:manager.glyphRange(for:container)) {rect,used,_,_,_ in
            count+=1
            if used.width>0 {bars.append(CGRect(x:used.minX,y:rect.minY+max(0,(font.lineHeight-height)/2),width:min(width,used.width),height:height))}
        }
        if text.hasSuffix("\n") {count+=1}
        return SkeletonTextMetrics(bars:bars,lineCount:count,height:max(font.lineHeight,manager.usedRect(for:container).height+(text.hasSuffix("\n") ? font.lineHeight:0)))
    }
}
struct TextSkeleton:View {
    var text:String
    var font:UIFont=UIFont.systemFont(ofSize:15)
    var lineSpacing:CGFloat=7
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var width:CGFloat=0
    var body:some View {
        let metrics=width>0 ? SkeletonTextLayout.measure(text,width:width,font:font,lineSpacing:lineSpacing):SkeletonTextMetrics(bars:[],lineCount:0,height:font.lineHeight)
        let rows=SkeletonBars(bars:metrics.bars)
        rows.fill(.primary.opacity(scheme == .dark ? 0.16:0.075))
            .overlay {
                if !reduced {TimelineView(.animation(minimumInterval:1.0/24)) {timeline in
                    let phase=timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:1.8)/1.8
                    Rectangle().fill(LinearGradient(colors:[.clear,.white.opacity(scheme == .dark ? 0.12:0.6),.clear],startPoint:.leading,endPoint:.trailing))
                        .frame(width:max(1,width*0.55)).offset(x:width*(phase*1.55-0.775)).frame(maxWidth:.infinity)
                }.mask(rows)}
            }.frame(height:metrics.height).frame(maxWidth:.infinity)
            .background {GeometryReader {proxy in Color.clear.onAppear {width=proxy.size.width}.onChange(of:proxy.size.width) {_,value in if abs(width-value)>0.5 {width=value}}}}
            .allowsHitTesting(false).accessibilityElement(children:.ignore).accessibilityLabel("正在处理，共 \(metrics.lineCount) 行")
    }
}
private struct SkeletonBars:Shape {
    var bars:[CGRect]
    func path(in rect:CGRect)->Path {var path=Path();for bar in bars {path.addRoundedRect(in:bar,cornerSize:CGSize(width:4,height:4))};return path}
}
struct AITextReveal:ViewModifier {
    var active:Bool
    var initial:Bool
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.colorScheme) private var scheme
    @State private var tint=false
    func body(content:Content)->some View {
        content.overlay {
            LinearGradient(colors:scheme == .dark ? [.cyan,.blue.opacity(0.8),.purple.opacity(0.8)]:[Color(red:0.12,green:0.43,blue:0.51),Color(red:0.21,green:0.32,blue:0.56),Color(red:0.48,green:0.25,blue:0.61)],startPoint:.topLeading,endPoint:.bottomTrailing)
                .mask(content).opacity(tint ? 0.95:0).allowsHitTesting(false).accessibilityHidden(true)
        }.task(id:active) {
            guard !reduced else {tint=false;return}
            if active {tint=true}
            else if tint || initial {
                tint=true
                do {try await Task.sleep(nanoseconds:900_000_000);try Task.checkCancellation();withAnimation(Theme.normal) {tint=false}}catch{}
            }
        }.onChange(of:reduced) {_,value in if value {tint=false}}
    }
}

import UIKit
import SwiftUI
import Combine

@MainActor final class KeyboardVisibility: ObservableObject {
    @Published private(set) var visible = false
    private var observers = Set<AnyCancellable>()
    init() {
        NotificationCenter.default.publisher(for:UIResponder.keyboardWillChangeFrameNotification)
            .receive(on:RunLoop.main).sink { [weak self] notification in
                guard let frame=notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {return}
                self?.visible = frame.minY < UIScreen.main.bounds.maxY && frame.height>0
            }.store(in:&observers)
        NotificationCenter.default.publisher(for:UIResponder.keyboardWillHideNotification)
            .receive(on:RunLoop.main).sink { [weak self] _ in self?.visible=false }.store(in:&observers)
    }
}

enum Theme {
    static let accent = Color(red:0.153,green:0.384,blue:0.765)
    static let muted = Color.secondary
    static let page: CGFloat = 16, gap: CGFloat = 12, radius: CGFloat = 18
    static let fast = Animation.easeOut(duration:0.12), normal = Animation.timingCurve(0.2,0,0,1,duration:0.22)
    static let expense = Color(red:0.78,green:0.36,blue:0.08)
    static let income = Color(red:0.05,green:0.49,blue:0.36)
    static let colors: [Color] = [.cyan,accent,.orange,.purple,.pink,.teal,.indigo,.mint]
    static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? .black:Color(white:0.965) }
    static func panel(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(white:0.082):.white }
    static func finance(_ kind: String) -> Color { switch kind { case "income": return income; case "refund":return accent; case "loan_in":return .purple; case "loan_principal":return .pink; default:return expense } }
    static let categories = ["餐饮","交通","购物","生活","住房","医疗","教育","娱乐","旅行","通讯","订阅","其他"]
    static func categoryIcon(_ category:String)->String { ["餐饮":"fork.knife","交通":"car.fill","购物":"bag.fill","生活":"house.fill","住房":"building.2.fill","医疗":"cross.case.fill","教育":"book.fill","娱乐":"gamecontroller.fill","旅行":"airplane","通讯":"phone.fill","订阅":"repeat","工资":"banknote.fill"][category] ?? "square.grid.2x2.fill" }
}

struct Panel<Content: View>: View {
    @Environment(\.colorScheme) var scheme
    @ViewBuilder var content: ()->Content
    var body: some View { VStack(alignment:.leading,spacing:Theme.gap,content:content).padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Theme.panel(scheme),in:RoundedRectangle(cornerRadius:Theme.radius,style:.continuous)) }
}
struct Amount: View {
    var cents: Int64
    var currency: String = ""
    var prominent = false
    var body: some View {
        HStack(alignment:.firstTextBaseline,spacing:4) {
            if !currency.isEmpty { Text(currency).font(.caption).foregroundStyle(.secondary) }
            Text(Money.amount(cents)).font(.system(size:prominent ? 28:16,weight:prominent ? .semibold:.medium,design:.rounded)).monospacedDigit().contentTransition(.numericText())
        }.accessibilityElement(children:.combine)
    }
}
struct EmptyState: View {
    var icon: String
    var title: String
    var subtitle: String
    var body: some View { VStack(spacing:12) { Image(systemName:icon).font(.system(size:32,weight:.light)).foregroundStyle(Theme.accent).frame(width:68,height:68).background(Theme.accent.opacity(0.07),in:Circle()); Text(title).font(.headline); Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }.frame(maxWidth:.infinity).padding(.vertical,42) }
}
/// Native glass for controls; content cards stay solid for reading contrast.
struct AppGlass<S:Shape>:ViewModifier {
    var shape:S
    var interactive=false
    var tinted=false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder func body(content:Content)->some View {
        if #available(iOS 26.0,*),!reduceTransparency {
            content.contentShape(shape).glassEffect(.regular.tint(tinted ? Theme.accent:.clear).interactive(interactive),in:shape).contentShape(shape)
        } else {
            content.background(tinted ? Theme.accent:Theme.panel(scheme),in:shape).contentShape(shape)
        }
    }
}
extension View {
    func appGlass<S:Shape>(_ shape:S,interactive:Bool=false,tinted:Bool=false)->some View {modifier(AppGlass(shape:shape,interactive:interactive,tinted:tinted))}
    func appClearChrome()->some View {modifier(AppClearChrome())}
    func aiText(revealing:Bool=false,initial:Bool=false)->some View {modifier(AITextReveal(active:revealing,initial:initial))}
}
struct AppGlassGroup<Content:View>:View {
    @ViewBuilder var content:()->Content
    @ViewBuilder var body:some View {
        if #available(iOS 26.0,*) {GlassEffectContainer(spacing:12,content:content)} else {content()}
    }
}

/// Suppress the full-width bar surface while retaining each native glass control.
struct AppClearChrome:ViewModifier {
    @ViewBuilder func body(content:Content)->some View {
        if #available(iOS 26.0,*) {
            content.toolbarBackground(.hidden,for:.navigationBar,.bottomBar)
                .scrollEdgeEffectHidden(true,for:.all)
        } else {content.toolbarBackground(.hidden,for:.navigationBar,.bottomBar)}
    }
}

/// Cobalt sky above a softly rolling white cloud bank, clipped to a true circle.
struct AIOrb:View {
    var active=false
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/24,paused:!active || reduced)) {timeline in
            let time=active && !reduced ? timeline.date.timeIntervalSinceReferenceDate*2.4:0
            Canvas {context,size in
                let side=min(size.width,size.height)
                let bounds=CGRect(x:(size.width-side)/2,y:(size.height-side)/2,width:side,height:side)
                context.clip(to:Path(ellipseIn:bounds))
                context.translateBy(x:bounds.minX,y:bounds.minY)
                context.fill(Path(CGRect(x:0,y:0,width:side,height:side)),with:.linearGradient(
                    Gradient(stops:[.init(color:Color(red:0.24,green:0.43,blue:0.93),location:0),.init(color:Color(red:0.31,green:0.49,blue:0.96),location:0.43),.init(color:Color(red:0.70,green:0.75,blue:0.95),location:1)]),
                    startPoint:.zero,endPoint:CGPoint(x:side*0.25,y:side)))
                var haze=context;haze.addFilter(.blur(radius:side*0.065))
                // A continuous bank, with small independent billows instead of rotating blobs.
                for layer in 0..<3 {
                    var cloud=Path()
                    let drift=CGFloat(sin(time*0.32+Double(layer)*0.9))*0.035
                    let base=CGFloat(0.62+Double(layer)*0.075)+drift
                    cloud.move(to:CGPoint(x:-side*0.15,y:side*base))
                    for step in 0...48 {
                        let x=CGFloat(step)/48*1.3-0.15
                        let wave=sin(Double(x)*7.5+time*0.26+Double(layer)*0.7)*0.053
                            + sin(Double(x)*17-time*0.19+Double(layer))*0.018
                        cloud.addLine(to:CGPoint(x:side*x,y:side*(base+CGFloat(wave))))
                    }
                    cloud.addLine(to:CGPoint(x:side*1.15,y:side*1.2))
                    cloud.addLine(to:CGPoint(x:-side*0.15,y:side*1.2));cloud.closeSubpath()
                    haze.fill(cloud,with:.linearGradient(Gradient(colors:[.white.opacity(layer==0 ? 0.64:0.48),Color(red:0.75,green:0.79,blue:0.97).opacity(0.24)]),startPoint:CGPoint(x:0,y:side*base),endPoint:CGPoint(x:0,y:side*1.1)))
                }
                // Soft illumination along the white cloud edge.
                var light=context;light.addFilter(.blur(radius:side*0.085))
                let shift=CGFloat(sin(time*0.24))*side*0.10
                light.fill(Path(ellipseIn:CGRect(x:side*0.03+shift,y:side*0.47,width:side*0.65,height:side*0.25)),with:.color(.white.opacity(0.42)))
            }.clipShape(Circle())
        }.accessibilityElement(children:.ignore).accessibilityLabel("智能助理")
    }
}
struct ProcessingBar: View {
    var label:String
    var body:some View {
        HStack(spacing:8) {AIOrb(active:true).frame(width:18,height:18);Text(label).font(.caption).foregroundStyle(.secondary);Spacer()}.padding(10)
    }
}
struct AccountPreset: Codable, Identifiable {
    var name: String, type: String, currency: String, region: String
    var id: String { name }
}
struct CardArtwork: Codable, Identifiable { var id:String, bank:String, title:String, kind:String, network:String, source:String }
enum Artwork {
    static let accounts: [AccountPreset] = load("AccountPresets")
    static let cards: [CardArtwork] = load("CardArtwork")
    static func issuer(account:Item,card:Item?)->String {
        bank(account.text("name")) ?? bank(card?.text("institution") ?? "") ?? ((card?.text("institution").isEmpty==false) ? card!.text("institution"):account.text("name"))
    }
    static func cardArtwork(account:Item,card:Item?)->CardArtwork? {
        let issuer=issuer(account:account,card:card),design=card?.text("design") ?? ""
        if design=="minimal" {return nil}
        if let chosen=cards.first(where:{$0.id==design && $0.bank==issuer && $0.kind==account.text("type")}) {return chosen}
        return cards.first {$0.bank==issuer && $0.kind==account.text("type") && $0.network==(card?.text("network") ?? "unionpay")}
    }
    static func cardColors(issuer:String,credit:Bool)->[Color] {
        if issuer.range(of:"汇丰|HSBC|工商|中国银行|招商|中信|华夏|民生",options:[.regularExpression,.caseInsensitive]) != nil {return [Color(red:0.48,green:0.04,blue:0.10),Color(red:0.82,green:0.16,blue:0.20)]}
        if issuer.range(of:"农业|邮政|渣打|恒生|TD Bank|Standard",options:[.regularExpression,.caseInsensitive]) != nil {return [Color(red:0.02,green:0.27,blue:0.23),Color(red:0.06,green:0.51,blue:0.40)]}
        return credit ? [Color(red:0.12,green:0.15,blue:0.22),Color(red:0.22,green:0.29,blue:0.39)]:[Color(red:0.12,green:0.28,blue:0.54),Color(red:0.31,green:0.49,blue:0.75)]
    }
    static func bank(_ name:String)->String? {
        let aliases:[String:[String]]=["中国工商银行":["工商银行","工行"],"中国建设银行":["建设银行","建行"],"中国农业银行":["农业银行","农行"],"中国银行":["中行"],"中国邮政储蓄银行":["邮政储蓄银行","邮储银行","邮储"],"中国民生银行":["民生银行"],"招商银行":["招行"],"交通银行":["交行"],"上海浦东发展银行":["浦发银行"],"中国光大银行":["光大银行"]]
        let normalized=name.replacingOccurrences(of:" ",with:"")
        for (bank,short) in aliases where ([bank]+short).contains(where:{normalized.contains($0)}) {return bank}
        return accounts.first {$0.type=="bank" && $0.name==name}?.name
    }
    static func load<T: Decodable>(_ name: String) -> T where T: ExpressibleByArrayLiteral {
        guard let url = Bundle.main.url(forResource:name,withExtension:"json"), let data = try? Data(contentsOf:url), let value = try? JSONDecoder().decode(T.self,from:data) else { return [] }; return value
    }
    static func index(_ name:String,_ type:String)->Int {
        let canonical=bank(name) ?? name
        if let i = accounts.firstIndex(where:{$0.name == canonical}) { return i }
        if let match = accounts.enumerated().filter({$0.offset>=3 && (name.contains($0.element.name) || $0.element.name.contains(name))}).max(by:{$0.element.name.count<$1.element.name.count}) { return match.offset }
        return type == "cash" ? 0:type == "credit" ? 2:type == "wallet" ? 98:1
    }
}
struct AccountIcon: View {
    var name: String
    var type: String = "bank"
    var body: some View { Image("Account\(Artwork.index(name,type))").resizable().interpolation(.high).scaledToFit().frame(width:36,height:36).accessibilityHidden(true) }
}

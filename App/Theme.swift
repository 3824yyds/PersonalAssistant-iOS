import UIKit
import SwiftUI

enum Theme {
    static let accent = Color(red:0.153,green:0.384,blue:0.765)
    static let muted = Color.secondary
    static let page: CGFloat = 16, gap: CGFloat = 12, radius: CGFloat = 18
    static let fast = Animation.easeOut(duration:0.12), normal = Animation.timingCurve(0.2,0,0,1,duration:0.22)
    static let expense = Color(red:0.78,green:0.36,blue:0.08)
    static let income = Color(red:0.05,green:0.49,blue:0.36)
    static let colors: [Color] = [.cyan,accent,.orange,.purple,.pink,.teal,.indigo,.mint]
    static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? .black:Color(red:0.957,green:0.961,blue:0.957) }
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
struct AIOrb: View {
    var active = false
    @Environment(\.accessibilityReduceMotion) var reduced
    @State private var phase = false
    var body: some View {
        Circle().fill(LinearGradient(colors:[Color(red:0.48,green:0.81,blue:1),Theme.accent,.white.opacity(0.85)],startPoint:phase ? .topLeading:.bottomTrailing,endPoint:phase ? .bottomTrailing:.topLeading))
            .overlay { Circle().fill(RadialGradient(colors:[.white.opacity(0.8),.clear],center:.topLeading,startRadius:0,endRadius:30)).padding(3) }
            .scaleEffect(active && phase ? 1.04:1)
            .animation(active && !reduced ? .easeInOut(duration:1.6).repeatForever(autoreverses:true):.default,value:phase)
            .onAppear { phase = active }.onChange(of:active) { _,v in phase = v }
            .accessibilityLabel(active ? "AI 正在处理":"智能助理")
    }
}
struct ProcessingBar: View {
    var label: String
    var body: some View { VStack(alignment:.leading,spacing:8) { HStack { AIOrb(active:true).frame(width:18,height:18); Text(label).font(.caption).foregroundStyle(.secondary); Spacer() }; ProgressView().progressViewStyle(.linear).tint(Theme.accent) }.padding(12).background(Theme.accent.opacity(0.06),in:RoundedRectangle(cornerRadius:12)).clipShape(RoundedRectangle(cornerRadius:12)) }
}
struct AccountPreset: Codable, Identifiable {
    var name: String, type: String, currency: String, region: String
    var id: String { name }
}
struct CardArtwork: Codable, Identifiable { var id:String, bank:String, title:String, kind:String, network:String, source:String }
enum Artwork {
    static let accounts: [AccountPreset] = load("AccountPresets")
    static let cards: [CardArtwork] = load("CardArtwork")
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
struct ToolbarControls: ToolbarContent {
    @Binding var sheet: RootSheet?
    var body: some ToolbarContent {
        ToolbarItemGroup(placement:.topBarTrailing) {
            Button { sheet = .wallet } label: { Image(systemName:"creditcard").font(.system(size:19,weight:.regular)) }.accessibilityLabel("卡包与资产")
            Button { sheet = .profile } label: { Image(systemName:"person.crop.circle").font(.system(size:23,weight:.regular)) }.accessibilityLabel("个人详情")
        }
    }
}

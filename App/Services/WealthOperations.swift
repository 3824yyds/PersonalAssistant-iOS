import Foundation
import CryptoKit

extension Document {
    var wealth:Item {get {Item(wallet.raw["wealth"]?.object ?? [:])} set {var w=wallet;w.raw["wealth"] = .object(newValue.raw);wallet=w}}
    mutating func upsertWealth(_ item:Item,in key:String) {var w=wealth;var values=w.items(key);values.removeAll {$0.id==item.id};values.append(item);w.set(key,items:values);wealth=w}
}
enum WealthOperations {
    static func stableID(_ prefix:String,_ id:String)->String {
        var bytes=Array(Insecure.MD5.hash(data:Data(("personal-assistant/"+prefix+"/"+id).utf8)))
        bytes[6]=(bytes[6]&0x0f)|0x30;bytes[8]=(bytes[8]&0x3f)|0x80
        let hex=bytes.map {String(format:"%02x",$0)}.joined()
        return [String(hex.prefix(8)),String(hex.dropFirst(8).prefix(4)),String(hex.dropFirst(12).prefix(4)),String(hex.dropFirst(16).prefix(4)),String(hex.dropFirst(20))].joined(separator:"-")
    }
    static func subscriptionDue(_ s:Item,in d:Document)->Date {
        guard let first=Clock.date(s.text("firstDue")) else{return Date()}
        let cycle=s.text("cycle",fallback:"monthly"),component:Calendar.Component=cycle=="weekly" ? .weekOfYear:cycle=="yearly" ? .year:.month,step=cycle=="quarterly" ? 3:1
        var index=0
        for n in 0..<6000 {let candidate=Calendar.current.date(byAdding:component,value:n*step,to:first) ?? first;if candidate<=Date() {index=n}else{break}}
        while index<6000 {
            let day=Calendar.current.date(byAdding:component,value:index*step,to:first) ?? first
            if !d.records.contains(where:{$0.id==stableID("subscription",s.id+":"+Clock.day(day))}) {return day};index+=1
        }
        return first
    }
    static func refreshSubscription(_ s:Item,in d:Document)->Document {
        var next=d;let id=stableID("subscription-reminder",s.id);next.records.removeAll {$0.id==id}
        guard s.bool("active",fallback:true),let account=d.accounts.first(where:{$0.id==s.text("accountId")}) else{return next}
        let date=Calendar.current.date(bySettingHour:9,minute:0,second:0,of:subscriptionDue(s,in:d)) ?? Date()
        let alert=Calendar.current.date(byAdding:.day,value:-Int(s.int("leadDays",fallback:3)),to:date) ?? date
        next.records.append(Item(["id":.string(id),"kind":.string("reminder"),"title":.string(s.text("name")+" · 续费或取消"),"body":.string("付款请在订阅管理中确认"),"category":.string(s.text("category",fallback:"订阅")),"currency":.string(account.text("currency",fallback:"CNY")),"account":.string(account.text("name")),"date":.int(Clock.milliseconds),"due":.int(Int64(date.timeIntervalSince1970*1000)),"alertAt":.int(max(1,Int64(alert.timeIntervalSince1970*1000))),"zone":.string(TimeZone.current.identifier)]));return next
    }
    static func paySubscription(_ s:Item,in d:Document)->Document {
        guard let a=d.accounts.first(where:{$0.id==s.text("accountId")}) else{return d}
        var next=d;let due=subscriptionDue(s,in:d),id=stableID("subscription",s.id+":"+Clock.day(due))
        guard !next.records.contains(where:{$0.id==id}) else{return d}
        next.records.append(Item(["id":.string(id),"kind":.string("expense"),"title":.string(s.text("name")),"body":.string("订阅周期 "+Clock.day(due)),"cents":.int(s.int("cents")),"currency":.string(a.text("currency",fallback:"CNY")),"category":.string(s.text("category",fallback:"订阅")),"account":.string(a.text("name")),"date":.int(Clock.milliseconds),"wealthRef":.string("subscription:"+s.id)]))
        return refreshSubscription(s,in:next)
    }
    static func envelope(_ e:Item,in d:Document)->(assigned:Int64,used:Int64,remaining:Int64) {
        let current=Clock.month(),roll=e.bool("rollover",fallback:true)
        let allocations=d.wealth.items("allocations").filter {$0.text("envelopeId")==e.id && (roll ? $0.text("month")<=current:$0.text("month")==current)}
        let start=allocations.map {$0.text("month")}.min() ?? current
        let uses=Dictionary(d.wealth.items("uses").map {($0.text("recordId"),$0.text("envelopeId"))},uniquingKeysWith:{$1})
        let used=d.records.filter {r in let month=Clock.month(r.date);return ["expense","refund"].contains(r.text("kind")) && r.text("currency",fallback:"CNY")==e.text("currency",fallback:"CNY") && r.int("date")<=Clock.milliseconds && month>=start && (roll ? month<=current:month==current) && uses[r.text("kind")=="refund" ? r.text("linkId"):r.id]==e.id}.reduce(Int64(0)) {$0+($1.text("kind")=="refund" ? -$1.int("cents"):$1.int("cents"))}
        let assigned=allocations.reduce(Int64(0)){$0+$1.int("cents")};return(assigned,used,assigned-used)
    }
    static func splitBalances(_ group:Item,in d:Document)->[String:Int64] {
        var result=Dictionary(uniqueKeysWithValues:group.strings("members").map {($0,Int64(0))})
        for s in d.wealth.items("splits") where s.text("groupId")==group.id {result[s.text("payer"),default:0]+=s.int("cents");for share in s.items("shares") {result[share.text("member"),default:0]-=share.int("cents")}}
        for s in d.wealth.items("settlements") where s.text("groupId")==group.id {result[s.text("from"),default:0]+=s.int("cents");result[s.text("to"),default:0]-=s.int("cents")};return result
    }
    static func addSplit(_ entry:Item,group:Item,in d:Document) throws ->Document {
        guard let a=d.accounts.first(where:{$0.id==entry.text("accountId")}),a.text("currency",fallback:"CNY")==group.text("currency",fallback:"CNY") else {throw AppError.message("请选择同币种的本人收付账户")}
        var next=d;next.upsertWealth(entry,in:"splits")
        let own=entry.items("shares").filter {$0.text("member")==group.text("me")}.reduce(Int64(0)) {$0+$1.int("cents")},mine=entry.text("payer")==group.text("me")
        let rows:[(String,String,Int64)]=mine ? [("own","expense",own),("advance","advance_out",entry.int("cents")-own)]:[("own-due","expense",own),("payable","aa_payable",own)]
        for (role,kind,amount) in rows where amount>0 {next.records.append(Item(["id":.string(stableID("split-"+role,entry.id)),"kind":.string(kind),"title":.string(entry.text("title")),"cents":.int(amount),"currency":.string(group.text("currency",fallback:"CNY")),"category":.string(kind=="expense" ? "AA消费":kind=="advance_out" ? "AA代垫":"AA应付"),"account":.string(a.text("name")),"date":.int(entry.int("date")),"wealthRef":.string("split:"+entry.id)]))};return next
    }
    static func settle(_ entry:Item,group:Item,in d:Document) throws ->Document {
        let b=splitBalances(group,in:d),amount=entry.int("cents"),from=entry.text("from"),to=entry.text("to")
        guard from != to,amount>0,amount<=min(-(b[from] ?? 0),b[to] ?? 0) else {throw AppError.message("结算方向或金额超过待结算余额")}
        var next=d;next.upsertWealth(entry,in:"settlements")
        if from==group.text("me") || to==group.text("me") {
            guard let a=d.accounts.first(where:{$0.id==entry.text("accountId")}),a.text("currency",fallback:"CNY")==group.text("currency",fallback:"CNY") else {throw AppError.message("请选择同币种收付账户")}
            next.records.append(Item(["id":.string(stableID("split-settlement",entry.id)),"kind":.string(to==group.text("me") ? "advance_in":"aa_settlement_out"),"title":.string(group.text("name")+" · "+from+" → "+to),"cents":.int(amount),"currency":.string(group.text("currency",fallback:"CNY")),"category":.string("AA结算"),"account":.string(a.text("name")),"date":.int(entry.int("date")),"wealthRef":.string("split:"+entry.id)]))
        };return next
    }
    static func quantity(_ s:String) throws ->Decimal {guard s.range(of:#"^[0-9]{1,12}(\.[0-9]{1,6})?$"#,options:.regularExpression) != nil,let number=Decimal(string:s) else {throw AppError.message("数量与单价最多六位小数")};return number}
    static func cents(_ amount:Decimal)->Int64 {var a=amount,b=Decimal();NSDecimalRound(&b,&a,0,.plain);return NSDecimalNumber(decimal:b).int64Value}
    static func position(_ p:Item,in d:Document) throws ->(quantity:Decimal,cost:Int64,market:Int64,realized:Int64,dividends:Int64) {
        var qty=Decimal(0),cost:Int64=0,realized:Int64=0,dividends:Int64=0
        for t in d.wealth.items("trades").filter({$0.text("assetId")==p.text("assetId")}).sorted(by:{$0.int("date")<$1.int("date")}) {
            let q=try quantity(t.text("quantity",fallback:"0")),gross=t.int("grossCents"),fee=t.int("feeCents")
            switch t.text("side") {
            case "buy":guard q>0 else {throw AppError.message("买入数量应大于零")};qty+=q;cost+=gross+fee
            case "sell":guard q>0,q<=qty else {throw AppError.message("卖出数量超过当时持仓")};let basis=q==qty ? cost:cents(Decimal(cost)*q/qty);qty-=q;cost-=basis;realized+=gross-fee-basis
            default:guard q==0 else{throw AppError.message("分红数量应为零")};dividends+=gross-fee
            }
        }
        let market=cents(qty*(try quantity(p.text("price",fallback:"0")))*100)
        guard market<=Money.maximum,cost<=Money.maximum else {throw AppError.message("持仓金额超出范围")};return(qty,cost,market,realized,dividends)
    }
    static func syncPosition(_ id:String,in d:Document) throws ->Document {
        guard let p=d.wealth.items("positions").first(where:{$0.text("assetId")==id}) else{return d};let result=try position(p,in:d);var next=d;var w=next.wallet;w.set("assets",items:w.items("assets").map {a in var changed=a;if a.id==id {changed.set("cents",result.market);changed.set("valuedAt",p.int("quotedAt"))};return changed});next.wallet=w;return next
    }
    static func trade(_ t:Item,in d:Document) throws ->Document {
        guard let asset=d.wallet.items("assets").first(where:{$0.id==t.text("assetId")}),let a=d.accounts.first(where:{$0.id==t.text("accountId") && !$0.bool("archived") && $0.text("type") != "credit"}),asset.text("currency",fallback:"CNY")==a.text("currency",fallback:"CNY"),t.int("grossCents")>0,t.int("feeCents")>=0 else {throw AppError.message("请核对成交金额、费用和同币种账户")}
        let side=t.text("side"),cash=side=="buy" ? t.int("grossCents")+t.int("feeCents"):t.int("grossCents")-t.int("feeCents")
        guard cash>0,cash<=Money.maximum else{throw AppError.message("交易现金金额无效")}
        var next=d;next.upsertWealth(t,in:"trades")
        next.records.append(Item(["id":.string(stableID("investment-trade",t.id)),"kind":.string(side=="buy" ? "investment_buy":side=="sell" ? "investment_sell":"income"),"title":.string(asset.text("name")+" · "+(side=="buy" ? "买入":side=="sell" ? "卖出":"分红")),"cents":.int(cash),"currency":.string(a.text("currency",fallback:"CNY")),"category":.string(side=="dividend" ? "投资分红":"投资交易"),"account":.string(a.text("name")),"date":.int(t.int("date")),"wealthRef":.string("trade:"+t.id)]))
        return try syncPosition(asset.id,in:next)
    }
}

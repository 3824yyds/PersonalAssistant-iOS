import Foundation

enum Validation {
    static func extra(_ d:Document) throws {
        func require(_ valid:Bool,_ message:String) throws {if !valid {throw AppError.message(message)}}
        func positive(_ amount:Int64,_ zero:Bool=false)->Bool {(zero ? 0:1)...Money.maximum ~= amount}
        let byID=Dictionary(uniqueKeysWithValues:d.accounts.map {($0.id,$0)})
        let transfers=d.root.items("transfers"),adjustments=d.root.items("adjustments")
        try require(transfers.count<=20000 && adjustments.count<=10000,"转账或调整记录过多")
        for t in transfers {try require(UUID(uuidString:t.id) != nil && t.text("from") != t.text("to") && byID[t.text("from")]?.text("currency",fallback:"CNY")==t.text("currency") && byID[t.text("to")]?.text("currency",fallback:"CNY")==t.text("currency") && positive(t.int("cents")) && t.int("date")>0,"转账资料无效")}
        for t in adjustments {try require(byID[t.text("accountId")] != nil && (-Money.maximum...Money.maximum).contains(t.int("cents")) && t.int("date")>0,"余额核对资料无效")}
        for r in d.records {
            try require(Money.labels[r.text("kind")] != nil,"账目类型不支持")
            if r.text("kind")=="reminder" {try require(r.int("due")>0 && r.int("alertAt")>0 && r.int("alertAt")<=r.int("due") && ["none","daily","weekly","monthly","yearly"].contains(r.text("period",fallback:"none")),"提醒时间或周期无效")}
        }
        let budgets=d.root.items("budgets")
        try require(budgets.count<=5000,"预算记录过多")
        for b in budgets {try require(Clock.date(b.text("month")+"-01") != nil && Money.currencies.contains(b.text("currency")) && positive(b.int("cents")),"预算资料无效")}
        let w=d.wallet
        try require(w.items("cards").count<=500 && w.items("assets").count<=500 && w.items("loans").count<=500,"卡片或资产记录过多")
        for c in w.items("cards") {try require(byID[c.text("accountId")] != nil && positive(c.int("limitCents"),true) && positive(c.int("statementCents"),true) && c.int("paidBeforeCents")>=0 && c.int("paidBeforeCents")<=c.int("statementCents") && (0...31).contains(c.int("statementDay")) && (0...31).contains(c.int("repaymentDay")) && (c.text("lastFour").isEmpty || c.text("lastFour").range(of:#"^[0-9]{4}$"#,options:.regularExpression) != nil),"卡片尾号、额度或账单资料无效")}
        for a in w.items("assets") {try require(UUID(uuidString:a.id) != nil && !a.text("name").isEmpty && Money.currencies.contains(a.text("currency",fallback:"CNY")) && positive(a.int("cents"),true),"资产资料无效")}
        for l in w.items("loans") {try require(UUID(uuidString:l.id) != nil && byID[l.text("accountId")] != nil && positive(l.int("receivedCents",fallback:l.int("principalCents"))),"贷款资料无效");_=try Loans.schedule(l)}
        let wealth=Item(w.raw["wealth"]?.object ?? [:])
        for key in ["subscriptions","envelopes","allocations","uses","groups","splits","settlements","positions","trades","quotes"] {try require(wealth.items(key).count<=20000,"财务明细过多")}
        for s in wealth.items("subscriptions") {try require(!s.text("name").isEmpty && byID[s.text("accountId")] != nil && positive(s.int("cents")) && Clock.date(s.text("firstDue")) != nil && ["weekly","monthly","quarterly","yearly"].contains(s.text("cycle",fallback:"monthly")),"订阅资料无效")}
        for a in wealth.items("allocations") {try require((-Money.maximum...Money.maximum).contains(a.int("cents")) && a.int("cents") != 0 && Clock.date(a.text("month")+"-01") != nil,"资金分配资料无效")}
        for g in wealth.items("groups") {let members=g.strings("members");try require((2...30).contains(members.count) && Set(members).count==members.count && members.contains(g.text("me")),"AA成员资料无效")}
        for s in wealth.items("splits") {try require(positive(s.int("cents")) && s.items("shares").count<=30 && s.items("shares").allSatisfy({positive($0.int("cents"),true)}) && s.items("shares").reduce(Int64(0),{$0+$1.int("cents")})==s.int("cents"),"AA份额资料无效")}
        for s in wealth.items("settlements") {try require(positive(s.int("cents")),"AA结算金额无效")}
        for t in wealth.items("trades") {try require(positive(t.int("grossCents")) && positive(t.int("feeCents"),true) && ["buy","sell","dividend"].contains(t.text("side",fallback:"buy")),"投资交易金额无效")}
    }
}

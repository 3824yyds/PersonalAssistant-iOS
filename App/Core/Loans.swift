import Foundation

public struct Installment: Identifiable, Sendable {
    public let id: Int
    public let date: Date
    public let principal: Int64, interest: Int64, fee: Int64
    public var total: Int64 { principal + interest + fee }
}

public enum Loans {
    public static func schedule(_ l: Item) throws -> [Installment] {
        let months = Int(l.int("months",fallback:12)), amount = l.int("principalCents")
        guard (1...480).contains(months), (1...Money.maximum).contains(amount), (0...20000).contains(l.int("annualBps")), let first = Clock.date(l.text("firstDue")), (0...Money.maximum).contains(l.int("monthlyFeeCents")), ["annuity","principal","bullet","flat"].contains(l.text("method",fallback:"annuity")) else { throw AppError.message("请核对本金、期限、日期和年利率") }
        var remaining = amount, result: [Installment] = []
        for period in 1...months {
            let date = Calendar.current.date(byAdding:.month,value:period-1,to:first) ?? first
            let changes = l.items("rateChanges").filter { $0.text("from") <= Clock.day(date) }.sorted { $0.text("from") < $1.text("from") }
            let bps = changes.last?.int("annualBps") ?? l.int("annualBps")
            let r = Decimal(bps) / Decimal(120_000)
            let method = l.text("method",fallback:"annuity")
            let interest = rounded(Decimal(method == "flat" ? amount : remaining)*r)
            let n = months-period+1
            let principal: Int64
            if period == months { principal = remaining }
            else if method == "bullet" { principal = 0 }
            else if method == "principal" || method == "flat" { principal = amount / Int64(months) }
            else if r == 0 { principal = remaining / Int64(n) }
            else { var factor=Decimal(1); for _ in 0..<n { factor *= 1+r }; let payment = rounded(Decimal(remaining)*r*factor/(factor-1)); principal = max(0,min(remaining,payment-interest)) }
            remaining -= principal
            result.append(Installment(id:period,date:date,principal:principal,interest:interest,fee:l.int("monthlyFeeCents")))
        }
        return result
    }
    private static func rounded(_ value:Decimal)->Int64 {var source=value,result=Decimal();NSDecimalRound(&result,&source,0,.plain);return NSDecimalNumber(decimal:result).int64Value}
    public static func annualIRR(received: Int64, start: Date, flows: [(Date,Int64)]) -> Double? {
        guard received > 0, !flows.isEmpty, flows.allSatisfy({ $0.0 > start && $0.1 >= 0 }) else { return nil }
        func npv(_ x: Double) -> Double { flows.reduce(-Double(received)) { total, flow in total + Double(flow.1)*exp(-x*flow.0.timeIntervalSince(start)/(365*86400)) } }
        var lo = -20.0, hi = log(2.0)
        while npv(hi) > 0 && hi < 20 { hi *= 2 }
        guard npv(lo) >= 0, npv(hi) <= 0 else { return nil }
        for _ in 0..<100 { let mid = (lo+hi)/2; if npv(mid)>0 { lo = mid } else { hi = mid } }
        return expm1((lo+hi)/2)*100
    }
    public static func risk(_ l: Item) -> String {
        var text = "费用应以实际到账、每期实际支付和还款日期计算综合年化成本，不能只看日息或月费率。\n\n"
        if l.text("lenderType") == "private" {
            text += "民间借贷司法保护上限通常依《最高人民法院关于审理民间借贷案件适用法律若干问题的规定》第25条，以合同成立时一年期贷款市场报价利率（LPR）的四倍确定。该标准不直接套用于受监管金融机构贷款。\n\n"
            let lpr = l.int("lprBps")
            if lpr > 0 { text += "你填写的合同期一年期 LPR 为 \(Double(lpr)/100)%，四倍为 \(Double(lpr)*4/100)%。应核实发布日期、合同成立日及费用性质。\n\n" }
            else { text += "尚未提供合同成立时一年期 LPR，不能计算司法保护上限。\n\n" }
        } else { text += "银行、消费金融、汽车金融、小贷等需先核实机构资质、合同、息费披露和监管规则，不能统一用“LPR四倍”认定合法性。\n\n" }
        text += "预扣利息应核对实际交付本金（《民法典》第670条）；利率约定与高利放贷限制见第680条。暴力威胁、骚扰无关第三人、泄露个人信息应保留证据，可向金融监管部门、12378或警方反映，具体渠道以当地最新公告为准。\n\n这是一份风险核对提示，不代替律师对合同、机构性质及最新规定的审查。"
        return text
    }
}

import Foundation

public enum Money {
    public static let maximum: Int64 = 99_999_999_999_999
    public static let currencies = ["CNY","USD","HKD","GBP","MYR","SGD","TWD","JPY","EUR","AUD","CAD","CHF","KRW","INR","THB","IDR","VND","PHP","NZD","AED","SAR","BRL","MXN","ZAR","TRY","SEK","NOK","DKK","PLN","ILS","CZK","HUF","MOP"]
    public static func parse(_ source: String, signed: Bool = false, allowZero: Bool = false) throws -> Int64 {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = signed ? #"^-?[0-9]{1,12}(\.[0-9]{1,2})?$"# : #"^[0-9]{1,12}(\.[0-9]{1,2})?$"#
        guard source.range(of: regex, options: .regularExpression) != nil, let decimal = Decimal(string: source, locale: Locale(identifier: "en_US_POSIX")) else { throw AppError.message("金额最多两位小数，请使用数字填写") }
        let value = NSDecimalNumber(decimal: decimal * 100).int64Value
        guard abs(value) <= maximum, allowZero || value != 0 else { throw AppError.message("请填写有效金额") }
        return value
    }
    public static func amount(_ cents: Int64) -> String { let n = abs(cents); return "\(cents < 0 ? "-" : "")\(n / 100).\(String(format: "%02lld", n % 100))" }
    public static func format(_ cents: Int64, currency: String) -> String { currency + " " + amount(cents) }
    public static func delta(_ r: Item) -> Int64 {
        switch r.text("kind") {
        case "income", "refund", "loan_in", "advance_in", "investment_sell", "aa_payable": return r.int("cents")
        case "expense", "loan_principal", "advance_out", "investment_buy", "aa_settlement_out": return -r.int("cents")
        default: return 0
        }
    }
    public static let labels = ["expense":"支出","income":"收入","refund":"退款","loan_in":"借款到账","loan_principal":"归还本金","advance_out":"代垫付出","advance_in":"收回代垫","investment_buy":"投资买入","investment_sell":"投资卖出","aa_payable":"AA应付确认","aa_settlement_out":"AA结算付款","reminder":"提醒"]
}

public struct Totals: Equatable, Sendable {
    public var income: Int64 = 0, expense: Int64 = 0, refund: Int64 = 0
    public var netExpense: Int64 { expense - refund }
    public var surplus: Int64 { income - expense + refund }
    public init(_ records: [Item]) {
        income = records.filter { $0.text("kind") == "income" }.reduce(0) { $0 + $1.int("cents") }
        expense = records.filter { $0.text("kind") == "expense" }.reduce(0) { $0 + $1.int("cents") }
        refund = records.filter { $0.text("kind") == "refund" }.reduce(0) { $0 + $1.int("cents") }
    }
}

public enum Finance {
    /// Check day-end cash throughout the changed history. Existing bad balances remain editable,
    /// but no operation may create or worsen a cash shortfall. Credit is an explicit debt account.
    public static func validateCashChange(from before:Document,to after:Document) throws {
        let calendar=Calendar.current,now=Clock.milliseconds
        func end(_ milliseconds:Int64)->Int64 {
            let date=Date(timeIntervalSince1970:Double(milliseconds)/1000)
            return Int64((calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:date)) ?? date).timeIntervalSince1970*1000)-1
        }
        func events(_ account:Item,_ document:Document)->[Int64:Int64] {
            let start=account.int("openingDate",fallback:1),currency=account.text("currency",fallback:"CNY")
            guard start<=now else {return [:]}
            var result=[end(start):account.int("openingCents")]
            let originals=Dictionary(document.records.map {($0.id,$0)},uniquingKeysWith:{$1})
            for record in document.records where record.text("currency",fallback:"CNY")==currency && (start...now).contains(record.int("date")) {
                let owner=record.text("kind")=="refund" ? originals[record.text("linkId")] ?? record:record
                if owner.text("account",fallback:"默认账户")==account.text("name") {result[end(record.int("date")),default:0]+=Money.delta(record)}
            }
            for transfer in document.root.items("transfers") where (start...now).contains(transfer.int("date")) && transfer.text("currency")==currency {
                if transfer.text("from")==account.id {result[end(transfer.int("date")),default:0]-=transfer.int("cents")}
                if transfer.text("to")==account.id {result[end(transfer.int("date")),default:0]+=transfer.int("cents")}
            }
            for adjustment in document.root.items("adjustments") where adjustment.text("accountId")==account.id && (start...now).contains(adjustment.int("date")) {result[end(adjustment.int("date")),default:0]+=adjustment.int("cents")}
            return result
        }
        for account in after.accounts where account.text("type") != "credit" {
            let oldEvents=before.accounts.first(where:{$0.id==account.id}).map {events($0,before)} ?? [:]
            let newEvents=events(account,after)
            if oldEvents==newEvents {continue}
            var oldBalance:Int64=0,newBalance:Int64=0
            for day in Set(oldEvents.keys).union(newEvents.keys).sorted() {
                oldBalance+=oldEvents[day] ?? 0;newBalance+=newEvents[day] ?? 0
                guard newBalance>=min(0,oldBalance) else {throw AppError.message(account.text("name")+"在 "+Clock.day(Date(timeIntervalSince1970:Double(day)/1000))+" 的余额不足，不能完成此操作。请核对到账、期初余额或更换付款账户。")}
            }
        }
    }
    public static func origin(_ r: Item, in d: Document) -> Item { r.text("kind") == "refund" ? d.records.first { $0.id == r.text("linkId") } ?? r : r }
    public static func accounts(_ d: Document) -> [Item] {
        var result = d.accounts
        for record in d.records where record.text("kind") != "reminder" {
            let name = origin(record, in: d).text("account", fallback: "默认账户"), currency = record.text("currency", fallback: "CNY")
            if !result.contains(where: { $0.text("name") == name && $0.text("currency", fallback: "CNY") == currency }) {
                // Materialized by the caller before saving; stable IDs from existing accounts remain intact.
                result.append(Item.make(["name":.string(name),"currency":.string(currency),"type":.string("cash"),"openingDate":.int(1)]))
            }
        }
        return result
    }
    public static func balance(_ a: Item, in d: Document, at: Int64 = Clock.milliseconds) -> Int64 {
        let start = a.int("openingDate", fallback: 1), currency = a.text("currency", fallback: "CNY")
        guard at >= start else { return 0 }
        var result = a.int("openingCents")
        for r in d.records where r.text("currency", fallback: "CNY") == currency && (start...at).contains(r.int("date")) && origin(r, in: d).text("account", fallback: "默认账户") == a.text("name") { result += Money.delta(r) }
        for t in d.root.items("transfers") where t.text("currency") == currency && (start...at).contains(t.int("date")) {
            if t.text("from") == a.id { result -= t.int("cents") }; if t.text("to") == a.id { result += t.int("cents") }
        }
        for t in d.root.items("adjustments") where t.text("accountId") == a.id && (start...at).contains(t.int("date")) { result += t.int("cents") }
        return result
    }
    public static func select(_ d: Document, month: Date, currency: String? = nil, account: String? = nil) -> [Item] {
        d.records.filter { r in r.text("kind") != "reminder" && Clock.month(r.date) == Clock.month(month) && (currency == nil || r.text("currency", fallback: "CNY") == currency) && (account == nil || origin(r, in: d).text("account") == account) }.sorted { $0.int("date") > $1.int("date") }
    }
    public static func saveAccount(_ account: Item, card: Item?, in d: Document) throws -> Document {
        var next = d
        if let old = d.accounts.first(where: { $0.id == account.id }) {
            guard old.text("currency", fallback: "CNY") == account.text("currency", fallback: "CNY") else { throw AppError.message("已有账户不能更改币种，请另建账户") }
            next.records = next.records.map { r in var v = r; if r.text("account") == old.text("name") && r.text("currency") == old.text("currency", fallback: "CNY") { v.set("account", account.text("name")) }; return v }
        }
        next.upsert(account, in: "accounts")
        if var c = card { c.set("accountId", account.id); next.upsertWallet(c, in: "cards") }
        next=try next.validated();try validateCashChange(from:d,to:next);return next
    }
    /// Manual posted transactions use the same cash rule as loans and transfers.
    /// Imported future transactions may be corrected without forcing their date to change.
    public static func saveRecord(_ record:Item,in d:Document) throws ->Document {
        let old=d.records.first(where:{$0.id==record.id})
        guard ["expense","income","refund"].contains(record.text("kind")),record.text("loanId").isEmpty,record.text("wealthRef").isEmpty,
              old?.text("loanId").isEmpty ?? true,old?.text("wealthRef").isEmpty ?? true else {throw AppError.message("这笔流水由贷款或资产管理生成，请在对应功能中处理")}
        guard let account=d.accounts.first(where:{$0.text("name")==record.text("account") && $0.text("currency",fallback:"CNY")==record.text("currency",fallback:"CNY")}),!account.bool("archived") else {throw AppError.message("请选择可用的同币种账户")}
        guard record.int("date")<=Clock.milliseconds || old?.int("date")==record.int("date") else {throw AppError.message("尚未发生的收支请先创建提醒，实际发生后再记账")}
        var next=d;next.upsert(record,in:"records");next=try next.validated();try validateCashChange(from:d,to:next);return next
    }
    public static func transfer(_ d: Document, from: String, to: String, cents: Int64, memo: String = "转账") throws -> Document {
        guard from != to, let a = d.accounts.first(where: { $0.id == from }), let b = d.accounts.first(where: { $0.id == to }),
              !a.bool("archived"), !b.bool("archived"), a.text("currency", fallback: "CNY") == b.text("currency", fallback: "CNY"), cents > 0, cents <= Money.maximum else { throw AppError.message("请选择两个可用的同币种账户和有效金额") }
        var next = d
        let t = Item.make(["from":.string(from),"to":.string(to),"cents":.int(cents),"currency":.string(a.text("currency", fallback: "CNY")),"date":.int(Clock.milliseconds),"memo":.string(memo)])
        next.upsert(t, in: "transfers"); try validateCashChange(from:d,to:next); return next
    }
    public static func repay(_ d: Document, credit: Item, from: String, cents: Int64) throws -> Document {
        guard let a = d.accounts.first(where: { $0.id == from }), credit.text("type") == "credit", a.text("type") != "credit", cents <= max(0, -balance(credit, in:d)), balance(a,in:d) >= cents else { throw AppError.message("请核对欠款和还款账户余额") }
        let card = d.wallet.items("cards").first { $0.text("accountId") == credit.id }
        return try transfer(d, from: from, to: credit.id, cents: cents, memo: "信用卡还款 · " + (card?.text("statementMonth") ?? ""))
    }
    public static func paid(_ c: Item, in d: Document) -> Int64 {
        guard !c.text("statementMonth").isEmpty else { return 0 }
        return min(c.int("statementCents"), c.int("paidBeforeCents") + d.root.items("transfers").filter { $0.text("to") == c.text("accountId") && $0.text("memo") == "信用卡还款 · " + c.text("statementMonth") && $0.int("date") <= Clock.milliseconds }.reduce(0) { $0 + $1.int("cents") })
    }
    public static func deleteRecord(_ id: String, in d: Document) throws -> Document {
        guard let record = d.records.first(where: { $0.id == id }) else { return d }
        guard record.text("loanId").isEmpty, record.text("wealthRef").isEmpty else { throw AppError.message("这笔流水由贷款或资产管理生成，请在对应功能中处理") }
        var next = d; next.records.removeAll { $0.id == id || $0.text("linkId") == id };try validateCashChange(from:d,to:next);return next
    }
    public static func report(_ d: Document, month: Date, currency: String) -> String {
        let rs = select(d, month: month, currency: currency), t = Totals(rs)
        let prevDate = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month
        let prev = select(d, month: prevDate, currency: currency), p = Totals(prev)
        let balances = d.accounts.filter { $0.text("currency", fallback: "CNY") == currency }.map { ($0, balance($0,in:d)) }
        let assets = balances.reduce(Int64(0)) { $0 + max(0, $1.1) }, debt = balances.reduce(Int64(0)) { $0 + max(0, -$1.1) }
        let sheet=BalanceSheet(d,currency:currency)
        let categories = Dictionary(grouping: rs.filter { $0.text("kind") == "expense" }, by: { $0.text("category",fallback:"其他") }).map { ($0.key, $0.value.reduce(Int64(0)) { $0 + $1.int("cents") }) }.sorted { $0.1 > $1.1 }
        let budget = d.root.items("budgets").first { $0.text("month") == Clock.month(month) && $0.text("currency") == currency && $0.text("category").isEmpty }
        var s = "# \(Clock.month(month)) 月度财务报告\n\n币种：\(currency) · 仅依据已记录数据\n\n| 指标 | 金额 |\n|---|---:|\n| 收入 | \(Money.amount(t.income)) |\n| 支出 | \(Money.amount(t.expense)) |\n| 退款 | \(Money.amount(t.refund)) |\n| 结余 | \(Money.amount(t.surplus)) |\n| 当前账户资产 | \(Money.amount(assets)) |\n| 当前账户欠款 | \(Money.amount(debt)) |\n\n"
        if prev.isEmpty { s += "上月没有记录，无法判断环比变化。\n\n" } else { s += "净支出较上月\(t.netExpense >= p.netExpense ? "增加" : "减少") \(Money.amount(abs(t.netExpense-p.netExpense)))。\n\n" }
        s += "## 支出结构\n" + categories.prefix(8).map { "- \($0.0)：\(Money.amount($0.1))" }.joined(separator:"\n")
        s += "\n\n## 本月建议\n"
        if let b = budget { s += "- 总预算 \(Money.amount(b.int("cents")))，\(t.netExpense > b.int("cents") ? "已超支" : "还可安排") \(Money.amount(abs(b.int("cents")-t.netExpense)))。\n" }
        if debt > 0 { s += "- 当前有账户欠款，先核对还款日、最低应还及可用现金，优先防止逾期。\n" }
        if t.surplus < 0 { s += "- 已记录收支出现缺口，先确认工资是否漏记，再缩减非必要支出；不要把未使用信用额度当作收入。\n" }
        if let top = categories.first { s += "- 本月最大支出类别是\(top.0)，可核对其中的固定支出与可调整支出。\n" }
        if t.income > 0 { s += "- 以必要月支出为基准逐步建立 3–6 个月应急金，金额应结合住房、家庭和工作稳定性调整。\n" }
        if rs.isEmpty { s += "- 本期没有流水，请先记录收入和必要支出，再制定预算。\n" }
        s += "\n\n## 当前资产与负债\n| 指标 | 金额 |\n|---|---:|\n| 总资产 | \(Money.amount(sheet.assets)) |\n| 账户欠款 | \(Money.amount(sheet.accountDebt)) |\n| 手动负债 | \(Money.amount(sheet.manualDebt)) |\n| 贷款待还本金 | \(Money.amount(sheet.loanDebt)) |\n| 总负债 | \(Money.amount(sheet.liabilities)) |\n| 净资产 | \(Money.amount(sheet.netWorth)) |\n\n借款到账不计收入，归还本金不计支出；利息和费用计入支出。未到期的预计利息不计入当前本金负债。账户及资产负债为当前值；月报收支为所选月份，各币种分别统计。"
        return s
    }
}

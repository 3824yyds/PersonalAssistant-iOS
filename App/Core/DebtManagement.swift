import Foundation

/// One actual payment, independent of the reference installment it pays toward.
public struct LoanPayment: Identifiable, Sendable {
    public var id: String
    public var period: Int
    public var accountID: String
    public var date: Date
    public var principal: Int64
    public var interest: Int64
    public var fee: Int64
    public var total: Int64 { principal + interest + fee }
    public init(id: String = UUID().uuidString.lowercased(), period: Int, accountID: String, date: Date = Date(), principal: Int64, interest: Int64, fee: Int64) {
        self.id=id; self.period=period; self.accountID=accountID; self.date=date
        self.principal=principal; self.interest=interest; self.fee=fee
    }
}

public struct DebtDue: Sendable {
    public var principal: Int64, interest: Int64, fee: Int64
    public var total: Int64 { principal + interest + fee }
}

extension Loans {
    public static let typeLabels = ["online":"网贷 / 消费贷", "mortgage":"商业房贷", "fund":"公积金贷款", "car":"车贷", "private":"私人借贷", "other":"其他贷款"]
    public static let methodLabels = ["annuity":"等额本息", "principal":"等额本金", "bullet":"先息后本", "lump":"到期一次还本付息", "flat":"按初始本金计息"]

    public static func payments(_ loan: Item, in d: Document) -> [LoanPayment] {
        let rows=d.records.filter { $0.text("loanId")==loan.id && $0.int("loanPeriod") != 0 && $0.text("kind") != "refund" }
        return Dictionary(grouping: rows, by: { $0.text("loanGroupId",fallback:$0.id) }).map { id, group in
            let first=group[0]
            let account=d.accounts.first { $0.text("name")==first.text("account") && $0.text("currency",fallback:"CNY")=="CNY" }
            return LoanPayment(id:id,period:Int(first.int("loanPeriod")),accountID:account?.id ?? "",date:first.date,
                principal:group.filter { $0.text("kind")=="loan_principal" }.reduce(0) { $0+$1.int("cents") },
                interest:group.filter { $0.text("kind")=="expense" && $0.text("category")=="贷款利息" }.reduce(0) { $0+$1.int("cents") },
                fee:group.filter { $0.text("kind")=="expense" && $0.text("category") != "贷款利息" }.reduce(0) { $0+$1.int("cents") })
        }.sorted { $0.date==$1.date ? $0.id<$1.id : $0.date>$1.date }
    }

    public static func openingPrincipalPaid(_ loan:Item) -> Int64 {
        let count=max(0,Int(loan.int("openingPaidPeriods")))
        guard count>0 else {return 0}
        // Opening periods refer to the original contract, not a later replacement plan.
        var original=loan; original.raw.removeValue(forKey:"customSchedule")
        return ((try? schedule(original)) ?? []).prefix(count).reduce(0) { $0+$1.principal }
    }
    public static func outstanding(_ loan: Item, in d: Document, at: Int64 = Clock.milliseconds) -> Int64 {
        if let start=Clock.date(loan.text("baseDate")), Int64(start.timeIntervalSince1970*1000)>at { return 0 }
        let paid=d.records.filter { $0.text("loanId")==loan.id && $0.text("kind")=="loan_principal" && $0.int("date")<=at }.reduce(Int64(0)) { $0+$1.int("cents") }
        return max(0,loan.int("principalCents")-openingPrincipalPaid(loan)-paid)
    }
    public static func due(_ row: Installment, loan: Item, in d: Document) -> DebtDue {
        if row.id<=loan.int("openingPaidPeriods") { return DebtDue(principal:0,interest:0,fee:0) }
        let paid=payments(loan,in:d).filter { $0.period==row.id }
        return DebtDue(principal:max(0,row.principal-paid.reduce(0) { $0+$1.principal }),
                       interest:max(0,row.interest-paid.reduce(0) { $0+$1.interest }),
                       fee:max(0,row.fee-paid.reduce(0) { $0+$1.fee }))
    }
    public static func dues(_ loan:Item,in d:Document)->[Int:DebtDue] {
        var result=Dictionary(uniqueKeysWithValues:((try? schedule(loan)) ?? []).map {($0.id,DebtDue(principal:$0.principal,interest:$0.interest,fee:$0.fee))})
        for record in d.records where record.text("loanId")==loan.id {
            let period=Int(record.int("loanPeriod"))
            guard var due=result[period] else {continue}
            if record.text("kind")=="loan_principal" {due.principal-=record.int("cents")}
            else if record.text("kind")=="expense" {if record.text("category")=="贷款利息" {due.interest-=record.int("cents")}else{due.fee-=record.int("cents")}}
            result[period]=due
        }
        for (period,value) in result {
            result[period]=period<=loan.int("openingPaidPeriods") ? DebtDue(principal:0,interest:0,fee:0):DebtDue(principal:max(0,value.principal),interest:max(0,value.interest),fee:max(0,value.fee))
        }
        return result
    }
    public static func needsPlanReview(_ loan:Item,in d:Document) -> Bool {
        if loan.bool("planNeedsReview") {return true}
        let revision=loan.int("planReviewedAt")
        return d.records.contains { $0.text("loanId")==loan.id && $0.int("loanPeriod")==(-1) && $0.int("date")>revision }
    }
    /// Purely removes an actual transaction and its linked refunds; callers validate the result atomically.
    private static func removing(_ rows:[Item],from d:Document) -> Document {
        let ids=Set(rows.map(\.id));var next=d
        next.records.removeAll { ids.contains($0.id) || ids.contains($0.text("linkId")) }
        return next
    }
    public static func save(_ loan:Item,in d:Document) throws -> Document {
        guard UUID(uuidString:loan.id) != nil, !loan.text("name").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              loan.text("name").count<=100, let account=d.accounts.first(where:{$0.id==loan.text("accountId")}),
              account.text("currency",fallback:"CNY")=="CNY", account.text("type") != "credit", !account.bool("archived"),
              let start=Clock.date(loan.text("baseDate")), Clock.day(start)<=Clock.day(),
              let first=Clock.date(loan.text("firstDue")), first>start,
              loan.int("principalCents")>0, (1...480).contains(loan.int("months")),
              (1...loan.int("principalCents")).contains(loan.int("receivedCents")),
              (0...loan.int("months")).contains(loan.int("openingPaidPeriods")) else { throw AppError.message("请核对贷款名称、日期、到账金额和人民币收付账户") }
        _=try schedule(loan)
        if loan.bool("recordReceipt") && loan.int("openingPaidPeriods")>0 { throw AppError.message("已有还款的旧贷款请仅登记，不要再次记录到账") }
        let paid=payments(loan,in:d)
        guard paid.reduce(Int64(0),{$0+$1.principal})+openingPrincipalPaid(loan)<=loan.int("principalCents"),
              paid.allSatisfy({ $0.period == -1 || ($0.period>loan.int("openingPaidPeriods") && $0.period<=loan.int("months")) }),
              paid.allSatisfy({ Clock.day($0.date)>=Clock.day(start) }) else { throw AppError.message("新合同与已有还款不一致，请先修改或撤销相关还款") }
        for row in try schedule(loan) {
            guard paid.filter({$0.period==row.id}).reduce(Int64(0),{$0+$1.principal})<=row.principal else {throw AppError.message("计划本金小于本期实际已还本金，请先核对还款记录")}
        }
        let receiptRows=d.records.filter { $0.text("loanId")==loan.id && $0.int("loanPeriod")==0 }
        var next=d
        if loan.bool("recordReceipt") {let ids=Set(receiptRows.map(\.id));next.records.removeAll {ids.contains($0.id)}}
        else {next=removing(receiptRows,from:d)}
        next.upsertWallet(loan,in:"loans")
        if loan.bool("recordReceipt") {
            let date=Int64(start.timeIntervalSince1970*1000)
            guard date>=account.int("openingDate",fallback:1) else { throw AppError.message("到账日早于账户期初日期，请核对账户期初余额") }
            let group=receiptRows.first?.text("loanGroupId") ?? UUID().uuidString.lowercased()
            for (kind,category,amount) in [("loan_in","贷款本金",loan.int("principalCents")),("expense","贷款费用",loan.int("principalCents")-loan.int("receivedCents"))] where amount>0 {
                var record=receiptRows.first {$0.text("kind")==kind && $0.text("category")==category} ?? Item.make()
                for (key,value) in ["kind":JSONValue.string(kind),"title":.string(loan.text("name")+" · "+category),"category":.string(category),"cents":.int(amount),"currency":.string("CNY"),"account":.string(account.text("name")),"date":.int(date),"loanId":.string(loan.id),"loanPeriod":.int(0),"loanGroupId":.string(group)] {record.raw[key]=value}
                next.records.append(record)
            }
        }
        try Finance.validateCashChange(from:d,to:next)
        return try next.validated()
    }
    public static func savePayment(_ payment:LoanPayment,loanID:String,in d:Document) throws -> Document {
        guard let loan=d.wallet.items("loans").first(where:{$0.id==loanID}), !loan.bool("archived"),
              UUID(uuidString:payment.id) != nil, let account=d.accounts.first(where:{$0.id==payment.accountID}),
              !account.bool("archived"), account.text("type") != "credit", account.text("currency",fallback:"CNY")=="CNY",
              [payment.principal,payment.interest,payment.fee].allSatisfy({(0...Money.maximum).contains($0)}),
              (1...Money.maximum).contains(payment.total), Clock.day(payment.date)<=Clock.day(),
              Clock.day(payment.date)>=loan.text("baseDate"),
              Int64(payment.date.timeIntervalSince1970*1000)>=account.int("openingDate",fallback:1),
              payment.period == -1 || (payment.period>loan.int("openingPaidPeriods") && payment.period<=loan.int("months")) else { throw AppError.message("请核对还款金额、期次、实际日期和可用的人民币付款账户") }
        let old=d.records.filter { $0.text("loanId")==loanID && $0.int("loanPeriod") != 0 && $0.text("loanGroupId",fallback:$0.id)==payment.id }
        var next=removing(old,from:d)
        let remaining=outstanding(loan,in:next)
        guard payment.principal<=remaining else { throw AppError.message("归还本金超过待还本金 "+Money.amount(remaining)) }
        if payment.period>0, let row=try schedule(loan).first(where:{$0.id==payment.period}) {
            let left=due(row,loan:loan,in:next)
            guard payment.principal<=left.principal else { throw AppError.message("本金超过本期计划，请选择提前还本或先核对还款计划") }
            guard left.total>0 else { throw AppError.message("本期已还清；额外本金请使用提前还本") }
        }
        for (kind,category,amount) in [("loan_principal","贷款本金",payment.principal),("expense","贷款利息",payment.interest),("expense","贷款费用",payment.fee)] where amount>0 {
            let label=payment.period == -1 ? "提前还本":"第\(payment.period)期"
            next.records.append(Item.make(["kind":.string(kind),"title":.string(loan.text("name")+" · "+label+" · "+category),"category":.string(category),"cents":.int(amount),"currency":.string("CNY"),"account":.string(account.text("name")),"date":.int(Int64(payment.date.timeIntervalSince1970*1000)),"loanId":.string(loanID),"loanPeriod":.int(Int64(payment.period)),"loanGroupId":.string(payment.id)]))
        }
        if payment.period == -1 {var changed=loan;changed.set("planNeedsReview",true);next.upsertWallet(changed,in:"loans")}
        try Finance.validateCashChange(from:d,to:next)
        return try next.validated()
    }
    public static func deletePayment(_ id:String,loanID:String,in d:Document) throws -> Document {
        let rows=d.records.filter { $0.text("loanId")==loanID && $0.int("loanPeriod") != 0 && $0.text("loanGroupId",fallback:$0.id)==id }
        var next=removing(rows,from:d)
        if rows.contains(where:{$0.int("loanPeriod") == -1}),var loan=next.wallet.items("loans").first(where:{$0.id==loanID}) {loan.set("planNeedsReview",true);next.upsertWallet(loan,in:"loans")}
        try Finance.validateCashChange(from:d,to:next)
        return try next.validated()
    }
    public static func delete(_ id:String,in d:Document) throws -> Document {
        var next=removing(d.records.filter {$0.text("loanId")==id},from:d)
        var wallet=next.wallet; wallet.set("loans",items:wallet.items("loans").filter {$0.id != id}); next.wallet=wallet
        try Finance.validateCashChange(from:d,to:next)
        return try next.validated()
    }
    public static func savePlan(_ rows:[Installment],loanID:String,in d:Document) throws -> Document {
        guard var loan=d.wallet.items("loans").first(where:{$0.id==loanID}) else { throw AppError.message("贷款不存在") }
        let original=try schedule(loan)
        guard let first=rows.first,Clock.day(first.date)>loan.text("baseDate") else {throw AppError.message("首期还款日必须晚于借款日")}
        guard rows.count==original.count, rows.enumerated().allSatisfy({$0.element.id==$0.offset+1}) else { throw AppError.message("还款计划期次不完整") }
        for row in rows {
            let paid=payments(loan,in:d).filter {$0.period==row.id}
            guard row.principal>=paid.reduce(0,{$0+$1.principal}),row.interest>=paid.reduce(0,{$0+$1.interest}),row.fee>=paid.reduce(0,{$0+$1.fee}) else { throw AppError.message("计划金额不能小于本期已经记录的还款") }
            if row.id<=loan.int("openingPaidPeriods") {
                let old=original[row.id-1]
                guard row.principal==old.principal,row.interest==old.interest,row.fee==old.fee,row.date==old.date else { throw AppError.message("登记前已还的期次不能改动") }
            }
        }
        let early=payments(loan,in:d).filter {$0.period == -1}.reduce(Int64(0)) {$0+$1.principal}
        guard rows.reduce(Int64(0),{$0+$1.principal})==loan.int("principalCents")-early else { throw AppError.message("计划本金合计应等于登记本金减去已提前归还的本金") }
        loan.set("customSchedule",items:rows.map {Item(["period":.int(Int64($0.id)),"date":.string(Clock.day($0.date)),"principalCents":.int($0.principal),"interestCents":.int($0.interest),"feeCents":.int($0.fee)])})
        loan.set("planReviewedAt",Clock.milliseconds)
        loan.set("planNeedsReview",false)
        _=try schedule(loan)
        var next=d;next.upsertWallet(loan,in:"loans");return try next.validated()
    }
    /// Reminder rows are derived from the debt plan. They never count as repayments or cash flows.
    public static func refreshReminders(_ d:Document) -> Document {
        var next=d
        let existing=d.records.filter {$0.bool("loanReminder")}
        next.records.removeAll {$0.bool("loanReminder")}
        var generated:[Item]=[]
        for loan in d.wallet.items("loans") where !loan.bool("archived") && !loan.bool("remindersPaused") {
            let balance=outstanding(loan,in:d),review=needsPlanReview(loan,in:d)
            let payments=payments(loan,in:d)
            let dues=dues(loan,in:d)
            for row in (try? schedule(loan)) ?? [] {
                guard let remaining=dues[row.id] else {continue}
                guard remaining.total>0 else {continue}
                if balance==0 && (!payments.contains(where:{$0.period==row.id}) || remaining.interest+remaining.fee==0) {continue}
                let date=Calendar.current.date(bySettingHour:9,minute:0,second:0,of:row.date) ?? row.date
                let lead=Calendar.current.date(byAdding:.day,value:-Int(loan.int("reminderLeadDays",fallback:3)),to:date) ?? date
                let account=d.accounts.first {$0.id==loan.text("accountId")}
                var reminder=existing.first {$0.text("linkedLoanId")==loan.id && $0.int("linkedLoanPeriod")==row.id} ?? Item.make()
                reminder.set("kind","reminder");reminder.set("loanReminder",true);reminder.set("linkedLoanId",loan.id);reminder.set("linkedLoanPeriod",Int64(row.id))
                reminder.set("title",loan.text("name")+" · 第\(row.id)期还款")
                reminder.set("body",review ? "提前还款后的计划待核对，请查看贷款方最新账单。":"待还 "+Money.format(remaining.total,currency:"CNY")+"，请核对贷款方账单后在贷款详情登记实际还款。")
                reminder.set("date",reminder.int("date",fallback:Clock.milliseconds));reminder.set("due",Int64(date.timeIntervalSince1970*1000));reminder.set("alertAt",Int64(date.timeIntervalSince1970*1000));reminder.set("leadAt",Int64(lead.timeIntervalSince1970*1000))
                reminder.set("priority",Int64(2));reminder.set("currency","CNY");reminder.set("account",account?.text("name") ?? "");reminder.set("zone",TimeZone.current.identifier);reminder.set("completed",false)
                generated.append(reminder)
            }
        }
        // Keep the earliest deadlines within the vault's record limit. iOS schedules a rolling 60 alerts.
        next.records+=generated.sorted {$0.int("due")<$1.int("due")}.prefix(max(0,20_000-next.records.count))
        return next
    }
}

public struct BalanceSheet: Sendable {
    public var accountAssets:Int64=0, manualAssets:Int64=0, accountDebt:Int64=0, manualDebt:Int64=0, loanDebt:Int64=0
    public var assets:Int64 { accountAssets+manualAssets }
    public var liabilities:Int64 { accountDebt+manualDebt+loanDebt }
    public var netWorth:Int64 { assets-liabilities }
    public init(_ d:Document,currency:String) {
        for account in d.accounts where account.text("currency",fallback:"CNY")==currency {
            let balance=Finance.balance(account,in:d)
            accountAssets+=max(0,balance); accountDebt+=max(0,-balance)
        }
        for asset in d.wallet.items("assets") where asset.text("currency",fallback:"CNY")==currency {
            if asset.text("kind")=="debt" { manualDebt+=asset.int("cents") } else { manualAssets+=asset.int("cents") }
        }
        if currency=="CNY" { loanDebt=d.wallet.items("loans").reduce(0) { $0+Loans.outstanding($1,in:d) } }
    }
}

import SwiftUI
import Charts

struct FinancialReportView:View {
    @EnvironmentObject var store:AppStore
    @State var month=Date()
    @State var currency="CNY"
    @State var cloud=""
    @State var working=false
    @State var task:Task<Void,Never>?
    var body:some View {ScrollView {VStack(alignment:.leading,spacing:16) {
        DatePicker("报告月份",selection:$month,displayedComponents:.date).datePickerStyle(.compact)
        Picker("币种",selection:$currency) {ForEach(Money.currencies,id:\.self) {Text($0).tag($0)}}
        Panel {MarkdownBody(text:Finance.report(store.current,month:month,currency:currency))}
        Panel {Text("近六个月收支").font(.headline);Chart(months,id:\.0) {m in LineMark(x:.value("月份",m.0),y:.value("收入",Double(m.1)/100)).foregroundStyle(Theme.income).symbol(.circle);LineMark(x:.value("月份",m.0),y:.value("净支出",Double(m.2)/100)).foregroundStyle(Theme.expense).symbol(.circle)}.frame(height:160);HStack {Text("收入").foregroundStyle(Theme.income);Text("净支出").foregroundStyle(Theme.expense)}.font(.caption)}
        NavigationLink {ForecastView()} label:{Panel {Label("未来现金流与情景推演",systemImage:"chart.xyaxis.line")}}
        if store.cloudEnabled && store.hasAPIKey {Button("请 AI 深入分析") {analyze()}.buttonStyle(.borderedProminent).disabled(working)}
        if working {ProcessingBar(label:"正在分析财务状况")}
        if !cloud.isEmpty {Panel {MarkdownBody(text:cloud)}}
    }.padding(16)}.navigationTitle("月度财务报告").navigationBarTitleDisplayMode(.inline).onAppear {currency=store.currency}.onDisappear {task?.cancel()}}
    var months:[(String,Int64,Int64)] {(0..<6).reversed().map {offset in let date=Calendar.current.date(byAdding:.month,value:-offset,to:month) ?? month;let rs=Finance.select(store.current,month:date,currency:currency);let t=Totals(rs);return(Clock.month(date),t.income,t.netExpense)}}
    func analyze() {let d=store.current,selectedMonth=month,code=currency,model=store.model,epoch=store.epoch;working=true;task=Task {defer{working=false};do {let text=try await AIService.cloud(messages:[["role":"system","content":"你是专业个人财务规划助理。只根据提供数据分析，区分月度流水与当前余额，输出结论、关键风险、按优先级的行动和下月预算建议；结合地区和用户目标，不编造缺失资料。\n"+AIService.financeContext(d)],["role":"user","content":"请深入分析这份月报：\n"+Finance.report(d,month:selectedMonth,currency:code)]],model:model);try Task.checkCancellation();if store.epoch==epoch {cloud=text}}catch{store.present(error)}}}
}
struct ForecastPoint:Identifiable {var date:Date,base:Int64,scenario:Int64;var id:Date {date}}
struct ForecastView:View {
    @EnvironmentObject var store:AppStore
    @State var currency="CNY"
    @State var purchase=""
    @State var purchaseDate=Date().addingTimeInterval(86400)
    @State var days=31
    var points:[ForecastPoint] {
        let d=store.current,now=Date(),amount=(try? Money.parse(purchase,allowZero:true)) ?? 0
        let start=d.accounts.filter {$0.text("currency",fallback:"CNY")==currency && $0.text("type") != "credit"}.reduce(Int64(0)) {$0+Finance.balance($1,in:d)}
        var current=start,result:[ForecastPoint]=[]
        for day in 0...days {
            let date=Calendar.current.date(byAdding:.day,value:day,to:now) ?? now
            if day>0 {
                for r in d.records where r.text("currency",fallback:"CNY")==currency && Calendar.current.isDate(r.date,inSameDayAs:date) && r.int("date")>Clock.milliseconds {current+=Money.delta(r)}
                if currency=="CNY" {for l in d.wallet.items("loans") {for row in (try? Loans.schedule(l)) ?? [] where Calendar.current.isDate(row.date,inSameDayAs:date) && !d.records.contains(where:{$0.text("loanId")==l.id && $0.int("loanPeriod")==row.id}) {current-=row.total}}}
            }
            result.append(ForecastPoint(date:date,base:current,scenario:current-(Clock.day(date)>=Clock.day(purchaseDate) ? amount:0)))
        }
        return result
    }
    var body:some View {Form {
        Section {Picker("币种",selection:$currency) {ForEach(Money.currencies,id:\.self) {Text($0).tag($0)}};Picker("预测范围",selection:$days) {Text("31天").tag(31);Text("90天").tag(90)}}
        Section("情景推演") {TextField("计划额外支出",text:$purchase).keyboardType(.decimalPad);DatePicker("计划日期",selection:$purchaseDate,in:Date()...,displayedComponents:.date)}
        Section {Chart(points) {p in LineMark(x:.value("日期",p.date),y:.value("基线",Double(p.base)/100)).foregroundStyle(Theme.accent);LineMark(x:.value("日期",p.date),y:.value("情景",Double(p.scenario)/100)).foregroundStyle(Theme.expense);RuleMark(y:.value("零",0)).foregroundStyle(.secondary.opacity(0.3))}.frame(height:200);HStack {Text("基线").foregroundStyle(Theme.accent);Text("情景").foregroundStyle(Theme.expense)}.font(.caption);if let low=points.min(by:{$0.scenario<$1.scenario}) {Text("最低预计现金：\(Money.format(low.scenario,currency:currency)) · \(Clock.day(low.date))").font(.subheadline).foregroundStyle(low.scenario<0 ? Theme.expense:.primary)}}
        Section {Text("预测仅包含已录入的未来流水和贷款计划，尚未录入的工资、日常开支、订阅或信用卡还款不会自动补全。情景推演不写入账本。").font(.caption).foregroundStyle(.secondary)}
    }.navigationTitle("现金流推演").navigationBarTitleDisplayMode(.inline).onAppear {currency=store.currency}}
}

struct LoansView:View {
    @EnvironmentObject var store:AppStore
    @State var adding=false
    var body:some View {List {
        if store.current.wallet.items("loans").isEmpty {EmptyState(icon:"calendar.badge.clock",title:"把还款计划理清楚",subtitle:"支持网贷、车贷、房贷及民间借款")}
        ForEach(store.current.wallet.items("loans")) {l in NavigationLink {LoanDetailView(loanID:l.id)} label:{VStack(alignment:.leading,spacing:7) {Text(l.text("name")).font(.headline);HStack {Text(l.text("lender")).font(.caption).foregroundStyle(.secondary);Spacer();Amount(cents:outstanding(l),currency:"CNY")}}}}
        Button("登记贷款",systemImage:"plus") {adding=true}
    }.navigationTitle("贷款与还款").navigationBarTitleDisplayMode(.inline).sheet(isPresented:$adding) {NavigationStack {LoanEditor()}.environmentObject(store)}}
    func outstanding(_ l:Item)->Int64 {max(0,l.int("principalCents")-store.current.records.filter {$0.text("loanId")==l.id && $0.text("kind")=="loan_principal" && $0.int("date")<=Clock.milliseconds}.reduce(0){$0+$1.int("cents")})}
}
struct LoanEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    @State var name=""
    @State var lender=""
    @State var principal=""
    @State var received=""
    @State var annual=""
    @State var fee="0.00"
    @State var accountID=""
    @State var months=12
    @State var type="online"
    @State var lenderType="unknown"
    @State var method="annuity"
    @State var baseDate=Date()
    @State var firstDue=Date().addingTimeInterval(30*86400)
    @State var recordReceipt=false
    @State var lpr=""
    var body:some View {Form {
        Section("合同") {TextField("贷款名称",text:$name);Picker("贷款类型",selection:$type) {Text("网贷").tag("online");Text("车贷").tag("car");Text("商业房贷").tag("mortgage");Text("公积金贷").tag("fund");Text("民间借款").tag("private");Text("其他").tag("other")};TextField("债权方",text:$lender);Picker("机构性质",selection:$lenderType) {Text("尚未核实").tag("unknown");Text("银行").tag("bank");Text("持牌消费 / 汽车金融").tag("finance");Text("小贷公司").tag("smallloan");Text("个人 / 非金融企业").tag("private")}}
        Section("金额与利率") {TextField("合同本金（CNY）",text:$principal).keyboardType(.decimalPad);TextField("年利率（%）",text:$annual).keyboardType(.decimalPad);TextField("每月固定费用",text:$fee).keyboardType(.decimalPad);Stepper("期限：\(months)个月",value:$months,in:1...480);Picker("还款方式",selection:$method) {Text("等额本息").tag("annuity");Text("等额本金").tag("principal");Text("先息后本").tag("bullet");Text("按初始本金计息").tag("flat")};if lenderType=="private" {TextField("合同期一年期 LPR（%）",text:$lpr).keyboardType(.decimalPad)}}
        Section("账户与日期") {Picker("人民币收付账户",selection:$accountID) {Text("请选择").tag("");ForEach(store.current.accounts.filter {$0.text("currency",fallback:"CNY")=="CNY" && !$0.bool("archived") && $0.text("type") != "credit"}) {Text($0.text("name")).tag($0.id)}};DatePicker("合同 / 登记日",selection:$baseDate,in:...Date(),displayedComponents:.date);DatePicker("首期还款日",selection:$firstDue,displayedComponents:.date);Toggle("同时记录本次借款到账",isOn:$recordReceipt);if recordReceipt {TextField("实际到账金额",text:$received).keyboardType(.decimalPad)}}
    }.navigationTitle("登记贷款").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("保存") {save()}.disabled(store.busy)}}}
    func save() {do {
        guard !name.isEmpty,let account=store.current.accounts.first(where:{$0.id==accountID}) else {throw AppError.message("请填写贷款名称并选择收付账户")}
        let p=try Money.parse(principal),r=recordReceipt ? try Money.parse(received):p,bps=try Money.parse(annual,allowZero:true)
        guard r<=p,bps<=20000,firstDue>baseDate else {throw AppError.message("请核对实际到账、年利率和还款日")}
        var l=Item.make(["name":.string(name),"type":.string(type),"lender":.string(lender),"lenderType":.string(lenderType),"contractDate":.string(Clock.day(baseDate)),"baseDate":.string(Clock.day(baseDate)),"firstDue":.string(Clock.day(firstDue)),"principalCents":.int(p),"receivedCents":.int(r),"recordReceipt":.bool(recordReceipt),"accountId":.string(accountID),"months":.int(Int64(months)),"annualBps":.int(bps),"method":.string(method),"monthlyFeeCents":.int(try Money.parse(fee,allowZero:true))])
        if !lpr.isEmpty {l.set("lprBps",try Money.parse(lpr,allowZero:true))};_=try Loans.schedule(l)
        Task {if await store.commit({d in d.upsertWallet(l,in:"loans");if recordReceipt {let group=UUID().uuidString.lowercased();let date=Int64((Clock.date(Clock.day(baseDate)) ?? baseDate).timeIntervalSince1970*1000);for (kind,cat,cents) in [("loan_in","贷款本金",p),("expense","贷款费用",p-r)] where cents>0 {d.records.append(Item.make(["kind":.string(kind),"title":.string(name+" · "+cat),"category":.string(cat),"cents":.int(cents),"currency":.string("CNY"),"account":.string(account.text("name")),"date":.int(date),"loanId":.string(l.id),"loanPeriod":.int(0),"loanGroupId":.string(group)]))}}}) {dismiss()}}
    }catch {store.present(error)}}
}
struct LoanDetailView:View {
    @EnvironmentObject var store:AppStore
    var loanID:String
    @State var paying:Installment?
    @State var risk=false
    var loan:Item {store.current.wallet.items("loans").first {$0.id==loanID} ?? Item()}
    var plan:[Installment] {(try? Loans.schedule(loan)) ?? []}
    var body:some View {List {
        Section {Amount(cents:loan.int("principalCents"),currency:"CNY",prominent:true);Text("名义年利率 \(Double(loan.int("annualBps"))/100)% · \(loan.int("months"))个月").font(.caption).foregroundStyle(.secondary);if let start=Clock.date(loan.text("baseDate")),let irr=Loans.annualIRR(received:loan.bool("recordReceipt") ? loan.int("receivedCents"):loan.int("principalCents"),start:start,flows:plan.map {($0.date,$0.total)}) {Text(String(format:"综合年化成本（实际日期 IRR）：%.2f%%",irr)).font(.caption)};Button("法律与权益风险核对") {risk=true}}
        Section("还款计划") {ForEach(plan) {p in
            let paid=store.current.records.contains {$0.text("loanId")==loanID && $0.int("loanPeriod")==p.id}
            Button {if !paid {paying=p}} label:{HStack {VStack(alignment:.leading,spacing:5) {Text("第\(p.id)期 · "+Clock.day(p.date)).font(.subheadline);Text("本金 \(Money.amount(p.principal)) · 利息 \(Money.amount(p.interest)) · 费用 \(Money.amount(p.fee))").font(.caption2).foregroundStyle(.secondary)};Spacer();if paid {Image(systemName:"checkmark.circle.fill").foregroundStyle(Theme.income)}else{Amount(cents:p.total)}}}.buttonStyle(.plain)
                .contextMenu {if paid {Button("撤销本期还款",role:.destructive) {Task {await store.commit {$0.records.removeAll {$0.text("loanId")==loanID && $0.int("loanPeriod")==p.id}}}}}}
        }}
    }.navigationTitle(loan.text("name")).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented:$risk) {NavigationStack {ScrollView {Text(Loans.risk(loan)).font(.system(size:14)).lineSpacing(7).padding(20).textSelection(.enabled)}.navigationTitle("风险核对").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.confirmationAction) {Button("完成") {risk=false}}}}}
        .sheet(item:$paying) {p in NavigationStack {LoanPaymentView(loan:loan,installment:p)}.environmentObject(store)}
    }
}
struct LoanPaymentView:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    let loan:Item,installment:Installment
    @State var accountID=""
    @State var principal=""
    @State var interest=""
    @State var fee=""
    @State var date=Date()
    var body:some View {Form {Picker("付款账户",selection:$accountID) {Text("请选择").tag("");ForEach(store.current.accounts.filter {$0.text("currency",fallback:"CNY")=="CNY" && !$0.bool("archived") && $0.text("type") != "credit"}) {Text($0.text("name")).tag($0.id)}};TextField("实际归还本金",text:$principal).keyboardType(.decimalPad);TextField("实际支付利息",text:$interest).keyboardType(.decimalPad);TextField("实际支付费用",text:$fee).keyboardType(.decimalPad);DatePicker("实际支付日期",selection:$date,in:...Date(),displayedComponents:.date);Text("本金减少负债，利息和费用计入支出，均影响付款账户余额。").font(.caption).foregroundStyle(.secondary)}.navigationTitle("记录第\(installment.id)期还款").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("确认") {save()}.disabled(store.busy)}}.onAppear {accountID=loan.text("accountId");principal=Money.amount(installment.principal);interest=Money.amount(installment.interest);fee=Money.amount(installment.fee)}}
    func save() {do {let p=try Money.parse(principal,allowZero:true),i=try Money.parse(interest,allowZero:true),f=try Money.parse(fee,allowZero:true);guard p+i+f>0,let a=store.current.accounts.first(where:{$0.id==accountID}) else {throw AppError.message("请核对还款金额和账户")};let outstanding=loan.int("principalCents")-store.current.records.filter {$0.text("loanId")==loan.id && $0.text("kind")=="loan_principal"}.reduce(0){$0+$1.int("cents")};guard p<=outstanding else {throw AppError.message("归还本金超过待还本金")};let group=UUID().uuidString.lowercased();Task {if await store.commit({d in guard !d.records.contains(where:{$0.text("loanId")==loan.id && $0.int("loanPeriod")==installment.id}) else {throw AppError.message("本期已记录还款")};for (kind,category,cents) in [("loan_principal","贷款本金",p),("expense","贷款利息",i),("expense","贷款费用",f)] where cents>0 {d.records.append(Item.make(["kind":.string(kind),"title":.string(loan.text("name")+" · 第\(installment.id)期 · "+category),"category":.string(category),"cents":.int(cents),"currency":.string("CNY"),"account":.string(a.text("name")),"date":.int(Int64(date.timeIntervalSince1970*1000)),"loanId":.string(loan.id),"loanPeriod":.int(Int64(installment.id)),"loanGroupId":.string(group)]))}}) {dismiss()}}}catch{store.present(error)}}
}

struct WealthToolsView:View {
    var body:some View {List {NavigationLink("订阅与续费",destination:SubscriptionsView());NavigationLink("资金桶",destination:EnvelopesView());NavigationLink("AA 分摊",destination:SplitGroupsView());NavigationLink("投资持仓",destination:InvestmentsView());NavigationLink("财务证据搜索",destination:EvidenceView())}.navigationTitle("财务工具").navigationBarTitleDisplayMode(.inline)}
}
struct EvidenceView:View {
    @EnvironmentObject var store:AppStore
    @State var query=""
    var body:some View {List {
        if !query.isEmpty {Section("账目") {ForEach(store.current.records.filter {($0.text("title")+$0.text("body")+$0.text("category")+$0.text("account")).localizedCaseInsensitiveContains(query)}) {RecordRow(record:$0,document:store.current)}};Section("笔记") {ForEach(store.current.notes.filter {$0.int("deletedAt")==0 && ($0.text("title")+$0.text("body")).localizedCaseInsensitiveContains(query)}) {n in VStack(alignment:.leading,spacing:6) {Text(n.text("title")).font(.headline);Text(n.text("body")).font(.caption).foregroundStyle(.secondary).lineLimit(4)}}}}
    }.searchable(text:$query,prompt:"搜索金额相关资料、账户或关键词").navigationTitle("财务证据").navigationBarTitleDisplayMode(.inline)}
}

struct ExchangeView:View {
    @EnvironmentObject var store:AppStore
    @State var base="HKD"
    @State var quote="CNY"
    @State var amount="100"
    @State var rate:Decimal?
    @State var source=""
    @State var working=false
    @State var task:Task<Void,Never>?
    var body:some View {Form {
        Picker("从",selection:$base) {ForEach(Money.currencies,id:\.self) {Text($0).tag($0)}};Picker("到",selection:$quote) {ForEach(Money.currencies,id:\.self) {Text($0).tag($0)}};TextField("金额",text:$amount).keyboardType(.decimalPad)
        Button {working=true;task=Task {defer{working=false};do {let result=try await RateService.lookup(base:base,quote:quote);rate=result.0;source=result.1}catch{store.present(error)}}} label:{HStack {Text("查询汇率");if working {ProgressView()}}}.disabled(working)
        if let rate,let number=Decimal(string:amount) {Text("≈ "+NSDecimalNumber(decimal:number*rate).rounding(accordingToBehavior:NSDecimalNumberHandler(roundingMode:.plain,scale:2,raiseOnExactness:false,raiseOnOverflow:false,raiseOnUnderflow:false,raiseOnDivideByZero:false)).stringValue+" "+quote).font(.title3.monospacedDigit());Text(source).font(.caption).foregroundStyle(.secondary)}
        Text("公开参考价用于估算，实际成交价以银行为准。查询不发送个人账目。").font(.caption).foregroundStyle(.secondary)
    }.navigationTitle("汇率换算").navigationBarTitleDisplayMode(.inline).onChange(of:base) {_,_ in rate=nil}.onChange(of:quote) {_,_ in rate=nil}.onDisappear {task?.cancel()}}
}

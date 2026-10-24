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
                if currency=="CNY" {for l in d.wallet.items("loans") where !Loans.needsPlanReview(l,in:d) {for row in (try? Loans.schedule(l)) ?? [] where Calendar.current.isDate(row.date,inSameDayAs:date) {let due=Loans.due(row,loan:l,in:d);if Loans.outstanding(l,in:d)>0 {current-=due.total}}}}
            }
            result.append(ForecastPoint(date:date,base:current,scenario:current-(Clock.day(date)>=Clock.day(purchaseDate) ? amount:0)))
        }
        return result
    }
    var body:some View {Form {
        Section {Picker("币种",selection:$currency) {ForEach(Money.currencies,id:\.self) {Text($0).tag($0)}};Picker("预测范围",selection:$days) {Text("31天").tag(31);Text("90天").tag(90)}}
        Section("情景推演") {TextField("计划额外支出",text:$purchase).keyboardType(.decimalPad);DatePicker("计划日期",selection:$purchaseDate,in:Date()...,displayedComponents:.date)}
        Section {Chart(points) {p in LineMark(x:.value("日期",p.date),y:.value("基线",Double(p.base)/100)).foregroundStyle(Theme.accent);LineMark(x:.value("日期",p.date),y:.value("情景",Double(p.scenario)/100)).foregroundStyle(Theme.expense);RuleMark(y:.value("零",0)).foregroundStyle(.secondary.opacity(0.3))}.frame(height:200);HStack {Text("基线").foregroundStyle(Theme.accent);Text("情景").foregroundStyle(Theme.expense)}.font(.caption);if let low=points.min(by:{$0.scenario<$1.scenario}) {Text("最低预计现金：\(Money.format(low.scenario,currency:currency)) · \(Clock.day(low.date))").font(.subheadline).foregroundStyle(low.scenario<0 ? Theme.expense:.primary)}}
        Section {Text("预测仅包含已录入的未来流水和贷款计划，尚未录入的工资、日常开支、订阅或信用卡还款不会自动补全。提前还本后尚未核对的新计划不纳入预测。情景推演不写入账本。").font(.caption).foregroundStyle(.secondary)}
    }.navigationTitle("现金流推演").navigationBarTitleDisplayMode(.inline).onAppear {currency=store.currency}}
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

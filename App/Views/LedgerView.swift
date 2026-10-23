import SwiftUI
import Charts

struct LedgerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    @State var month = Date()
    @State var selectedDay: Date?
    @State var tab = 0
    @State var query = ""
    @State var currency = ""
    @State var account = ""
    @State var kind = ""
    @State var editing: Item?
    @State var creating = false
    @State var filters = false
    @State var datePicker = false
    @State var importing = false
    var records: [Item] { Finance.select(store.current,month:month,currency:currency.isEmpty ? nil:currency,account:account.isEmpty ? nil:account).filter { r in (kind.isEmpty || r.text("kind")==kind) && (query.isEmpty || (r.text("title")+r.text("body")+r.text("category")).localizedCaseInsensitiveContains(query)) } }
    var statsCurrency: String { currency.isEmpty ? store.currency:currency }
    var stats: [Item] { Finance.select(store.current,month:month,currency:statsCurrency,account:account.isEmpty ? nil:account) }
    var body: some View {
        ScrollView {
            LazyVStack(spacing:12) {
                Picker("账本视图",selection:$tab) { Text("流水").tag(0); Text("统计").tag(1); Text("日历").tag(2); Text("预算").tag(3) }.pickerStyle(.segmented)
                HStack {
                    dateButton("chevron.left","上个月",-1)
                    Button { datePicker=true } label: {Text(month.formatted(.dateTime.year().month())).font(.subheadline.weight(.semibold)).frame(maxWidth:.infinity,minHeight:40)}.buttonStyle(.plain)
                    dateButton("chevron.right","下个月",1)
                    Button { filters=true } label:{Image(systemName:"line.3.horizontal.decrease").frame(width:40,height:40)}.accessibilityLabel("筛选账目")
                }
                HStack { Text(tab==0 && currency.isEmpty ? "全部币种":"\(statsCurrency) · \(account.isEmpty ? "全部账户":account)").font(.caption).foregroundStyle(.secondary);Spacer();Menu { currencyMenu } label:{Label("币种",systemImage:"chevron.down").font(.caption)} }
                if tab == 0 {
                    let codes = Set(records.map {$0.text("currency",fallback:"CNY")}).sorted()
                    ForEach(codes.isEmpty ? [statsCurrency]:codes,id:\.self) { code in summary(records.filter {$0.text("currency",fallback:"CNY")==code},currency:code) }
                    HStack { Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("搜索流水",text:$query);if !query.isEmpty {Button {query=""} label:{Image(systemName:"xmark.circle.fill")}} }.padding(11).background(Theme.panel(scheme),in:RoundedRectangle(cornerRadius:12))
                    if records.isEmpty { EmptyState(icon:"book.closed",title:"本月还没有流水",subtitle:"点右下角＋，记录第一笔收支") }
                    ForEach(Array(Dictionary(grouping:records,by:{Clock.day($0.date)}).keys).sorted(by:>),id:\.self) { day in
                        HStack {Text(day).font(.caption.weight(.medium));Spacer()}.foregroundStyle(.secondary).padding(.top,6)
                        ForEach(records.filter {Clock.day($0.date)==day}) { r in Button {editing=r} label:{RecordRow(record:r,document:store.current)}.buttonStyle(.plain).contextMenu { Button("编辑",systemImage:"pencil") {editing=r}; if r.text("kind")=="expense" {Button("记录退款",systemImage:"arrow.uturn.backward") {refund(r)}};Button("删除",systemImage:"trash",role:.destructive) {Task {await store.commit {$0=try Finance.deleteRecord(r.id,in:$0)}}} } }
                    }
                } else if tab == 1 {
                    summary(stats,currency:statsCurrency)
                    CategoryStatistics(records:stats,currency:statsCurrency)
                    Panel {
                        Text("收支趋势").font(.headline)
                        let days = dayTotals()
                        Chart(days,id:\.0) { day in
                            BarMark(x:.value("日期",day.0),y:.value("金额",Double(day.1)/100)).foregroundStyle(Theme.expense).position(by:.value("类型","支出"))
                            BarMark(x:.value("日期",day.0),y:.value("金额",Double(day.2)/100)).foregroundStyle(Theme.income).position(by:.value("类型","收入"))
                        }.frame(height:150).chartLegend(.hidden)
                        HStack {Label("支出",systemImage:"circle.fill").foregroundStyle(Theme.expense);Label("收入",systemImage:"circle.fill").foregroundStyle(Theme.income)}.font(.caption2)
                    }
                } else if tab == 2 {
                    CalendarPanel(month:month,records:stats) { selectedDay=$0 }
                    if let selectedDay { ForEach(stats.filter {Calendar.current.isDate($0.date,inSameDayAs:selectedDay)}) { r in Button {editing=r} label:{RecordRow(record:r,document:store.current)}.buttonStyle(.plain) } }
                } else { BudgetPanel(month:month,currency:statsCurrency,records:stats) }
            }.padding(16)
        }.background {Theme.background(scheme).ignoresSafeArea()}.appClearChrome().navigationTitle("账本").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarLeading) {Menu {
                Button("记一笔",systemImage:"plus") {creating=true}
                NavigationLink("月度报告与预测",destination:FinancialReportView())
                NavigationLink("账户与转账",destination:AccountsView())
                NavigationLink("贷款与还款",destination:LoansView())
                NavigationLink("订阅与资金规划",destination:WealthToolsView())
                NavigationLink("汇率换算",destination:ExchangeView())
                Button("导入 / 导出账单",systemImage:"square.and.arrow.down") {importing=true}
            } label:{Image(systemName:"ellipsis.circle").accessibilityLabel("账本工具")}} }
            .sheet(item:$editing) {r in NavigationStack {RecordEditor(record:r)}.environmentObject(store)}
            .sheet(isPresented:$creating) {NavigationStack {RecordEditor()}.environmentObject(store)}
            .sheet(isPresented:$importing) {NavigationStack {ImportExportView()}.environmentObject(store)}
            .sheet(isPresented:$datePicker) {NavigationStack {DatePicker("选择月份",selection:$month,displayedComponents:.date).datePickerStyle(.graphical).padding().toolbar {ToolbarItem(placement:.confirmationAction) {Button("完成") {datePicker=false}}}}.presentationDetents([.medium,.large])}
            .sheet(isPresented:$filters) {NavigationStack {Form {
                Picker("类型",selection:$kind) {Text("全部").tag("");Text("支出").tag("expense");Text("收入").tag("income");Text("退款").tag("refund")}
                Picker("账户",selection:$account) {Text("全部账户").tag("");ForEach(store.current.accounts) {Text($0.text("name")).tag($0.text("name"))}}
                Picker("币种",selection:$currency) {Text("全部币种").tag("");ForEach(Money.currencies,id:\.self) {Text($0).tag($0)}}
                Button("重置筛选") {kind="";account="";currency=""}
            }.navigationTitle("筛选").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.confirmationAction) {Button("完成") {filters=false}}}}.presentationDetents([.medium])}
    }
    @ViewBuilder var currencyMenu: some View { Button("全部币种") {currency=""};ForEach(Money.currencies,id:\.self) {code in Button(code) {currency=code}} }
    func dateButton(_ icon:String,_ label:String,_ offset:Int)->some View { Button {month=Calendar.current.date(byAdding:.month,value:offset,to:month) ?? month;selectedDay=nil} label:{Image(systemName:icon).font(.caption.weight(.medium)).frame(width:40,height:40).background(Theme.panel(scheme),in:Circle())}.accessibilityLabel(label) }
    func summary(_ rs:[Item],currency:String)->some View {
        let t = Totals(rs)
        return Panel {HStack {Text(currency).font(.caption.weight(.semibold));Spacer();Text("本月结余").font(.caption).foregroundStyle(.secondary)};Amount(cents:t.surplus,prominent:true);HStack {VStack(alignment:.leading,spacing:4) {Text("收入").font(.caption).foregroundStyle(.secondary);Amount(cents:t.income).foregroundStyle(Theme.income)};Spacer();VStack(alignment:.trailing,spacing:4) {Text("净支出").font(.caption).foregroundStyle(.secondary);Amount(cents:t.netExpense).foregroundStyle(Theme.expense)}}}
    }
    func dayTotals()->[(Int,Int64,Int64)] { (1...31).compactMap { day in let rs=stats.filter {Calendar.current.component(.day,from:$0.date)==day};guard !rs.isEmpty else{return nil};let t=Totals(rs);return(day,t.netExpense,t.income) } }
    func refund(_ r:Item) { let remaining=r.int("cents")-store.current.records.filter {$0.text("kind")=="refund" && $0.text("linkId")==r.id}.reduce(0){$0+$1.int("cents")};guard remaining>0 else {store.error="该笔支出已全部退款";return};editing=Item.make(["kind":.string("refund"),"title":.string(String((r.text("title")+"退款").prefix(200))),"cents":.int(remaining),"currency":.string(r.text("currency",fallback:"CNY")),"category":.string(r.text("category")),"account":.string(r.text("account")),"linkId":.string(r.id),"date":.int(Clock.milliseconds)]) }
}

struct RecordRow: View {
    let record: Item, document: Document
    var body: some View {
        let origin=Finance.origin(record,in:document), kind=record.text("kind")
        HStack(spacing:12) {
            Image(systemName:Theme.categoryIcon(origin.text("category"))).font(.system(size:17)).foregroundStyle(Theme.finance(kind)).frame(width:36,height:36).background(Theme.finance(kind).opacity(0.08),in:RoundedRectangle(cornerRadius:12))
            VStack(alignment:.leading,spacing:5) {Text(record.text("title")).font(.system(size:14,weight:.medium)).lineLimit(1);Text(origin.text("category")+" · "+origin.text("account",fallback:"默认账户")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)}
            Spacer(minLength:8)
            VStack(alignment:.trailing,spacing:4) {Amount(cents:Money.delta(record),currency:record.text("currency",fallback:"CNY")).foregroundStyle(Theme.finance(kind));Text(Money.labels[kind] ?? kind).font(.system(size:10)).foregroundStyle(.secondary)}
        }.padding(13).background(RoundedRectangle(cornerRadius:14).fill(Color.primary.opacity(0.025))).contentShape(Rectangle())
    }
}

struct RecordEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    var record: Item?
    @State var title=""
    @State var amount=""
    @State var kind="expense"
    @State var category="餐饮"
    @State var accountID=""
    @State var date=Date()
    @State var memo=""
    @State var deleting=false
    var linked: Bool {!(record?.text("loanId").isEmpty ?? true) || !(record?.text("wealthRef").isEmpty ?? true)}
    var accounts:[Item] {store.current.accounts.filter {!$0.bool("archived")}}
    var body: some View {
        Form {
            Section {
                if kind != "refund" {Picker("类型",selection:$kind) {Text("支出").tag("expense");Text("收入").tag("income")}.pickerStyle(.segmented)}
                HStack {Text(accounts.first {$0.id==accountID}?.text("currency",fallback:"CNY") ?? store.currency).foregroundStyle(.secondary);TextField("0.00",text:$amount).keyboardType(.decimalPad).font(.system(size:30,weight:.semibold,design:.rounded)).monospacedDigit()}
                TextField("这笔钱用在哪里",text:$title)
            }
            Section {
                Picker("账户",selection:$accountID) {Text("请选择").tag("");ForEach(accounts) {a in Text(a.text("name")+" · "+a.text("currency",fallback:"CNY")).tag(a.id)}}.disabled(kind=="refund")
                Picker("分类",selection:$category) {ForEach(Array(Set(Theme.categories+[category,"工资","贷款利息","贷款费用"])).sorted(),id:\.self) {Text($0).tag($0)}}
                DatePicker("日期",selection:$date,displayedComponents:[.date,.hourAndMinute])
                TextField("备注",text:$memo,axis:.vertical).lineLimit(2...5)
            }
            if let record, !linked {Section {Button("删除这笔记录",role:.destructive) {deleting=true}.confirmationDialog("删除这笔记录及关联退款？",isPresented:$deleting,titleVisibility:.visible) {Button("删除",role:.destructive) {Task {if await store.commit({$0=try Finance.deleteRecord(record.id,in:$0)}) {dismiss()}}}}} }
            if linked {Section {Text("该流水由贷款或资产工具维护，请返回对应功能处理，避免账目重复。").font(.caption).foregroundStyle(.secondary)}}
        }.navigationTitle(kind=="refund" ? "记录退款":record==nil ? "记一笔":"编辑记录").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("保存") {save()}.disabled(store.busy || linked)}}
            .onAppear {if let r=record {title=r.text("title");amount=Money.amount(r.int("cents"));kind=r.text("kind");category=r.text("category",fallback:"其他");date=r.date;memo=r.text("body");accountID=accounts.first {$0.text("name")==r.text("account") && $0.text("currency",fallback:"CNY")==r.text("currency",fallback:"CNY")}?.id ?? ""} else {accountID=accounts.first(where:{$0.id==store.current.settings.text("defaultAccount")})?.id ?? accounts.first?.id ?? ""}}
    }
    func save() {
        do {
            let cents=try Money.parse(amount)
            guard let account=accounts.first(where:{$0.id==accountID}) else {throw AppError.message("请先在卡包中新建一个账户")}
            guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw AppError.message("请填写这笔记录的名称")}
            var r=record ?? Item.make();r.set("kind",kind);r.set("title",title.trimmingCharacters(in:.whitespacesAndNewlines));r.set("cents",cents);r.set("currency",account.text("currency",fallback:"CNY"));r.set("account",account.text("name"));r.set("category",category);r.set("date",Int64(date.timeIntervalSince1970*1000));r.set("body",memo)
            Task {if await store.commit({$0.upsert(r,in:"records")}) {dismiss()}}
        } catch {store.present(error)}
    }
}

struct CategoryStatistics: View {
    var records:[Item],currency:String
    @State var income=false
    @State var selected:String?
    var slices:[(String,Int64)] {Dictionary(grouping:records.filter {$0.text("kind")==((income) ? "income":"expense")},by:{$0.text("category",fallback:"其他")}).map {($0.key,$0.value.reduce(Int64(0)){$0+$1.int("cents")})}.sorted {$0.1>$1.1}}
    var body: some View {
        Panel {
            HStack {Text(income ? "收入分类":"支出分类").font(.headline);Spacer();Toggle("收入",isOn:$income).labelsHidden().accessibilityLabel("查看收入分类")}
            if slices.isEmpty {Text("本期没有这类收支").font(.subheadline).foregroundStyle(.secondary).padding(.vertical,22)}
            else {
                ZStack {
                    Chart(Array(slices.enumerated()),id:\.offset) { i,s in SectorMark(angle:.value("金额",s.1),innerRadius:.ratio(0.78),angularInset:1).foregroundStyle(Theme.colors[i%Theme.colors.count]) }.frame(height:190)
                    VStack(spacing:6) {Text(selected ?? (income ? "总收入":"总支出")).font(.caption).foregroundStyle(.secondary);Amount(cents:selected.flatMap {s in slices.first {$0.0==s}?.1} ?? slices.reduce(0){$0+$1.1},prominent:false)}.frame(maxWidth:130)
                }
                ForEach(Array(slices.enumerated()),id:\.offset) {i,s in Button {withAnimation(Theme.fast) {selected=selected==s.0 ? nil:s.0}} label:{HStack {Circle().fill(Theme.colors[i%Theme.colors.count]).frame(width:8,height:8);Text(s.0).font(.subheadline);Text(String(format:"%.1f%%",Double(s.1)*100/Double(max(1,slices.reduce(0){$0+$1.1})))).font(.caption).foregroundStyle(.secondary);Spacer();Amount(cents:s.1)}.padding(.vertical,6)}.buttonStyle(.plain)}
            }
        }.onChange(of:income) {_,_ in selected=nil}
    }
}

struct CalendarPanel: View {
    var month:Date, records:[Item],onSelect:(Date)->Void
    var days:[Date?] {let calendar=Calendar.current;let first=calendar.date(from:calendar.dateComponents([.year,.month],from:month))!;let offset=(calendar.component(.weekday,from:first)+5)%7;let count=calendar.range(of:.day,in:.month,for:first)!.count;return Array(repeating:nil,count:offset)+(0..<count).map {calendar.date(byAdding:.day,value:$0,to:first)}}
    var body:some View {Panel {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:2),count:7),spacing:4) {
            ForEach(["一","二","三","四","五","六","日"],id:\.self) {Text($0).font(.caption2).foregroundStyle(.secondary)}
            ForEach(Array(days.enumerated()),id:\.offset) {_,day in
                if let day {let rs=records.filter {Calendar.current.isDate($0.date,inSameDayAs:day)};Button {onSelect(day)} label:{VStack(spacing:4) {Text("\(Calendar.current.component(.day,from:day))").font(.system(size:13,weight:Calendar.current.isDateInToday(day) ? .bold:.regular));HStack(spacing:2) {if rs.contains(where:{$0.text("kind")=="expense"}) {Circle().fill(Theme.expense).frame(width:4,height:4)};if rs.contains(where:{$0.text("kind")=="income"}) {Circle().fill(Theme.income).frame(width:4,height:4)};if rs.contains(where:{$0.text("kind")=="refund"}) {Circle().fill(Theme.accent).frame(width:4,height:4)}}.frame(height:5)}.frame(maxWidth:.infinity,minHeight:40).background(Calendar.current.isDateInToday(day) ? Theme.accent.opacity(0.08):.clear,in:RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain).accessibilityLabel(Clock.day(day)+"，\(rs.count)笔收支")}else{Color.clear.frame(height:40)}
            }
        }
        HStack {Text("支出").foregroundStyle(Theme.expense);Text("收入").foregroundStyle(Theme.income);Text("退款").foregroundStyle(Theme.accent)}.font(.system(size:10))
    }}
}

struct BudgetPanel: View {
    @EnvironmentObject var store:AppStore
    var month:Date,currency:String,records:[Item]
    @State var adding=false
    @State var category=""
    @State var amount=""
    var budgets:[Item] {store.current.root.items("budgets").filter {$0.text("month")==Clock.month(month) && $0.text("currency")==currency}}
    var body:some View {Panel {
        HStack {Text("月度预算").font(.headline);Spacer();Button("设置") {adding=true}}
        if budgets.isEmpty {Text("为本月花费设一个范围").font(.subheadline).foregroundStyle(.secondary)}
        ForEach(budgets) {b in let selected=records.filter {b.text("category").isEmpty || Finance.origin($0,in:store.current).text("category")==b.text("category")};let used=Totals(selected).netExpense;VStack(alignment:.leading,spacing:8) {HStack {Text(b.text("category").isEmpty ? "总预算":b.text("category")).font(.subheadline);Spacer();Text(Money.amount(used)+" / "+Money.amount(b.int("cents"))).font(.caption).monospacedDigit()};ProgressView(value:Double(max(0,used)),total:Double(max(1,b.int("cents")))).tint(used>b.int("cents") ? Theme.expense:Theme.accent);Text(used>b.int("cents") ? "已超出 "+Money.amount(used-b.int("cents")):"剩余 "+Money.amount(b.int("cents")-used)).font(.caption2).foregroundStyle(used>b.int("cents") ? Theme.expense:.secondary)}.padding(.vertical,6).onTapGesture {category=b.text("category");amount=Money.amount(b.int("cents"));adding=true}}
    }.sheet(isPresented:$adding) {NavigationStack {Form {Picker("分类",selection:$category) {Text("总预算").tag("");ForEach(Theme.categories,id:\.self) {Text($0).tag($0)}};TextField("预算金额",text:$amount).keyboardType(.decimalPad);Text("\(Clock.month(month)) · \(currency)").foregroundStyle(.secondary)}.navigationTitle("预算").toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {adding=false}};ToolbarItem(placement:.confirmationAction) {Button("保存") {do {let cents=try Money.parse(amount);let c=category;Task {if await store.commit({d in var values=d.root.items("budgets");values.removeAll {$0.text("month")==Clock.month(month) && $0.text("currency")==currency && $0.text("category")==c};values.append(Item(["month":.string(Clock.month(month)),"currency":.string(currency),"category":.string(c),"cents":.int(cents)]));d.root.set("budgets",items:values)}) {adding=false}}}catch{store.present(error)}}}}}}}
}

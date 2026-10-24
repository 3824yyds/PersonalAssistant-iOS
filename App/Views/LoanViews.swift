import SwiftUI

struct LoansView:View {
    @EnvironmentObject var store:AppStore
    @State private var adding=false
    @State private var showArchived=false
    var loans:[Item] {store.current.wallet.items("loans").filter {$0.bool("archived")==showArchived}}
    var body:some View {
        List {
            if loans.isEmpty {EmptyState(icon:"calendar.badge.clock",title:"把还款计划理清楚",subtitle:"网贷、房贷、车贷和私人借贷，统一管理")}
            ForEach(loans) {loan in
                NavigationLink {LoanDetailView(loanID:loan.id)} label:{
                    VStack(alignment:.leading,spacing:7) {
                        HStack {Text(loan.text("name")).font(.headline);Spacer();Amount(cents:Loans.outstanding(loan,in:store.current),currency:"CNY")}
                        Text(Loans.typeLabels[loan.text("type")] ?? "贷款").font(.caption).foregroundStyle(.secondary)
                        if Loans.outstanding(loan,in:store.current)==0 {Text("本金已结清").font(.caption).foregroundStyle(Theme.income)}
                    }.padding(.vertical,4)
                }.accessibilityIdentifier("loan.row."+loan.id)
            }
            Button("登记贷款",systemImage:"plus") {adding=true}.accessibilityIdentifier("loan.add")
        }.navigationTitle("贷款与还款").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.topBarTrailing) {Menu {Toggle("查看归档贷款",isOn:$showArchived)} label:{Image(systemName:"ellipsis")}}}
            .sheet(isPresented:$adding) {NavigationStack {LoanEditor()}.environmentObject(store)}
    }
}

struct LoanEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) private var dismiss
    var loan:Item?
    @State private var name=""
    @State private var lender=""
    @State private var principal=""
    @State private var received=""
    @State private var annual="0"
    @State private var fee="0.00"
    @State private var accountID=""
    @State private var lpr=""
    @State private var months=12
    @State private var type="online"
    @State private var lenderType="unknown"
    @State private var method="annuity"
    @State private var openingPeriods=0
    @State private var leadDays=3
    @State private var baseDate=Date()
    @State private var firstDue=Calendar.current.date(byAdding:.month,value:1,to:Date()) ?? Date()
    @State private var recordReceipt=true
    @State private var remindersPaused=false
    @State private var loaded=false
    var accounts:[Item] {store.current.accounts.filter {$0.text("currency",fallback:"CNY")=="CNY" && !$0.bool("archived") && $0.text("type") != "credit"}}
    var body:some View {
        Form {
            Section("合同") {
                TextField("贷款名称",text:$name).accessibilityIdentifier("loan.name")
                Picker("贷款类型",selection:$type) {ForEach(["online","mortgage","fund","car","private","other"],id:\.self) {Text(Loans.typeLabels[$0] ?? $0).tag($0)}}
                TextField("债权方 / 贷款机构",text:$lender)
                Picker("机构性质",selection:$lenderType) {Text("尚未核实").tag("unknown");Text("银行").tag("bank");Text("持牌消费 / 汽车金融").tag("finance");Text("小贷公司").tag("smallloan");Text("个人 / 非金融企业").tag("private")}
            }
            Section {
                TextField("合同本金（CNY）",text:$principal).keyboardType(.decimalPad).accessibilityIdentifier("loan.principal")
                TextField("名义年利率（%）",text:$annual).keyboardType(.decimalPad)
                TextField("每期固定费用",text:$fee).keyboardType(.decimalPad)
                TextField("期限（月，1–480）",value:$months,format:.number).keyboardType(.numberPad)
                Picker("还款方式",selection:$method) {ForEach(["annuity","principal","bullet","lump","flat"],id:\.self) {Text(Loans.methodLabels[$0] ?? $0).tag($0)}}
                if lenderType=="private" {TextField("合同成立时一年期 LPR（%）",text:$lpr).keyboardType(.decimalPad)}
            } header:{Text("金额与利率")} footer:{Text("支持零利率。自动生成的月度计划用于参考；按日计息、浮动利率、宽限期和不规则分期，请在详情中按贷款方账单核对计划。")}
            Section {
                Picker("默认收付账户",selection:$accountID) {Text("请选择").tag("");ForEach(accounts) {Text($0.text("name")).tag($0.id)}}
                DatePicker("合同 / 借款日",selection:$baseDate,in:...Date(),displayedComponents:.date)
                DatePicker("首期还款日",selection:$firstDue,displayedComponents:.date)
                Toggle("同时记录借款到账",isOn:$recordReceipt).accessibilityIdentifier("loan.receipt")
                if recordReceipt {TextField("实际到账（留空按本金）",text:$received).keyboardType(.decimalPad)}
                else {Stepper("登记前已还：\(openingPeriods)期",value:$openingPeriods,in:0...months)}
            } header:{Text("到账与账户")} footer:{Text(recordReceipt ? "借款到账增加账户余额和负债，不计入收入。合同本金与到账的差额记为已扣费用。" : "仅登记现有负债，不增加账户余额。已经计入期初余额或录过到账的旧贷款，请使用此方式，避免重复入账。")}
            Section("自动还款提醒") {
                Toggle("暂停此贷款提醒",isOn:$remindersPaused)
                Stepper("提前 \(leadDays) 天提醒",value:$leadDays,in:0...30)
                Text("到期日当天 09:00 自动提醒，并在提前日期再提醒一次；还款后自动同步。需要允许系统通知。").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle(loan==nil ? "登记贷款":"编辑贷款").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}}
                ToolbarItem(placement:.confirmationAction) {Button("保存") {save()}.disabled(store.busy).accessibilityIdentifier("loan.save")}
            }.onAppear {load()}.onChange(of:type) {_,value in if value=="private" {lenderType="private"};if loan==nil && ["mortgage","fund","car"].contains(value) {recordReceipt=false}}
    }
    private func load() {
        guard !loaded else {return};loaded=true
        guard let loan else {accountID=accounts.first?.id ?? "";return}
        name=loan.text("name");lender=loan.text("lender");principal=Money.amount(loan.int("principalCents"));received=Money.amount(loan.int("receivedCents",fallback:loan.int("principalCents")));annual=Money.amount(loan.int("annualBps"));fee=Money.amount(loan.int("monthlyFeeCents"));accountID=loan.text("accountId");months=Int(loan.int("months",fallback:12));type=loan.text("type",fallback:"online");lenderType=loan.text("lenderType",fallback:"unknown");method=loan.text("method",fallback:"annuity");baseDate=Clock.date(loan.text("baseDate")) ?? Date();firstDue=Clock.date(loan.text("firstDue")) ?? Date();recordReceipt=loan.bool("recordReceipt");openingPeriods=Int(loan.int("openingPaidPeriods"));leadDays=Int(loan.int("reminderLeadDays",fallback:3));remindersPaused=loan.bool("remindersPaused")
        if loan.int("lprBps")>0 {lpr=Money.amount(loan.int("lprBps"))}
    }
    private func save() {
        do {
            var value=loan ?? Item.make()
            value.set("name",name.trimmingCharacters(in:.whitespacesAndNewlines));value.set("lender",lender);value.set("type",type);value.set("lenderType",lenderType)
            let amount=try Money.parse(principal)
            value.set("principalCents",amount);value.set("receivedCents",received.isEmpty ? amount:try Money.parse(received));value.set("annualBps",try Money.parse(annual,allowZero:true));value.set("monthlyFeeCents",try Money.parse(fee,allowZero:true));value.set("months",Int64(months));value.set("method",method);value.set("accountId",accountID);value.set("baseDate",Clock.day(baseDate));value.set("contractDate",Clock.day(baseDate));value.set("firstDue",Clock.day(firstDue));value.set("recordReceipt",recordReceipt);value.set("openingPaidPeriods",Int64(recordReceipt ? 0:openingPeriods));value.set("reminderLeadDays",Int64(leadDays));value.set("remindersPaused",remindersPaused)
            if !lpr.isEmpty {value.set("lprBps",try Money.parse(lpr,allowZero:true))} else {value.raw.removeValue(forKey:"lprBps")}
            if let loan,!loan.items("customSchedule").isEmpty {
                let keys=["principalCents","annualBps","monthlyFeeCents","months","method","firstDue","openingPaidPeriods"]
                if keys.contains(where:{loan.raw[$0] != value.raw[$0]}) {throw AppError.message("已使用核对后的合同计划。请在“核对还款计划”修改各期金额和日期；如需重建合同，先撤销相关还款。")}
            }
            Task {if await store.commit({$0=try Loans.save(value,in:$0)}) {
                if !remindersPaused {if await NotificationService.request() {NotificationService.sync(store.current.records)} else {store.error="贷款已保存并生成还款提醒。系统通知未开启，请到 iOS 设置允许通知。"}}
                dismiss()
            }}
        } catch {store.present(error)}
    }
}

struct LoanDetailView:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) private var dismiss
    let loanID:String
    @State private var editing=false
    @State private var risk=false
    @State private var deleting=false
    @State private var planEditing=false
    @State private var rates=false
    @State private var paying:LoanPayment?
    var loan:Item {store.current.wallet.items("loans").first {$0.id==loanID} ?? Item()}
    var plan:[Installment] {(try? Loans.schedule(loan)) ?? []}
    var remaining:Int64 {Loans.outstanding(loan,in:store.current)}
    var body:some View {
        List {
            Section {
                Text("待还本金").font(.caption).foregroundStyle(.secondary)
                Amount(cents:remaining,currency:"CNY",prominent:true).accessibilityIdentifier("loan.outstanding")
                Text("登记本金 "+Money.amount(loan.int("principalCents"))+" · "+(Loans.typeLabels[loan.text("type")] ?? "贷款")).font(.caption).foregroundStyle(.secondary)
                Text((Loans.methodLabels[loan.text("method",fallback:"annuity")] ?? "合同计划")+" · 名义年利率 "+Money.amount(loan.int("annualBps"))+"%").font(.caption).foregroundStyle(.secondary)
                if let start=Clock.date(loan.text("baseDate")),let irr=Loans.annualIRR(received:loan.int("receivedCents",fallback:loan.int("principalCents")),start:start,flows:plan.filter {$0.total>0}.map {($0.date,$0.total)}+Loans.payments(loan,in:store.current).filter {$0.period == -1}.map {($0.date,$0.total)}) {
                    if !Loans.needsPlanReview(loan,in:store.current) {Text(String(format:"参考综合年化成本：%.2f%%（实际日期 IRR）",irr)).font(.caption)}
                }
                if remaining==0 {Text("本金已结清，请核对是否还有应付息费。").font(.caption).foregroundStyle(Theme.income)}
                if Loans.needsPlanReview(loan,in:store.current) {Text("已记录提前还本，请按贷款方的新账单核对后续计划。原计划不再用于现金流预测，提醒仍按原到期日提示核对。").font(.caption).foregroundStyle(Theme.expense)}
            }
            Section {
                NavigationLink {LoanPaymentsView(loanID:loanID)} label:{Label("还款记录（\(Loans.payments(loan,in:store.current).count)）",systemImage:"list.bullet.rectangle")}.accessibilityIdentifier("loan.history")
                Button("核对还款计划",systemImage:"calendar") {planEditing=true}.accessibilityIdentifier("loan.plan")
                Button("利率调整",systemImage:"percent") {rates=true}
                Button("提前还本",systemImage:"arrow.down.circle") {paying=LoanPayment(period:-1,accountID:loan.text("accountId"),principal:remaining,interest:0,fee:0)}.disabled(remaining==0 || loan.bool("archived")).accessibilityIdentifier("loan.prepay")
            }
            Section {
                ForEach(plan) {row in
                    let due=Loans.due(row,loan:loan,in:store.current)
                    let recorded=Loans.payments(loan,in:store.current).contains {$0.period==row.id}
                    Button {
                        paying=LoanPayment(period:row.id,accountID:loan.text("accountId"),principal:min(due.principal,remaining),interest:due.interest,fee:due.fee)
                    } label:{
                        HStack {
                            VStack(alignment:.leading,spacing:6) {
                                Text("第\(row.id)期 · "+Clock.day(row.date)).font(.subheadline)
                                Text("待还本金 \(Money.amount(due.principal)) · 利息 \(Money.amount(due.interest)) · 费用 \(Money.amount(due.fee))").font(.caption2).foregroundStyle(.secondary)
                                if row.id<=loan.int("openingPaidPeriods") {Text("登记前已还").font(.caption2).foregroundStyle(.secondary)}
                                else if due.total==0 {Text("本期已还").font(.caption2).foregroundStyle(Theme.income)}
                                else if recorded {Text("部分已还").font(.caption2).foregroundStyle(Theme.expense)}
                                else if Clock.day(row.date)<Clock.day() && remaining>0 {Text("已过计划还款日，请核对实际账单").font(.caption2).foregroundStyle(Theme.expense)}
                            }
                            Spacer(minLength:4)
                            if due.total==0 {Image(systemName:"checkmark.circle.fill").foregroundStyle(Theme.income)} else {Amount(cents:due.total)}
                        }
                    }.buttonStyle(.plain).disabled(due.total==0 || loan.bool("archived") || (remaining==0 && !recorded)).accessibilityIdentifier("loan.installment.\(row.id)")
                }
            } header:{Text("还款计划")} footer:{Text("分期金额为合同参考值，付款时填写实际本息和费用。部分还款不会标为全部已还；未来息费不计入当前本金负债。")}
            Section {Button("法律与权益风险核对") {risk=true}}
        }.navigationTitle(loan.text("name")).navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItemGroup(placement:.topBarTrailing) {
                Button("编辑") {editing=true}.accessibilityIdentifier("loan.edit")
                Menu {
                    Button(loan.bool("archived") ? "恢复管理":"归档贷款") {Task {await store.commit {d in guard var value=d.wallet.items("loans").first(where:{$0.id==loanID}) else{return};value.set("archived",!value.bool("archived"));d.upsertWallet(value,in:"loans")}}}
                    Button("删除贷款",role:.destructive) {deleting=true}
                } label:{Image(systemName:"ellipsis")}.accessibilityLabel("贷款操作")
            }}
            .confirmationDialog("删除贷款及其到账、息费和还款流水？",isPresented:$deleting,titleVisibility:.visible) {Button("删除贷款与关联流水",role:.destructive) {Task {if await store.commit({$0=try Loans.delete(loanID,in:$0)}) {dismiss()}}}} message:{Text("账户余额会同步回滚。如果回滚后资金不足，会阻止删除；归档可保留完整账目，未还本金仍计入负债。")}
            .sheet(isPresented:$editing) {NavigationStack {LoanEditor(loan:loan)}.environmentObject(store)}
            .sheet(item:$paying) {payment in NavigationStack {LoanPaymentView(loanID:loanID,payment:payment)}.environmentObject(store)}
            .sheet(isPresented:$planEditing) {NavigationStack {LoanPlanEditor(loanID:loanID)}.environmentObject(store)}
            .sheet(isPresented:$rates) {NavigationStack {LoanRateEditor(loanID:loanID)}.environmentObject(store)}
            .sheet(isPresented:$risk) {NavigationStack {ScrollView {Text(Loans.risk(loan)).font(.system(size:14)).lineSpacing(7).padding(20).textSelection(.enabled)}.navigationTitle("风险核对").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.confirmationAction) {Button("完成") {risk=false}}}}}
    }
}

struct LoanPaymentView:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) private var dismiss
    let loanID:String,payment:LoanPayment
    @State private var accountID=""
    @State private var principal=""
    @State private var interest=""
    @State private var fee=""
    @State private var date=Date()
    @State private var loaded=false
    var body:some View {
        Form {
            Section {
                Picker("付款账户",selection:$accountID) {Text("请选择").tag("");ForEach(store.current.accounts.filter {$0.text("currency",fallback:"CNY")=="CNY" && !$0.bool("archived") && $0.text("type") != "credit"}) {Text($0.text("name")).tag($0.id)}}
                if let account=store.current.accounts.first(where:{$0.id==accountID}) {Text("当前余额 "+Money.format(Finance.balance(account,in:store.current),currency:"CNY")).font(.caption).foregroundStyle(.secondary)}
                TextField("实际归还本金",text:$principal).keyboardType(.decimalPad).accessibilityIdentifier("loan.payment.principal")
                TextField("实际支付利息",text:$interest).keyboardType(.decimalPad).accessibilityIdentifier("loan.payment.interest")
                TextField("实际支付费用 / 违约金",text:$fee).keyboardType(.decimalPad).accessibilityIdentifier("loan.payment.fee")
                DatePicker("实际支付日期",selection:$date,in:...Date(),displayedComponents:.date)
            } footer:{Text("本金只减少负债；利息和费用计入支出。系统校验实际支付日及后续已记账余额，余额不足不能扣款。")}
            if payment.period == -1 {Section {Text("提前还本的利息、违约金按贷款方实际结算填写。完成后请核对后续还款计划，系统不会推断银行采用缩短期限还是减少月供。").font(.caption).foregroundStyle(.secondary)}}
        }.navigationTitle(payment.period == -1 ? "提前还本":"记录第\(payment.period)期还款").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}}
                ToolbarItem(placement:.confirmationAction) {Button("保存") {save()}.disabled(store.busy).accessibilityIdentifier("loan.payment.save")}
            }.onAppear {guard !loaded else {return};loaded=true;accountID=payment.accountID;principal=Money.amount(payment.principal);interest=Money.amount(payment.interest);fee=Money.amount(payment.fee);date=payment.date}
    }
    private func save() {
        do {
            let value=LoanPayment(id:payment.id,period:payment.period,accountID:accountID,date:date,principal:try Money.parse(principal,allowZero:true),interest:try Money.parse(interest,allowZero:true),fee:try Money.parse(fee,allowZero:true))
            Task {if await store.commit({$0=try Loans.savePayment(value,loanID:loanID,in:$0)}) {dismiss()}}
        } catch {store.present(error)}
    }
}

struct LoanPaymentsView:View {
    @EnvironmentObject var store:AppStore
    let loanID:String
    @State private var editing:LoanPayment?
    @State private var deleting:LoanPayment?
    var loan:Item {store.current.wallet.items("loans").first {$0.id==loanID} ?? Item()}
    var body:some View {
        List {
            if Loans.payments(loan,in:store.current).isEmpty {Text("还没有实际还款记录").foregroundStyle(.secondary)}
            ForEach(Loans.payments(loan,in:store.current)) {payment in
                Button {editing=payment} label:{VStack(alignment:.leading,spacing:7) {
                    HStack {Text(payment.period == -1 ? "提前还本":"第\(payment.period)期");Spacer();Amount(cents:payment.total,currency:"CNY")}
                    Text(Clock.day(payment.date)+" · "+(store.current.accounts.first {$0.id==payment.accountID}?.text("name") ?? "原付款账户")).font(.caption).foregroundStyle(.secondary)
                    Text("本金 \(Money.amount(payment.principal)) · 利息 \(Money.amount(payment.interest)) · 费用 \(Money.amount(payment.fee))").font(.caption2).foregroundStyle(.secondary)
                }}.buttonStyle(.plain).accessibilityIdentifier("loan.payment."+payment.id)
                    .swipeActions {Button("撤销",role:.destructive) {deleting=payment}}
                    .contextMenu {Button("编辑还款") {editing=payment};Button("撤销还款",role:.destructive) {deleting=payment}}
            }
        }.navigationTitle("还款记录").navigationBarTitleDisplayMode(.inline)
            .sheet(item:$editing) {payment in NavigationStack {LoanPaymentView(loanID:loanID,payment:payment)}.environmentObject(store)}
            .confirmationDialog("撤销这笔实际还款？",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}}),titleVisibility:.visible) {Button("撤销还款并恢复余额",role:.destructive) {guard let payment=deleting else{return};Task {await store.commit {$0=try Loans.deletePayment(payment.id,loanID:loanID,in:$0)}};deleting=nil}} message:{Text("本金、息费、账户余额和还款提醒会同时恢复。")}
    }
}

private struct PlanDraft:Identifiable {
    var id:Int,date:Date,principal:String,interest:String,fee:String
    init(_ row:Installment) {id=row.id;date=row.date;principal=Money.amount(row.principal);interest=Money.amount(row.interest);fee=Money.amount(row.fee)}
}
struct LoanPlanEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) private var dismiss
    let loanID:String
    @State private var rows:[PlanDraft]=[]
    @State private var loaded=false
    var body:some View {
        Form {
            Section {Text("按贷款方合同或更新后的账单填写每期日期、本金、利息和费用。支持按日计息、宽限期、不规则分期及提前还款后的新计划。此操作不产生实际收付款。").font(.caption).foregroundStyle(.secondary)}
            ForEach($rows) {$row in
                Section("第\(row.id)期") {
                    DatePicker("还款日",selection:$row.date,displayedComponents:.date)
                    TextField("计划本金",text:$row.principal).keyboardType(.decimalPad)
                    TextField("计划利息",text:$row.interest).keyboardType(.decimalPad)
                    TextField("计划费用",text:$row.fee).keyboardType(.decimalPad)
                }
            }
        }.navigationTitle("核对还款计划").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("保存") {save()}.disabled(store.busy)}}
            .onAppear {guard !loaded else {return};loaded=true;if let loan=store.current.wallet.items("loans").first(where:{$0.id==loanID}) {rows=((try? Loans.schedule(loan)) ?? []).map(PlanDraft.init)}}
    }
    private func save() {
        do {let plan=try rows.map {Installment(id:$0.id,date:$0.date,principal:try Money.parse($0.principal,allowZero:true),interest:try Money.parse($0.interest,allowZero:true),fee:try Money.parse($0.fee,allowZero:true))};Task {if await store.commit({$0=try Loans.savePlan(plan,loanID:loanID,in:$0)}) {dismiss()}}} catch {store.present(error)}
    }
}

private struct RateDraft:Identifiable {var id=UUID();var date=Date();var annual=""}
struct LoanRateEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) private var dismiss
    let loanID:String
    @State private var rows:[RateDraft]=[]
    @State private var loaded=false
    var body:some View {
        Form {
            Section {Text("填写合同约定的重定价日及执行年利率，不自动抓取 LPR。按月生成参考计划；贷款方实际扣息不同，请核对各期计划。已有自定义合同计划时，应直接在计划中修改本息。").font(.caption).foregroundStyle(.secondary)}
            ForEach($rows) {$row in Section {DatePicker("生效日",selection:$row.date,displayedComponents:.date);TextField("执行年利率（%）",text:$row.annual).keyboardType(.decimalPad)}}.onDelete {rows.remove(atOffsets:$0)}
            Button("添加利率调整",systemImage:"plus") {rows.append(RateDraft())}
        }.navigationTitle("利率调整").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("保存") {save()}.disabled(store.busy)}}
            .onAppear {guard !loaded else{return};loaded=true;let loan=store.current.wallet.items("loans").first {$0.id==loanID};rows=(loan?.items("rateChanges") ?? []).map {RateDraft(date:Clock.date($0.text("from")) ?? Date(),annual:Money.amount($0.int("annualBps")))}}
    }
    private func save() {
        do {let changes=try rows.map {Item(["from":.string(Clock.day($0.date)),"annualBps":.int(try Money.parse($0.annual,allowZero:true))])};Task {if await store.commit({d in guard var loan=d.wallet.items("loans").first(where:{$0.id==loanID}) else {throw AppError.message("贷款不存在")};guard loan.items("customSchedule").isEmpty else {throw AppError.message("请在核对还款计划中修改合同本息")};let old=(try Loans.schedule(loan));loan.set("rateChanges",items:changes);let revised=try Loans.schedule(loan);for row in old where Loans.due(row,loan:loan,in:d).total==0 {let new=revised[row.id-1];guard row.principal==new.principal,row.interest==new.interest else {throw AppError.message("利率调整不能改变已还期次，请核对生效日")}};d=try Loans.save(loan,in:d)}) {dismiss()}}} catch {store.present(error)}
    }
}

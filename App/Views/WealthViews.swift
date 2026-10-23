import SwiftUI

struct SubscriptionsView:View {
    @EnvironmentObject var store:AppStore
    @State var adding=false
    @State var editing:Item?
    @State var paying:Item?
    var body:some View {List {
        ForEach(store.current.wealth.items("subscriptions")) {s in
            VStack(alignment:.leading,spacing:9) {
                HStack {Button {editing=s} label:{Text(s.text("name")).font(.headline)};Spacer();Amount(cents:s.int("cents"),currency:store.current.accounts.first {$0.id==s.text("accountId")}?.text("currency",fallback:"CNY") ?? "CNY")}
                HStack {Text(s.bool("active",fallback:true) ? "下期 "+Clock.day(WealthOperations.subscriptionDue(s,in:store.current)):"已停用").font(.caption).foregroundStyle(.secondary);Spacer();if s.bool("active",fallback:true) {Button("确认已付款") {paying=s}.font(.caption)}}
            }.padding(.vertical,6)
        }
        Button("添加订阅",systemImage:"plus") {adding=true}
    }.navigationTitle("订阅与续费").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented:$adding) {NavigationStack {SubscriptionEditor()}.environmentObject(store)}
        .sheet(item:$editing) {s in NavigationStack {SubscriptionEditor(subscription:s)}.environmentObject(store)}
        .confirmationDialog("确认这笔订阅已经实际支付？",isPresented:Binding(get:{paying != nil},set:{if !$0 {paying=nil}}),titleVisibility:.visible) {Button("确认付款并记账") {if let s=paying {Task {await store.commit {$0=WealthOperations.paySubscription(s,in:$0)}}};paying=nil};Button("取消",role:.cancel) {paying=nil}}
    }
}
struct SubscriptionEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    var subscription:Item?
    @State var name=""
    @State var amount=""
    @State var accountID=""
    @State var cycle="monthly"
    @State var date=Date()
    @State var lead=3
    @State var active=true
    var body:some View {Form {
        TextField("订阅名称",text:$name);TextField("每期金额",text:$amount).keyboardType(.decimalPad)
        Picker("扣款账户",selection:$accountID) {Text("请选择").tag("");ForEach(store.current.accounts.filter {!$0.bool("archived")}) {Text($0.text("name")+" · "+$0.text("currency",fallback:"CNY")).tag($0.id)}}
        Picker("周期",selection:$cycle) {Text("每周").tag("weekly");Text("每月").tag("monthly");Text("每季").tag("quarterly");Text("每年").tag("yearly")}
        DatePicker("首次到期日",selection:$date,displayedComponents:.date);Stepper("提前 \(lead) 天提醒",value:$lead,in:0...30);Toggle("启用",isOn:$active)
    }.navigationTitle(subscription==nil ? "添加订阅":"编辑订阅").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("保存") {save()}.disabled(store.busy)}}.onAppear {if let s=subscription {name=s.text("name");amount=Money.amount(s.int("cents"));accountID=s.text("accountId");cycle=s.text("cycle",fallback:"monthly");date=Clock.date(s.text("firstDue")) ?? Date();lead=Int(s.int("leadDays",fallback:3));active=s.bool("active",fallback:true)}}}
    func save() {do {guard !name.isEmpty,!accountID.isEmpty else{throw AppError.message("请填写名称并选择账户")};var s=subscription ?? Item.make();if let old=subscription,store.current.records.contains(where:{$0.text("wealthRef")=="subscription:"+old.id}),old.text("firstDue") != Clock.day(date) || old.text("cycle",fallback:"monthly") != cycle {throw AppError.message("已付款订阅不能修改原始周期，请停用后新建")};s.set("name",name);s.set("cents",try Money.parse(amount));s.set("accountId",accountID);s.set("cycle",cycle);s.set("firstDue",Clock.day(date));s.set("leadDays",Int64(lead));s.set("active",active);s.set("category","订阅");Task {if await store.commit({$0.upsertWealth(s,in:"subscriptions");$0=WealthOperations.refreshSubscription(s,in:$0)}) {dismiss()}}}catch{store.present(error)}}
}

struct EnvelopesView:View {
    @EnvironmentObject var store:AppStore
    @State var adding=false
    @State var name=""
    @State var currency="CNY"
    @State var rollover=true
    @State var allocating:Item?
    @State var allocation=""
    @State var assigning:Item?
    var body:some View {List {
        ForEach(store.current.wealth.items("envelopes")) {e in
            let b=WealthOperations.envelope(e,in:store.current)
            VStack(alignment:.leading,spacing:10) {HStack {Text(e.text("name")).font(.headline);Spacer();Text(e.text("currency",fallback:"CNY")).font(.caption).foregroundStyle(.secondary)};HStack {metric("已分配",b.assigned);Spacer();metric("已使用",b.used);Spacer();metric("剩余",b.remaining)};HStack {Button("分配 / 释放") {allocating=e;allocation=""};Spacer();Button("关联支出") {assigning=e}}.font(.caption)}.padding(.vertical,8)
        }
        Button("新建资金桶",systemImage:"plus") {name="";currency=store.currency;adding=true}
    }.navigationTitle("资金桶").navigationBarTitleDisplayMode(.inline)
        .alert("新建资金桶",isPresented:$adding) {TextField("名称",text:$name);Button("取消",role:.cancel) {};Button("创建") {guard !name.isEmpty else{return};let e=Item.make(["name":.string(name),"currency":.string(currency),"rollover":.bool(true)]);Task {await store.commit {$0.upsertWealth(e,in:"envelopes")}}}} message:{Text("币种：\(currency)，余额滚存。资金桶不产生转账。")}
        .alert("分配资金",isPresented:Binding(get:{allocating != nil},set:{if !$0 {allocating=nil}})) {TextField("正数分配，负数释放",text:$allocation);Button("取消",role:.cancel) {allocating=nil};Button("确认") {allocate()}} message:{Text("从同币种的可动用余额安排资金，不计入支出。")}
        .sheet(item:$assigning) {e in NavigationStack {List(store.current.records.filter {$0.text("kind")=="expense" && $0.text("currency",fallback:"CNY")==e.text("currency",fallback:"CNY")}) {r in Button {Task {if await store.commit({d in var w=d.wealth;var uses=w.items("uses");uses.removeAll {$0.text("recordId")==r.id};uses.append(Item(["recordId":.string(r.id),"envelopeId":.string(e.id)]));w.set("uses",items:uses);d.wealth=w}) {assigning=nil}}} label:{RecordRow(record:r,document:store.current)}}.navigationTitle("关联支出").toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {assigning=nil}}}}.environmentObject(store)}
    }
    func metric(_ label:String,_ amount:Int64)->some View {VStack(alignment:.leading,spacing:4) {Text(label).font(.caption2).foregroundStyle(.secondary);Amount(cents:amount)}}
    func allocate() {guard let e=allocating else{return};do {let amount=try Money.parse(allocation,signed:true);let d=store.current;let b=WealthOperations.envelope(e,in:d);let cash=d.accounts.filter {!$0.bool("archived") && $0.text("type") != "credit" && $0.text("currency",fallback:"CNY")==e.text("currency",fallback:"CNY")}.reduce(Int64(0)){$0+Finance.balance($1,in:d)};let allocated=d.wealth.items("envelopes").filter {$0.text("currency",fallback:"CNY")==e.text("currency",fallback:"CNY")}.reduce(Int64(0)) {$0+max(0,WealthOperations.envelope($1,in:d).remaining)};guard amount>0 ? amount<=max(0,cash-allocated) : -amount<=max(0,b.remaining) else {throw AppError.message("超过可分配资金或桶内剩余金额")};let a=Item.make(["envelopeId":.string(e.id),"month":.string(Clock.month()),"cents":.int(amount)]);Task {await store.commit {$0.upsertWealth(a,in:"allocations")}}}catch{store.present(error)};allocating=nil}
}

struct SplitGroupsView:View {
    @EnvironmentObject var store:AppStore
    @State var adding=false
    var body:some View {List {ForEach(store.current.wealth.items("groups")) {g in NavigationLink {SplitGroupDetail(group:g)} label:{VStack(alignment:.leading,spacing:5) {Text(g.text("name")).font(.headline);Text(g.strings("members").joined(separator:"、")+" · "+g.text("currency",fallback:"CNY")).font(.caption).foregroundStyle(.secondary)}}};Button("新建 AA 账本",systemImage:"plus") {adding=true}}.navigationTitle("AA 分摊").navigationBarTitleDisplayMode(.inline).sheet(isPresented:$adding) {NavigationStack {SplitGroupEditor()}.environmentObject(store)}}
}
struct SplitGroupEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    @State var name=""
    @State var members="我，"
    @State var me="我"
    @State var currency="CNY"
    var body:some View {Form {TextField("账本名称",text:$name);TextField("成员，用逗号分开",text:$members,axis:.vertical);TextField("我的成员名称",text:$me);Picker("币种",selection:$currency) {ForEach(Money.currencies,id:\.self) {Text($0).tag($0)}}}.navigationTitle("新建 AA 账本").toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("保存") {let people=members.replacingOccurrences(of:"，",with:",").split(separator:",").map {String($0).trimmingCharacters(in:.whitespaces)};guard !name.isEmpty,(2...30).contains(people.count),Set(people).count==people.count,people.contains(me) else{store.error="请填写名称及2至30个不同成员，并包含本人";return};let g=Item.make(["name":.string(name),"members":.array(people.map {.string($0)}),"me":.string(me),"currency":.string(currency)]);Task {if await store.commit({$0.upsertWealth(g,in:"groups")}) {dismiss()}}}}}.onAppear {currency=store.currency}}
}
struct SplitGroupDetail:View {
    @EnvironmentObject var store:AppStore
    let group:Item
    @State var adding=false
    @State var settling=false
    var body:some View {List {
        Section("待结算") {ForEach(group.strings("members"),id:\.self) {member in let amount=WealthOperations.splitBalances(group,in:store.current)[member] ?? 0;HStack {Text(member);Spacer();Text(amount>=0 ? "待收":"待付").font(.caption).foregroundStyle(.secondary);Amount(cents:abs(amount))}}}
        Section {Button("添加分摊",systemImage:"plus") {adding=true};Button("记录结算",systemImage:"arrow.left.arrow.right") {settling=true}}
        Section("分摊记录") {ForEach(store.current.wealth.items("splits").filter {$0.text("groupId")==group.id}) {s in VStack(alignment:.leading,spacing:6) {HStack {Text(s.text("title"));Spacer();Amount(cents:s.int("cents"))};Text(s.text("payer")+"付款 · "+s.items("shares").map {$0.text("member")+" "+Money.amount($0.int("cents"))}.joined(separator:"，")).font(.caption).foregroundStyle(.secondary)}}}
    }.navigationTitle(group.text("name")).navigationBarTitleDisplayMode(.inline).sheet(isPresented:$adding) {NavigationStack {SplitEntryEditor(group:group)}.environmentObject(store)}.sheet(isPresented:$settling) {NavigationStack {SplitSettlementEditor(group:group)}.environmentObject(store)}}
}
struct SplitEntryEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    let group:Item
    @State var title=""
    @State var amount=""
    @State var payer=""
    @State var accountID=""
    @State var shares:[String:String]=[:]
    var body:some View {Form {TextField("分摊事项",text:$title);TextField("总金额",text:$amount).keyboardType(.decimalPad);Picker("付款人",selection:$payer) {ForEach(group.strings("members"),id:\.self) {Text($0).tag($0)}};AccountPicker(accountID:$accountID,currency:group.text("currency",fallback:"CNY"));Button("平均分摊") {if let total=try? Money.parse(amount) {let members=group.strings("members"),part=total/Int64(members.count),rem=total%Int64(members.count);for (i,person) in members.enumerated() {shares[person]=Money.amount(part+(i<Int(rem) ? 1:0))}}};Section("每人的消费份额") {ForEach(group.strings("members"),id:\.self) {person in HStack {Text(person);TextField("0.00",text:Binding(get:{shares[person] ?? ""},set:{shares[person]=$0})).keyboardType(.decimalPad).multilineTextAlignment(.trailing)}}}}.navigationTitle("添加分摊").toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("保存") {save()}.disabled(store.busy)}}.onAppear {payer=group.text("me")}}
    func save() {do {guard !title.isEmpty else{throw AppError.message("请填写分摊事项")};let total=try Money.parse(amount),values=try group.strings("members").map {Item(["member":.string($0),"cents":.int(try Money.parse(shares[$0] ?? "0",allowZero:true))])};guard values.reduce(Int64(0),{$0+$1.int("cents")})==total else{throw AppError.message("各成员份额之和必须等于总金额")};let e=Item.make(["groupId":.string(group.id),"title":.string(title),"payer":.string(payer),"cents":.int(total),"accountId":.string(accountID),"date":.int(Clock.milliseconds),"shares":.array(values.map {.object($0.raw)})]);Task {if await store.commit({$0=try WealthOperations.addSplit(e,group:group,in:$0)}) {dismiss()}}}catch{store.present(error)}}
}
struct SplitSettlementEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    let group:Item
    @State var from=""
    @State var to=""
    @State var amount=""
    @State var accountID=""
    var body:some View {Form {Picker("付款人",selection:$from) {Text("请选择").tag("");ForEach(group.strings("members"),id:\.self) {Text($0).tag($0)}};Picker("收款人",selection:$to) {Text("请选择").tag("");ForEach(group.strings("members"),id:\.self) {Text($0).tag($0)}};TextField("结算金额",text:$amount).keyboardType(.decimalPad);AccountPicker(accountID:$accountID,currency:group.text("currency",fallback:"CNY"));Text("仅实际收到或付出资金后确认，结算不重复计入消费。").font(.caption).foregroundStyle(.secondary)}.navigationTitle("记录结算").toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("确认") {do {let e=Item.make(["groupId":.string(group.id),"from":.string(from),"to":.string(to),"cents":.int(try Money.parse(amount)),"accountId":.string(accountID),"date":.int(Clock.milliseconds)]);Task {if await store.commit({$0=try WealthOperations.settle(e,group:group,in:$0)}) {dismiss()}}}catch{store.present(error)}}}}}
}
struct AccountPicker:View {
    @EnvironmentObject var store:AppStore
    @Binding var accountID:String
    var currency:String
    var body:some View {Picker("本人收付账户",selection:$accountID) {Text("请选择").tag("");ForEach(store.current.accounts.filter {!$0.bool("archived") && $0.text("currency",fallback:"CNY")==currency && $0.text("type") != "credit"}) {Text($0.text("name")).tag($0.id)}}}
}

struct InvestmentsView:View {
    @EnvironmentObject var store:AppStore
    @State var adding=false
    var body:some View {List {ForEach(store.current.wealth.items("positions")) {p in if let a=store.current.wallet.items("assets").first(where:{$0.id==p.text("assetId")}) {NavigationLink {InvestmentDetail(asset:a)} label:{HStack {Text(a.text("name"));Spacer();Amount(cents:a.int("cents"),currency:a.text("currency",fallback:"CNY"))}}}};Button("新建投资持仓",systemImage:"plus") {adding=true}}.navigationTitle("投资持仓").navigationBarTitleDisplayMode(.inline).sheet(isPresented:$adding) {NavigationStack {PositionEditor()}.environmentObject(store)}}
}
struct PositionEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    @State var name=""
    @State var currency="CNY"
    @State var symbol=""
    @State var price="0"
    @State var kind="fund"
    var body:some View {Form {TextField("投资名称",text:$name);TextField("代码",text:$symbol);Picker("类型",selection:$kind) {Text("基金").tag("fund");Text("股票").tag("stock")};Picker("币种",selection:$currency) {ForEach(Money.currencies,id:\.self) {Text($0).tag($0)}};TextField("当前单价",text:$price).keyboardType(.decimalPad)}.navigationTitle("新建持仓").toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("保存") {do {guard !name.isEmpty else {throw AppError.message("请填写投资名称")};_=try WealthOperations.quantity(price);let a=Item.make(["name":.string(name),"kind":.string(kind),"currency":.string(currency),"cents":.int(0),"valuedAt":.int(Clock.milliseconds)]);let p=Item(["assetId":.string(a.id),"symbol":.string(symbol),"price":.string(price),"quotedAt":.int(Clock.milliseconds)]);Task {if await store.commit({d in d.upsertWallet(a,in:"assets");var w=d.wealth;var ps=w.items("positions");ps.append(p);w.set("positions",items:ps);var qs=w.items("quotes");qs.append(Item(["assetId":.string(a.id),"price":.string(price),"at":.int(Clock.milliseconds)]));w.set("quotes",items:qs);d.wealth=w}) {dismiss()}}}catch{store.present(error)}}}}.onAppear {currency=store.currency}}
}
struct InvestmentDetail:View {
    @EnvironmentObject var store:AppStore
    let asset:Item
    @State var trading=false
    @State var quoting=false
    @State var price=""
    var position:Item {store.current.wealth.items("positions").first {$0.text("assetId")==asset.id} ?? Item()}
    var body:some View {List {
        if let r=try? WealthOperations.position(position,in:store.current) {Section("持仓") {LabeledContent("数量",value:NSDecimalNumber(decimal:r.quantity).stringValue);LabeledContent("成本",value:Money.amount(r.cost));LabeledContent("当前市值",value:Money.amount(r.market));LabeledContent("未实现盈亏",value:Money.amount(r.market-r.cost));LabeledContent("已实现盈亏",value:Money.amount(r.realized));LabeledContent("净分红",value:Money.amount(r.dividends))}}
        Section {Button("登记交易 / 分红") {trading=true};Button("更新价格") {price=position.text("price");quoting=true}}
        Section("交易记录") {ForEach(store.current.wealth.items("trades").filter {$0.text("assetId")==asset.id}) {t in HStack {Text(t.text("side")=="buy" ? "买入":t.text("side")=="sell" ? "卖出":"分红");Text(t.text("quantity")).font(.caption).foregroundStyle(.secondary);Spacer();Amount(cents:t.int("grossCents"))}}}
    }.navigationTitle(asset.text("name")).navigationBarTitleDisplayMode(.inline).sheet(isPresented:$trading) {NavigationStack {InvestmentTradeEditor(asset:asset)}.environmentObject(store)}
        .alert("更新价格",isPresented:$quoting) {TextField("单价",text:$price);Button("取消",role:.cancel) {};Button("保存") {do {_=try WealthOperations.quantity(price);Task {await store.commit {d in var w=d.wealth;w.set("positions",items:w.items("positions").map {p in var n=p;if p.text("assetId")==asset.id {n.set("price",price);n.set("quotedAt",Clock.milliseconds)};return n});var qs=w.items("quotes");qs.append(Item(["assetId":.string(asset.id),"price":.string(price),"at":.int(Clock.milliseconds)]));w.set("quotes",items:qs);d.wealth=w;d=try WealthOperations.syncPosition(asset.id,in:d)}}}catch{store.present(error)}}}
    }
}
struct InvestmentTradeEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    let asset:Item
    @State var side="buy"
    @State var quantity=""
    @State var amount=""
    @State var fee="0"
    @State var accountID=""
    @State var date=Date()
    var body:some View {Form {Picker("类型",selection:$side) {Text("买入").tag("buy");Text("卖出").tag("sell");Text("分红").tag("dividend")};if side != "dividend" {TextField("数量",text:$quantity).keyboardType(.decimalPad)};TextField("成交总额 / 分红金额",text:$amount).keyboardType(.decimalPad);TextField("费用",text:$fee).keyboardType(.decimalPad);AccountPicker(accountID:$accountID,currency:asset.text("currency",fallback:"CNY"));DatePicker("交易日期",selection:$date,in:...Date(),displayedComponents:.date)}.navigationTitle("登记投资交易").toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("保存") {do {let q=side=="dividend" ? "0":quantity;_=try WealthOperations.quantity(q);let t=Item.make(["assetId":.string(asset.id),"side":.string(side),"quantity":.string(q),"grossCents":.int(try Money.parse(amount)),"feeCents":.int(try Money.parse(fee,allowZero:true)),"accountId":.string(accountID),"date":.int(Int64(date.timeIntervalSince1970*1000))]);Task {if await store.commit({$0=try WealthOperations.trade(t,in:$0)}) {dismiss()}}}catch{store.present(error)}}.disabled(store.busy)}}}
}

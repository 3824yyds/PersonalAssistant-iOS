import SwiftUI

struct WalletView: View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var scheme
    @State var expanded=false
    @State var selected:String?
    @State var creating=false
    @State var editing:Item?
    @State var assets=false
    var cards:[Item] {store.current.accounts.filter {!$0.bool("archived") && ["bank","credit"].contains($0.text("type"))}}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                HStack {Text("我的卡片 · \(cards.count)").font(.headline);Spacer();if cards.count>2 {Button(expanded ? "收起":"查看全部") {withAnimation(Theme.normal) {expanded.toggle();selected=nil}}.font(.caption)}}
                if cards.isEmpty {EmptyState(icon:"creditcard",title:"把账户收进卡包",subtitle:"添加银行卡或信用卡，余额会与账本同步")}
                VStack(spacing:expanded || cards.count<=2 ? 16:-142) {
                    ForEach(cards) {a in
                        VStack(spacing:0) {
                            Button {
                                if !expanded && cards.count>2 {withAnimation(Theme.normal) {expanded=true};return}
                                withAnimation(Theme.normal) {selected=selected==a.id ? nil:a.id}
                            } label:{CardFace(account:a,card:store.current.wallet.items("cards").first {$0.text("accountId")==a.id})}.buttonStyle(.plain)
                            if selected==a.id && (expanded || cards.count<=2) {
                                CardDetailsView(account:a).padding(16).frame(maxWidth:.infinity).background(Theme.panel(scheme)).transition(.opacity.combined(with:.move(edge:.top)))
                            }
                        }.clipShape(RoundedRectangle(cornerRadius:20,style:.continuous)).contextMenu {Button("编辑账户",systemImage:"pencil") {editing=a}}
                    }
                }
                Panel {NavigationLink {AccountsView()} label:{Label("全部账户与转账",systemImage:"building.columns")};Divider();NavigationLink {AssetsView()} label:{Label("资产与负债",systemImage:"chart.pie")};Divider();NavigationLink {LoansView()} label:{Label("贷款与还款",systemImage:"calendar.badge.clock")}}
            }.padding(16)
        }.background(Theme.background(scheme)).navigationTitle("卡包与资产").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.topBarLeading) {Button("完成") {dismiss()}};ToolbarItem(placement:.topBarTrailing) {Button {creating=true} label:{Image(systemName:"plus")}.accessibilityLabel("添加账户")}}
            .sheet(isPresented:$creating) {NavigationStack {AccountEditor()}.environmentObject(store)}
            .sheet(item:$editing) {a in NavigationStack {AccountEditor(account:a)}.environmentObject(store)}
    }
}

struct CardFace:View {
    var account:Item,card:Item?
    var art:CardArtwork? {Artwork.cards.first {$0.id==card?.text("design")}}
    var body:some View {
        GeometryReader {proxy in
            ZStack(alignment:.bottomTrailing) {
                if let art {Image(art.id).resizable().interpolation(.high).scaledToFill().frame(width:proxy.size.width,height:206).clipped()}
                else {
                    LinearGradient(colors:account.text("type")=="credit" ? [Color(red:0.12,green:0.15,blue:0.22),Color(red:0.22,green:0.29,blue:0.39)]:[Color(red:0.16,green:0.36,blue:0.65),Color(red:0.35,green:0.55,blue:0.78)],startPoint:.topLeading,endPoint:.bottomTrailing)
                    Circle().stroke(.white.opacity(0.08),lineWidth:50).frame(width:250,height:250).offset(x:80,y:70)
                    VStack(alignment:.leading,spacing:8) {HStack {AccountIcon(name:account.text("name"),type:account.text("type"));Text(account.text("name")).font(.system(size:17,weight:.semibold));Spacer()};Text(account.text("type")=="credit" ? "CREDIT":"DEBIT").font(.system(size:9,weight:.medium)).tracking(3);Spacer()}.foregroundStyle(.white).padding(20)
                }
                HStack(alignment:.bottom,spacing:10) {
                    if let card,!card.text("lastFour").isEmpty {Text("•••• "+card.text("lastFour")).font(.system(size:13,weight:.semibold,design:.monospaced)).shadow(radius:2)}
                    NetworkMark(network:card?.text("network") ?? "")
                }.foregroundStyle(.white).padding(16)
            }.frame(height:206).contentShape(Rectangle())
        }.frame(height:206).accessibilityLabel(account.text("name")+"，尾号"+(card?.text("lastFour") ?? "未设置"))
    }
}
struct NetworkMark:View {
    var network:String
    var body:some View {Group {
        if network=="mastercard" {ZStack {Circle().fill(Color(red:0.92,green:0,blue:0.1)).offset(x:-8);Circle().fill(Color(red:0.98,green:0.62,blue:0.1)).blendMode(.plusLighter).offset(x:8)}.frame(width:36,height:23)}
        else if network=="visa" {Text("VISA").font(.system(size:18,weight:.heavy,design:.rounded)).italic()}
        else if network=="unionpay" {Text("银联").font(.system(size:12,weight:.bold)).padding(.horizontal,5).padding(.vertical,3).background(LinearGradient(colors:[.red,.blue,.teal],startPoint:.leading,endPoint:.trailing),in:RoundedRectangle(cornerRadius:3))}
        else if network=="amex" {Text("AMEX").font(.system(size:11,weight:.bold)).padding(4).background(.blue,in:RoundedRectangle(cornerRadius:3))}
    }.accessibilityHidden(true)}
}

struct CardDetailsView:View {
    @EnvironmentObject var store:AppStore
    var account:Item
    @State var editing=false
    @State var repaying=false
    var card:Item {store.current.wallet.items("cards").first {$0.text("accountId")==account.id} ?? Item()}
    var balance:Int64 {Finance.balance(account,in:store.current)}
    var currency:String {account.text("currency",fallback:"CNY")}
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {Text(account.text("name")).font(.headline);Spacer();Button {editing=true} label:{Image(systemName:"pencil").font(.caption)}.accessibilityLabel("编辑账户")}
            Text(account.text("type")=="credit" ? (balance>0 ? "溢缴款":"当前欠款"):"账户余额").font(.caption).foregroundStyle(.secondary)
            Amount(cents:account.text("type")=="credit" ? abs(balance):balance,currency:currency,prominent:true)
            if account.text("type")=="credit" {
                Divider()
                Grid(alignment:.leading,horizontalSpacing:18,verticalSpacing:12) {
                    GridRow {detail("信用额度",card.int("limitCents"));detail("可用额度",max(0,card.int("limitCents")-max(0,-balance)))}
                    GridRow {detail("账单金额",card.int("statementCents"));detail("本期已还",Finance.paid(card,in:store.current))}
                    GridRow {VStack(alignment:.leading,spacing:4) {Text("账单日 / 还款日").font(.caption2).foregroundStyle(.secondary);Text("\(card.int("statementDay"))日 / \(card.int("repaymentDay"))日").font(.subheadline)};detail("本期未还",max(0,card.int("statementCents")-Finance.paid(card,in:store.current)))}
                }
                if balance<0 {Button("记录还款") {repaying=true}.buttonStyle(.borderedProminent).frame(maxWidth:.infinity)}
            }
            let rs=Finance.select(store.current,month:Date(),currency:currency,account:account.text("name")),totals=Totals(rs)
            Divider();HStack {detail("本月收入",totals.income);Spacer();detail("本月净支出",totals.netExpense)}
            if !card.text("branch").isEmpty {Text(card.text("branch")).font(.caption).foregroundStyle(.secondary)}
            if !card.text("memo").isEmpty {Text(card.text("memo")).font(.caption).foregroundStyle(.secondary)}
            ForEach(rs.prefix(3)) {r in RecordRow(record:r,document:store.current)}
        }.sheet(isPresented:$editing) {NavigationStack {AccountEditor(account:account)}.environmentObject(store)}
            .sheet(isPresented:$repaying) {NavigationStack {TransferView(to:account.id,repayment:true)}.environmentObject(store)}
    }
    func detail(_ label:String,_ cents:Int64)->some View {VStack(alignment:.leading,spacing:5) {Text(label).font(.caption2).foregroundStyle(.secondary);Amount(cents:cents)}}
}

struct AccountsView:View {
    @EnvironmentObject var store:AppStore
    @State var creating=false
    @State var editing:Item?
    @State var transferring=false
    var body:some View {List {
        ForEach(store.current.accounts) {a in Button {editing=a} label:{HStack {AccountIcon(name:a.text("name"),type:a.text("type"));VStack(alignment:.leading,spacing:4) {Text(a.text("name")).foregroundStyle(.primary);Text(a.bool("archived") ? "已归档":a.text("currency",fallback:"CNY")).font(.caption).foregroundStyle(.secondary)};Spacer();Amount(cents:Finance.balance(a,in:store.current))}}}
        Section {Button("添加账户",systemImage:"plus") {creating=true};Button("账户转账",systemImage:"arrow.left.arrow.right") {transferring=true}}
    }.navigationTitle("账户与余额").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented:$creating) {NavigationStack {AccountEditor()}.environmentObject(store)}
        .sheet(item:$editing) {a in NavigationStack {AccountEditor(account:a)}.environmentObject(store)}
        .sheet(isPresented:$transferring) {NavigationStack {TransferView()}.environmentObject(store)}
    }
}

struct AccountEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    var account:Item?
    @State var name=""
    @State var currency="CNY"
    @State var type="bank"
    @State var opening="0.00"
    @State var lastFour=""
    @State var network="unionpay"
    @State var design=""
    @State var limit="0.00"
    @State var statement="0.00"
    @State var statementMonth=Clock.month()
    @State var statementDay=1
    @State var repaymentDay=20
    @State var memo=""
    @State var branch=""
    @State var archived=false
    @State var presets=false
    var availableArt:[CardArtwork] {Artwork.cards.filter {$0.bank==name && $0.kind==type && $0.network==network}}
    var body:some View {
        Form {
            Section("账户") {
                Button {presets=true} label:{HStack {Text("选择机构模板");Spacer();Image(systemName:"chevron.right").font(.caption)}}
                TextField("账户名称",text:$name)
                Picker("类型",selection:$type) {Text("借记卡").tag("bank");Text("信用卡").tag("credit");Text("现金").tag("cash");Text("电子钱包").tag("wallet")}
                Picker("币种",selection:$currency) {ForEach(Money.currencies,id:\.self) {Text($0).tag($0)}}.disabled(account != nil)
                TextField(type=="credit" ? "期初余额（欠款填负数）":"期初余额",text:$opening).keyboardType(.numbersAndPunctuation)
            }
            if type=="bank" || type=="credit" {Section("卡片") {
                TextField("卡号后四位",text:$lastFour).keyboardType(.numberPad)
                Picker("卡组织",selection:$network) {Text("银联").tag("unionpay");Text("Visa").tag("visa");Text("Mastercard").tag("mastercard");Text("American Express").tag("amex");Text("无").tag("")}
                Picker("卡面",selection:$design) {Text("简约卡面").tag("");ForEach(availableArt) {Text($0.title).tag($0.id)}}
                TextField("开户行 / 支行",text:$branch)
            }}
            if type=="credit" {Section("账单与还款") {
                TextField("信用额度",text:$limit).keyboardType(.decimalPad)
                TextField("账单月份，例如 2026-10",text:$statementMonth).textInputAutocapitalization(.never)
                TextField("本期账单金额",text:$statement).keyboardType(.decimalPad)
                Stepper("账单日：\(statementDay)日",value:$statementDay,in:1...31)
                Stepper("还款日：\(repaymentDay)日",value:$repaymentDay,in:1...31)
            }}
            Section {TextField("备注",text:$memo,axis:.vertical);if account != nil {Toggle("归档账户",isOn:$archived)}}
        }.navigationTitle(account==nil ? "新建账户":"编辑账户").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("保存") {save()}.disabled(store.busy)}}
            .onAppear {load()}.onChange(of:name) {_,_ in design=""}.onChange(of:network) {_,_ in design=""}.onChange(of:type) {_,_ in design=""}
            .sheet(isPresented:$presets) {AccountPresetsView {p in name=p.name;currency=p.currency;type=p.type;design="";presets=false}}
    }
    func load() {
        guard let a=account else {currency=store.currency;return};name=a.text("name");currency=a.text("currency",fallback:"CNY");type=a.text("type",fallback:"bank");opening=Money.amount(a.int("openingCents"));archived=a.bool("archived")
        if let c=store.current.wallet.items("cards").first(where:{$0.text("accountId")==a.id}) {lastFour=c.text("lastFour");network=c.text("network",fallback:"unionpay");design=c.text("design");limit=Money.amount(c.int("limitCents"));statement=Money.amount(c.int("statementCents"));statementMonth=c.text("statementMonth",fallback:Clock.month());statementDay=Int(c.int("statementDay",fallback:1));repaymentDay=Int(c.int("repaymentDay",fallback:20));branch=c.text("branch");memo=c.text("memo")}
    }
    func save() {do {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, name.count<=100,lastFour.isEmpty || lastFour.range(of:#"^[0-9]{4}$"#,options:.regularExpression) != nil else {throw AppError.message("请核对账户名称及卡号后四位")}
        var a=account ?? Item.make();a.set("name",name.trimmingCharacters(in:.whitespacesAndNewlines));a.set("currency",currency);a.set("type",type);a.set("openingCents",try Money.parse(opening,signed:true,allowZero:true));a.set("openingDate",account?.int("openingDate",fallback:1) ?? 1);a.set("archived",archived)
        var c=store.current.wallet.items("cards").first {$0.text("accountId")==a.id} ?? Item();c.set("accountId",a.id);c.set("institution",name);c.set("lastFour",lastFour);c.set("network",network);c.set("design",availableArt.contains(where:{$0.id==design}) ? design:"");c.set("branch",branch);c.set("memo",memo)
        if type=="credit" {
            guard Clock.date(statementMonth+"-01") != nil else {throw AppError.message("账单月份格式应为 YYYY-MM")}
            c.set("limitCents",try Money.parse(limit,allowZero:true));c.set("statementCents",try Money.parse(statement,allowZero:true));c.set("statementMonth",statementMonth);c.set("statementDay",Int64(statementDay));c.set("repaymentDay",Int64(repaymentDay))
        }
        Task {if await store.commit({$0=try Finance.saveAccount(a,card:(type=="bank" || type=="credit") ? c:nil,in:$0)}) {dismiss()}}
    }catch {store.present(error)}}
}
struct AccountPresetsView:View {
    var select:(AccountPreset)->Void
    @Environment(\.dismiss) var dismiss
    @State var query=""
    var body:some View {NavigationStack {List(Artwork.accounts.filter {query.isEmpty || ($0.name+$0.region).localizedCaseInsensitiveContains(query)}) {p in Button {select(p);dismiss()} label:{HStack {AccountIcon(name:p.name,type:p.type);VStack(alignment:.leading,spacing:4) {Text(p.name);Text(p.region+" · "+p.currency).font(.caption).foregroundStyle(.secondary)}}}}.searchable(text:$query,prompt:"搜索银行或地区").navigationTitle("选择机构").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}}}}}
}

struct TransferView:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    var to:String="",repayment=false
    @State var fromID=""
    @State var toID=""
    @State var amount=""
    @State var memo=""
    var accounts:[Item] {store.current.accounts.filter {!$0.bool("archived")}}
    var body:some View {Form {
        Picker("转出账户",selection:$fromID) {Text("请选择").tag("");ForEach(accounts.filter {!repayment || $0.text("type") != "credit"}) {Text($0.text("name")+" · "+$0.text("currency",fallback:"CNY")).tag($0.id)}}
        Picker("转入账户",selection:$toID) {Text("请选择").tag("");ForEach(accounts) {Text($0.text("name")+" · "+$0.text("currency",fallback:"CNY")).tag($0.id)}}.disabled(repayment)
        TextField("金额",text:$amount).keyboardType(.decimalPad)
        if !repayment {TextField("备注",text:$memo)}
        Text("转账不计入收入或支出；余额会同步影响卡包。").font(.caption).foregroundStyle(.secondary)
    }.navigationTitle(repayment ? "信用卡还款":"账户转账").navigationBarTitleDisplayMode(.inline).toolbar {
        ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}}
        ToolbarItem(placement:.confirmationAction) {Button("确认") {do {let cents=try Money.parse(amount);Task {if await store.commit({d in if repayment {guard let credit=d.accounts.first(where:{$0.id==toID}) else {throw AppError.message("信用卡不存在")};d=try Finance.repay(d,credit:credit,from:fromID,cents:cents)} else {d=try Finance.transfer(d,from:fromID,to:toID,cents:cents,memo:memo)}}) {dismiss()}}}catch{store.present(error)}}.disabled(store.busy)}
    }.onAppear {toID=to}}
}

struct AssetsView:View {
    @EnvironmentObject var store:AppStore
    @State var editing:Item?
    @State var adding=false
    var body:some View {List {
        Section("手动资产与负债") {ForEach(store.current.wallet.items("assets")) {a in Button {editing=a} label:{HStack {VStack(alignment:.leading,spacing:5) {Text(a.text("name"));Text(a.text("kind")=="debt" ? "负债":"资产").font(.caption).foregroundStyle(.secondary)};Spacer();Amount(cents:a.int("cents"),currency:a.text("currency",fallback:"CNY"))}}}.onDelete {indices in let ids=Set(indices.map {store.current.wallet.items("assets")[$0].id});Task {await store.commit {d in var w=d.wallet;w.set("assets",items:w.items("assets").filter {!ids.contains($0.id)});d.wallet=w}}}}
        Section {Button("添加资产",systemImage:"plus") {adding=true}}
    }.navigationTitle("资产管理").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented:$adding) {NavigationStack {AssetEditor()}.environmentObject(store)}
        .sheet(item:$editing) {a in NavigationStack {AssetEditor(asset:a)}.environmentObject(store)}
    }
}
struct AssetEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    var asset:Item?
    @State var name=""
    @State var amount=""
    @State var currency="CNY"
    @State var kind="fund"
    @State var memo=""
    var body:some View {Form {TextField("资产名称",text:$name);Picker("类型",selection:$kind) {Text("基金").tag("fund");Text("股票").tag("stock");Text("房产").tag("property");Text("独立存款").tag("deposit");Text("其他资产").tag("other");Text("其他负债").tag("debt")};Picker("币种",selection:$currency) {ForEach(Money.currencies,id:\.self) {Text($0).tag($0)}};TextField("估值金额",text:$amount).keyboardType(.decimalPad);TextField("备注",text:$memo);Text("与账户存款分开记录，避免将同一笔资产重复计入。").font(.caption).foregroundStyle(.secondary)}.navigationTitle(asset==nil ? "添加资产":"编辑资产").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("保存") {do {guard !name.isEmpty else {throw AppError.message("请填写资产名称")};var a=asset ?? Item.make();a.set("name",name);a.set("kind",kind);a.set("currency",currency);a.set("cents",try Money.parse(amount,allowZero:true));a.set("valuedAt",Clock.milliseconds);a.set("memo",memo);Task {if await store.commit({$0.upsertWallet(a,in:"assets")}) {dismiss()}}}catch{store.present(error)}}}}.onAppear {currency=store.currency;if let a=asset {name=a.text("name");kind=a.text("kind");currency=a.text("currency");amount=Money.amount(a.int("cents"));memo=a.text("memo")}}}
}

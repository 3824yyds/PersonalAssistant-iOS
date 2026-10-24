import SwiftUI

struct RemindersView:View {
    @Binding var sheet:RootSheet?
    @EnvironmentObject var store:AppStore
    @Environment(\.colorScheme) var scheme
    @State var query=""
    @State var showCompleted=false
    @State var priority:Int64 = -1
    @State var editing:Item?
    @State private var linkedLoan:Item?
    var items:[Item] {store.current.records.filter {$0.text("kind")=="reminder" && $0.bool("completed")==showCompleted && (priority<0 || $0.int("priority",fallback:1)==priority) && (query.isEmpty || ($0.text("title")+$0.text("body")).localizedCaseInsensitiveContains(query))}.sorted {$0.int("due")<$1.int("due")}}
    var body:some View {
        VStack(spacing:0) {
            PageHeader(title:"提醒",sheet:$sheet) {
                Menu {Toggle("查看已完成",isOn:$showCompleted);Picker("优先级",selection:$priority) {Text("全部优先级").tag(Int64(-1));Text("高").tag(Int64(2));Text("普通").tag(Int64(1));Text("低").tag(Int64(0))};Button("开启通知") {Task {if !(await NotificationService.request()) {store.error="通知未开启，请到系统设置允许本应用通知"} else {NotificationService.sync(store.current.records)}}}} label:{Image(systemName:"line.3.horizontal.decrease").accessibilityLabel("提醒筛选")}
            }
            List {
        if items.isEmpty {EmptyState(icon:"bell",title:showCompleted ? "还没有已完成提醒":"今天也能从容安排",subtitle:"点右下角＋，添加一项提醒").listRowSeparator(.hidden).listRowBackground(Color.clear)}
        ForEach(items) {r in HStack(alignment:.top,spacing:12) {
            Button {complete(r)} label:{Image(systemName:r.bool("completed") ? "checkmark.circle.fill":"circle").font(.system(size:22,weight:.light)).foregroundStyle(Theme.accent)}.buttonStyle(.borderless).accessibilityLabel("完成提醒")
            Button {open(r)} label:{VStack(alignment:.leading,spacing:6) {Text(r.text("title")).font(.system(size:15,weight:.medium)).foregroundStyle(.primary);Text(Date(timeIntervalSince1970:Double(r.int("due"))/1000).formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(r.int("due")<Clock.milliseconds && !r.bool("completed") ? Theme.expense:.secondary);if !r.text("body").isEmpty {Text(r.text("body")).font(.caption).foregroundStyle(.secondary).lineLimit(2)}}}.buttonStyle(.plain);Spacer();if r.int("priority")==2 {Image(systemName:"exclamationmark").foregroundStyle(Theme.expense).font(.caption)}
        }.padding(.vertical,6).listRowBackground(Color.clear).swipeActions {if !r.bool("loanReminder") {Button(role:.destructive) {Task {await store.commit {$0.records.removeAll {$0.id==r.id}}}} label:{Label("删除",systemImage:"trash")}}}}

            }.listStyle(.plain).scrollContentBackground(.hidden).clipped()
            FloatingSearchField(text:$query,prompt:"搜索提醒")
        }.background {Theme.background(scheme).ignoresSafeArea()}.appClearChrome().toolbar(.hidden,for:.navigationBar)
        .sheet(item:$editing) {r in NavigationStack {ReminderEditor(reminder:r)}.environmentObject(store)}
        .sheet(item:$linkedLoan) {loan in NavigationStack {LoanDetailView(loanID:loan.id).toolbar {ToolbarItem(placement:.cancellationAction) {Button("完成") {linkedLoan=nil}}}}.environmentObject(store)}
    }
    private func open(_ reminder:Item) {
        if reminder.bool("loanReminder") {linkedLoan=store.current.wallet.items("loans").first {$0.id==reminder.text("linkedLoanId")}}
        else {editing=reminder}
    }
    func complete(_ r:Item) {
        if r.bool("loanReminder") {open(r);return}
        guard !r.bool("completed") else{return};var changed=r
        let period=r.text("period",fallback:"none")
        if period=="none" {changed.set("completed",true)}else {
            let date=Date(timeIntervalSince1970:Double(r.int("due"))/1000),component:Calendar.Component = period=="daily" ? .day:period=="weekly" ? .weekOfYear:period=="monthly" ? .month:.year
            let next=Calendar.current.date(byAdding:component,value:1,to:date) ?? date.addingTimeInterval(86400)
            changed.set("due",Int64(next.timeIntervalSince1970*1000));changed.set("alertAt",Int64(next.timeIntervalSince1970*1000)-(r.int("due")-r.int("alertAt")))
            var done=r.raw["completedPeriods"]?.array ?? [];done.append(.int(r.int("due")));changed.raw["completedPeriods"] = .array(done)
        }
        Task {await store.commit {$0.upsert(changed,in:"records")}}
    }
}
struct ReminderEditor:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    var reminder:Item?
    @State var title=""
    @State var bodyText=""
    @State var date=Date().addingTimeInterval(3600)
    @State var period="none"
    @State var priority=1
    @State var paused=false
    var body:some View {Form {
        Section {TextField("要提醒什么",text:$title);TextField("备注",text:$bodyText,axis:.vertical).lineLimit(2...5)}
        Section {DatePicker("提醒时间",selection:$date,displayedComponents:[.date,.hourAndMinute]);Picker("重复",selection:$period) {Text("不重复").tag("none");Text("每天").tag("daily");Text("每周").tag("weekly");Text("每月").tag("monthly");Text("每年").tag("yearly")};Picker("优先级",selection:$priority) {Text("低").tag(0);Text("普通").tag(1);Text("高").tag(2)};Toggle("暂停提醒",isOn:$paused)}
    }.navigationTitle(reminder==nil ? "新建提醒":"编辑提醒").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("保存") {save()}.disabled(store.busy)}}.onAppear {if let r=reminder {title=r.text("title");bodyText=r.text("body");date=Date(timeIntervalSince1970:Double(r.int("due"))/1000);period=r.text("period",fallback:"none");priority=Int(r.int("priority",fallback:1));paused=r.bool("paused")}}
    }
    func save() {guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {store.error="请填写提醒内容";return};var r=reminder ?? Item.make(["kind":.string("reminder"),"date":.int(Clock.milliseconds)]);r.set("title",title);r.set("body",bodyText);r.set("due",Int64(date.timeIntervalSince1970*1000));r.set("alertAt",Int64(date.timeIntervalSince1970*1000));r.set("period",period);r.set("priority",Int64(priority));r.set("paused",paused);r.set("currency",store.currency);r.set("zone",TimeZone.current.identifier);r.set("interval",Int64(24));r.set("anchorDay",Int64(Calendar.current.component(.day,from:date)));r.set("anchorMonth",Int64(Calendar.current.component(.month,from:date)));Task {if await store.commit({$0.upsert(r,in:"records")}) {if await NotificationService.request() {NotificationService.sync(store.current.records)};dismiss()}}}
}

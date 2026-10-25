import UIKit
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import CoreFoundation

struct SettingsView:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    @State var deleting=false
    var body:some View {List {
        Section {NavigationLink {ProfileView()} label:{HStack(spacing:14) {ProfilePortrait(size:52);VStack(alignment:.leading,spacing:5) {Text("个人头像").font(.headline).foregroundStyle(.primary);Text("点击更换头像").font(.caption).foregroundStyle(.secondary)}}.padding(.vertical,8)}}
        Section("智能助理") {
            NavigationLink {CloudSettingsView()} label:{Label("云端智能",systemImage:"cloud")}
            NavigationLink {LocalModelView()} label:{Label("本机智能",systemImage:"cpu")}
            NavigationLink {MemoryView()} label:{Label("助理记忆",systemImage:"bubble.left.and.bubble.right")}
        }
        Section("个性化") {
            NavigationLink {AppearanceView()} label:{Label("外观与图标",systemImage:"paintpalette")}
            Picker("默认币种",selection:Binding(get:{store.currency},set:{v in Task {await store.setting("currency",.string(v))}})) {ForEach(Money.currencies,id:\.self) {Text($0).tag($0)}}
        }
        Section("资料与安全") {
            NavigationLink {VaultCapacityView()} label:{Label("资料库容量",systemImage:"internaldrive")}
            NavigationLink {BackupView()} label:{Label("加密备份与恢复",systemImage:"externaldrive")}
            NavigationLink {ImportExportView()} label:{Label("账单导入与导出",systemImage:"arrow.down.doc")}
            Toggle("Face ID / 系统解锁",isOn:Binding(get:{store.biometricEnabled},set:{v in Task {await store.setBiometric(v)}}))
            Button("开启提醒通知",systemImage:"bell") {Task {if await NotificationService.request() {NotificationService.sync(store.current.records)}else{store.error="请到 iOS 设置中允许本应用发送通知"}}}
            Button("锁定资料库",systemImage:"lock") {dismiss();store.lock()}
        }
        Section {NavigationLink("关于个人助理",destination:AboutView())}
    }.navigationTitle("个人详情").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.confirmationAction) {Button("完成") {dismiss()}}}.appErrorScope()}
}

struct VaultCapacityView:View {
    @EnvironmentObject var store:AppStore
    var body:some View {Form {
        Section {
            ProgressView(value:Double(min(store.vaultBytes,VaultCrypto.maximum)),total:Double(VaultCrypto.maximum)).tint(store.vaultBytes>VaultCrypto.maximum*4/5 ? .orange:Theme.accent)
            LabeledContent("已使用",value:VaultCrypto.capacityLabel(store.vaultBytes)).accessibilityIdentifier("vault.capacity.used")
            LabeledContent("可用容量",value:VaultCrypto.capacityLabel(VaultCrypto.maximum-store.vaultBytes))
            LabeledContent("容量上限",value:VaultCrypto.capacityLabel(VaultCrypto.maximum))
        } header:{Text("笔记与财务资料")} footer:{Text("显示上次成功保存的加密资料大小，包含笔记、图片、手绘、账户和账本；聊天记录独立保存。附件经过编码后会占用更多容量。")}
        if store.vaultBytes>=VaultCrypto.maximum*4/5 {Section {Label("容量即将用满",systemImage:"exclamationmark.circle").foregroundStyle(.orange);Text("建议先导出备份，再缩小图片或移除不需要的附件。超过上限时会保留原资料，当前编辑内容仍留在页面中。").font(.subheadline)}}
        Section {NavigationLink("导出加密备份",destination:BackupView())}
    }.navigationTitle("资料库容量").navigationBarTitleDisplayMode(.inline).appErrorScope()}
}

struct CloudSettingsView:View {
    @EnvironmentObject var store:AppStore
    @State var key=""
    @State var models=["deepseek-flash","deepseek-v4-pro"]
    @State var custom=""
    @State var fetching=false
    @State var notice=false
    var body:some View {Form {
        Section {Toggle("使用云端智能",isOn:Binding(get:{store.cloudEnabled},set:{v in if v {notice=true}else{Task {await store.setting("cloudEnabled",.bool(false))}}}))} footer:{Text("开启后，问题、近期对话及财务咨询所需资料会原文发送至 DeepSeek；关闭后使用本机智能。")}
        Section("DeepSeek") {
            SecureField(store.hasAPIKey ? "已保存密钥；输入新密钥可替换":"输入 API Key",text:$key).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("保存密钥") {store.setAPIKey(key);key=""}
            if store.hasAPIKey {Button("删除密钥",role:.destructive) {store.setAPIKey("")}}
            Link("注册 DeepSeek / 获取 API Key",destination:URL(string:"https://platform.deepseek.com/api_keys")!)
        }
        Section("聊天模型") {
            Picker("模型",selection:Binding(get:{store.model},set:{v in Task {await store.setting("model",.string(v))}})) {ForEach(models,id:\.self) {Text($0).tag($0)}}
            Button {fetching=true;Task {defer{fetching=false};do {models=try await AIService.models();if !models.contains(store.model),let first=models.first {await store.setting("model",.string(first))}}catch{store.present(error)}}} label:{HStack {Text("刷新可用模型");if fetching {ProgressView()}}}.disabled(fetching || !store.hasAPIKey)
            TextField("自定义模型 ID",text:$custom).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("使用此模型") {let value=custom.trimmingCharacters(in:.whitespacesAndNewlines);guard !value.isEmpty else{return};if !models.contains(value) {models.append(value)};Task {await store.setting("model",.string(value))}}
        }
    }.navigationTitle("云端智能").navigationBarTitleDisplayMode(.inline).appErrorScope().onAppear {if !models.contains(store.model) {models.append(store.model)}}
        .alert("开启云端智能？",isPresented:$notice) {Button("取消",role:.cancel) {};Button("开启") {Task {await store.setting("cloudEnabled",.bool(true));await store.setting("cloudNoticeSeen",.bool(true))}}} message:{Text("消息、近期对话，以及财务咨询使用的金额和明细将原文发送至 DeepSeek。")}
    }
}

struct LocalModelView:View {
    @EnvironmentObject var store:AppStore
    @StateObject var download=ModelDownload()
    @State var importing=false
    @State var installed=LocalModel.shared.available
    @State var checking=false
    var body:some View {Form {
        Section {HStack {Image(systemName:"cpu").font(.title2).foregroundStyle(Theme.accent);VStack(alignment:.leading,spacing:5) {Text("千问 · Qwen2.5").font(.headline);Text("1.5B · Q4_K_M").font(.caption).foregroundStyle(.secondary)};Spacer();if installed {Image(systemName:"checkmark.circle.fill").foregroundStyle(Theme.income)}}}
        Section {
            if download.running || checking {VStack(alignment:.leading,spacing:8) {Text(checking ? "校验导入文件":download.stage).font(.subheadline);ProgressView(value:download.progress).tint(Theme.accent);if download.running {Button("取消下载",role:.cancel) {download.cancel()}}}}
            else if installed {Button("删除模型",role:.destructive) {Task {do {try await LocalModel.shared.remove();installed=false}catch{store.present(error)}}}}
            else {Button("下载模型（约 1.12 GB）") {download.start()};Button("导入 GGUF 文件") {importing=true}}
        } footer:{Text("本机模型使用 Metal 加速；运行速度取决于 iPhone 型号、内存及温度。下载时请保持应用在前台。")}
        Section("语音") {Label("使用 iPhone 系统离线普通话识别",systemImage:"waveform");Text("首次使用会申请麦克风和语音识别权限。离线资源和支持情况由 iOS 管理。").font(.caption).foregroundStyle(.secondary)}
    }.navigationTitle("本机智能").navigationBarTitleDisplayMode(.inline).appErrorScope()
        .onChange(of:download.running) {_,running in if !running {installed=LocalModel.shared.available}}
        .onChange(of:download.error) {_,error in if let error {store.error=error;download.error=nil}}
        .fileImporter(isPresented:$importing,allowedContentTypes:[.data,.item]) {result in do {let url=try result.get();let access=url.startAccessingSecurityScopedResource();checking=true;Task {defer{if access {url.stopAccessingSecurityScopedResource()};checking=false};do {try await Task.detached {try LocalModel.shared.install(url)}.value;installed=true}catch{store.present(error)}}}catch{store.present(error)}}
    }
}

struct AppearanceView:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.colorScheme) var scheme
    @State var iconError:String?
    var body:some View {Form {
        Picker("外观",selection:Binding(get:{store.appearance.rawValue},set:{store.selectAppearance($0)})) {Text("跟随系统").tag("system");Text("浅色").tag("light");Text("纯黑深色").tag("dark")}.accessibilityIdentifier("appearance.mode")
        Section("应用图标") {HStack(spacing:18) {icon("Sunshine",nil);icon("Sky","AppIconSky");icon("Peach","AppIconPeach")}.padding(.vertical,8)}
        Section {Text("字体会响应 iOS 的文字大小与辅助功能设置。").font(.caption).foregroundStyle(.secondary)}
    }.scrollContentBackground(.hidden).background(Theme.background(scheme)).accessibilityIdentifier("appearance.form")
        .navigationTitle("外观与图标").navigationBarTitleDisplayMode(.inline)}
    func icon(_ name:String,_ alternate:String?)->some View {Button {UIApplication.shared.setAlternateIconName(alternate) {error in if let error {Task {@MainActor in store.present(error)}}else{UserDefaults.standard.set(name,forKey:"appIcon")}}} label:{Image("Launcher"+name).resizable().scaledToFit().frame(width:64,height:64).clipShape(RoundedRectangle(cornerRadius:15))}.buttonStyle(.plain).accessibilityLabel(name+"图标")}
}

struct MemoryView:View {
    @EnvironmentObject var store:AppStore
    @State var adding=false
    @State var editing:Item?
    @State var text=""
    @State var kind="preference"
    var memory:Item {Item(store.current.root.raw["assistantMemory"]?.object ?? [:])}
    var body:some View {List {
        Toggle("使用助理记忆",isOn:Binding(get:{memory.bool("enabled",fallback:true)},set:{v in Task {await store.commit {d in var m=Item(d.root.raw["assistantMemory"]?.object ?? [:]);m.set("enabled",v);d.root.raw["assistantMemory"] = .object(m.raw)}}}))
        if memory.items("facts").isEmpty {EmptyState(icon:"bubble.left.and.bubble.right",title:"记住对你重要的事",subtitle:"保存城市、目标或偏好，让建议更贴合你").listRowBackground(Color.clear).listRowSeparator(.hidden)}
        ForEach(memory.items("facts")) {f in Button {editing=f;text=f.text("text");kind=f.text("kind",fallback:"preference");adding=true} label:{VStack(alignment:.leading,spacing:5) {Text(f.text("text")).foregroundStyle(.primary);Text(label(f.text("kind"))).font(.caption).foregroundStyle(.secondary)}}.swipeActions {Button(role:.destructive) {Task {await store.commit {d in var m=Item(d.root.raw["assistantMemory"]?.object ?? [:]);m.set("facts",items:m.items("facts").filter {$0.id != f.id});d.root.raw["assistantMemory"] = .object(m.raw)}}} label:{Label("删除",systemImage:"trash")}}}
    }.navigationTitle("助理记忆").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.topBarTrailing) {Button {editing=nil;text="";kind="preference";adding=true} label:{Image(systemName:"plus")}.accessibilityLabel("添加记忆")}}
        .sheet(isPresented:$adding) {NavigationStack {Form {Picker("类型",selection:$kind) {ForEach(["preference","locality","goal","income_cycle","situation"],id:\.self) {Text(label($0)).tag($0)}};TextField("希望助理记住什么",text:$text,axis:.vertical).lineLimit(3...8)}.navigationTitle(editing==nil ? "添加记忆":"编辑记忆").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {adding=false}};ToolbarItem(placement:.confirmationAction) {Button("保存") {guard !text.isEmpty,text.count<=500 else {store.error="记忆内容请填写1至500字";return};var fact=editing ?? Item.make();fact.set("text",text);fact.set("kind",kind);fact.set("updatedAt",Clock.milliseconds);if fact.int("createdAt")==0 {fact.set("createdAt",Clock.milliseconds)};Task {if await store.commit({d in var m=Item(d.root.raw["assistantMemory"]?.object ?? [:]);var facts=m.items("facts");facts.removeAll {$0.id==fact.id};guard facts.count<100 else{throw AppError.message("记忆过多，请先清理")};facts.append(fact);m.set("facts",items:facts);d.root.raw["assistantMemory"] = .object(m.raw)}) {adding=false}}}}}}.appErrorScope()}
    }
    func label(_ kind:String)->String { ["preference":"偏好","locality":"所在城市","goal":"财务目标","income_cycle":"收入周期","situation":"生活情况"][kind] ?? "偏好" }
}

struct AboutView:View {
    var body:some View {List {
        Section("个人助理 · iOS 3.5.1 (8)") {Text("记录生活，理清财务。为 iPhone 设计的笔记、账本与智能助理。")}
        Section("使用与隐私") {
            Text("笔记、账本和个人头像在本机加密保存。请定期导出加密备份，并妥善保管资料库密码。")
            Text("卡包展示你记录的账户与交易，余额随账本更新，不连接银行账户或提供支付服务。")
            Text("云端智能可在设置中关闭；开启后，问题及相关资料会发送至 DeepSeek。")
            Text("安装更新时请使用同一签名与应用标识，以保留本机资料。")
        }
        Section {Link("llama.cpp 开源许可",destination:URL(string:"https://github.com/ggml-org/llama.cpp/blob/master/LICENSE")!)}
    }.navigationTitle("关于").navigationBarTitleDisplayMode(.inline)}
}

struct DataFile:FileDocument {
    static var readableContentTypes:[UTType] {[.data,.commaSeparatedText,.plainText]}
    var data:Data
    init(data:Data) {self.data=data}
    init(configuration:ReadConfiguration) throws {data=configuration.file.regularFileContents ?? Data()}
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper {FileWrapper(regularFileWithContents:data)}
}
struct BackupView:View {
    @EnvironmentObject var store:AppStore
    @State var importing=false
    @State var exporting=false
    @State var restore=false
    @State var confirm=false
    @State var bytes=Data()
    @State var password=""
    @State var file=DataFile(data:Data())
    var body:some View {Form {
        Section {Button("导出完整加密备份",systemImage:"square.and.arrow.up") {Task {do {file=DataFile(data:try await store.backup());exporting=true}catch{store.present(error)}}};Button("从完整备份恢复",systemImage:"square.and.arrow.down") {importing=true}}
        Section {Text("备份使用当前资料库密码加密。恢复将替换当前笔记、账本、账户等资料，请先导出当前备份。").font(.caption).foregroundStyle(.secondary)}
    }.navigationTitle("加密备份与恢复").navigationBarTitleDisplayMode(.inline).appErrorScope()
        .fileExporter(isPresented:$exporting,document:file,contentType:.data,defaultFilename:"PersonalAssistant-\(Clock.day()).pavault") {result in if case .failure(let error)=result {store.present(error)}}
        .fileImporter(isPresented:$importing,allowedContentTypes:[.data,.item]) {result in do {let url=try result.get();let access=url.startAccessingSecurityScopedResource();defer{if access {url.stopAccessingSecurityScopedResource()}};bytes=try PrivateFiles.boundedRead(url);_=try VaultCrypto.salt(bytes);restore=true}catch{store.present(error)}}
        .alert("输入备份密码",isPresented:$restore) {SecureField("备份原密码",text:$password);Button("取消",role:.cancel) {password="";bytes=Data()};Button("继续") {confirm=true}} message:{Text("请填写导出这份备份时使用的密码；当前资料库密码不会改变。")}
        .confirmationDialog("恢复将替换当前资料，确定继续？",isPresented:$confirm,titleVisibility:.visible) {Button("恢复并替换",role:.destructive) {Task {if await store.importBackup(bytes,password:password) {store.error="备份已恢复"};password="";bytes=Data()}};Button("取消",role:.cancel) {password="";bytes=Data()}}
    }
}

struct ImportExportView:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) var dismiss
    @State var importing=false
    @State var exporting=false
    @State var review=false
    @State var accountID=""
    @State var drafts:[Item]=[]
    @State var file=DataFile(data:Data())
    var body:some View {Form {
        Section("导入账单") {Picker("入账账户",selection:$accountID) {Text("请选择").tag("");ForEach(store.current.accounts.filter {!$0.bool("archived")}) {Text($0.text("name")+" · "+$0.text("currency",fallback:"CNY")).tag($0.id)}};Button("选择 CSV 文件") {importing=true}.disabled(accountID.isEmpty)}
        Section("导出") {Button("导出全部流水 CSV") {file=DataFile(data:Data(CSV.export(store.current.records,document:store.current).utf8));exporting=true}}
        Section {Text("导入前会展示草稿，核对后才保存。退款、失败和中性交易不会自动计入收支，请通过原支出关联处理退款。").font(.caption).foregroundStyle(.secondary)}
    }.navigationTitle("账单导入与导出").navigationBarTitleDisplayMode(.inline).appErrorScope()
        .toolbar {ToolbarItem(placement:.confirmationAction) {Button("完成") {dismiss()}}}
        .fileExporter(isPresented:$exporting,document:file,contentType:.commaSeparatedText,defaultFilename:"Ledger-\(Clock.day()).csv") {r in if case .failure(let e)=r {store.present(e)}}
        .fileImporter(isPresented:$importing,allowedContentTypes:[.commaSeparatedText,.plainText,.data]) {result in do {
            let url=try result.get(),access=url.startAccessingSecurityScopedResource();defer{if access {url.stopAccessingSecurityScopedResource()}}
            let data=try PrivateFiles.boundedRead(url,maximum:12*1024*1024)
            guard let text=String(data:data,encoding:.utf8) ?? String(data:data,encoding:String.Encoding(rawValue:CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))) else {throw AppError.message("文件编码无法识别，请导出 UTF-8 CSV")}
            guard let a=store.current.accounts.first(where:{$0.id==accountID}) else {throw AppError.message("请先选择入账账户")}
            drafts=try CSV.drafts(text,account:a).map {r in var next=r;let source=a.id+"|"+r.text("original");next.set("importKey",SHA256.hash(data:Data(source.utf8)).map {String(format:"%02x",$0)}.joined());next.set("original","");return next}.filter {r in !store.current.records.contains {$0.id==r.id || $0.text("importKey")==r.text("importKey")}}
            if drafts.isEmpty {store.error="没有可导入的新流水，请核对文件或重复记录"}else{review=true}
        }catch{store.present(error)}}
        .sheet(isPresented:$review) {NavigationStack {List {Section {Text("待导入 \(drafts.count) 笔，请逐项核对账户、金额与日期。").font(.caption)};ForEach(drafts) {RecordRow(record:$0,document:store.current)}.onDelete {drafts.remove(atOffsets:$0)}}.navigationTitle("核对导入草稿").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {review=false;drafts=[]}};ToolbarItem(placement:.confirmationAction) {Button("确认导入") {Task {if await store.commit({$0.records+=drafts}) {review=false;drafts=[]}}}.disabled(store.busy)}}}.environmentObject(store).appErrorScope()}
    }
}

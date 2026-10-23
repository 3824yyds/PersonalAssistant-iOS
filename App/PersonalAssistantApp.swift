import UIKit
import SwiftUI

@main struct PersonalAssistantApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var phase
    @State private var backgroundAt: Date?
    var body: some Scene {
        WindowGroup {
            Group { if store.document != nil { MainTabs() } else { UnlockView() } }
                .environmentObject(store).tint(Theme.accent).preferredColorScheme(store.theme)
                .alert("提示",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error=nil}})) { Button("知道了",role:.cancel) {store.error=nil} } message: {Text(store.error ?? "")}
                .onChange(of:phase) { _,next in
                    if next == .background { backgroundAt = Date(); store.speech?.cancel(); store.activeTask?.cancel() }
                    if next == .active, let date = backgroundAt, Date().timeIntervalSince(date)>60 { store.lock(); backgroundAt=nil }
                }
        }
    }
}

enum RootSheet: String, Identifiable { case note, entry, reminder, wallet, profile; var id:String {rawValue} }
struct MainTabs: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var tab = 0
    @State var expanded = false
    @State var sheet: RootSheet?
    let tabs = [("笔记","note.text"),("账本","book.closed"),("提醒","bell"),("助理","bubble.left.and.bubble.right")]
    var body: some View {
        ZStack {
            Theme.background(scheme).ignoresSafeArea()
            TabView(selection:$tab) {
                NavigationStack { NotesView().toolbar { ToolbarControls(sheet:$sheet) } }.tag(0)
                NavigationStack { LedgerView().toolbar { ToolbarControls(sheet:$sheet) } }.tag(1)
                NavigationStack { RemindersView().toolbar { ToolbarControls(sheet:$sheet) } }.tag(2)
                NavigationStack { ConversationView().toolbar { ToolbarControls(sheet:$sheet) } }.tag(3)
            }.toolbar(.hidden,for:.tabBar)
            if expanded { Color.black.opacity(0.14).ignoresSafeArea().onTapGesture { animate { expanded=false } } }
        }
        .safeAreaInset(edge:.bottom,spacing:0) {
            HStack(spacing:0) {
                ForEach(0..<tabs.count,id:\.self) { i in
                    Button { expanded=false; tab=i } label: {
                        VStack(spacing:4) { Image(systemName:tabs[i].1).font(.system(size:18)); Text(tabs[i].0).font(.system(size:10,weight:tab==i ? .semibold:.regular)) }.frame(maxWidth:.infinity,minHeight:46).foregroundStyle(tab==i ? Theme.accent:.secondary)
                    }.buttonStyle(.plain).accessibilityAddTraits(tab==i ? .isSelected:[])
                }
                Button { animate { expanded.toggle() }; UIImpactFeedbackGenerator(style:.light).impactOccurred() } label: {
                    Image(systemName:"plus").font(.system(size:22,weight:.regular)).rotationEffect(.degrees(expanded ? 45:0)).frame(width:44,height:44).background(Theme.accent,in:Circle()).foregroundStyle(.white)
                }.buttonStyle(.plain).accessibilityLabel(expanded ? "收起快捷操作":"展开快捷操作").padding(.leading,8).padding(.trailing,16)
            }.padding(.vertical,6).background(Theme.panel(scheme))
                .overlay(alignment:.bottomTrailing) {
                    if expanded {
                        VStack(spacing:10) {
                            quick("note.text","新建笔记",.note)
                            quick("plus.forwardslash.minus","记一笔",.entry)
                            quick("bell","新建提醒",.reminder)
                        }.padding(.trailing,16).padding(.bottom,66).transition(.asymmetric(insertion:.move(edge:.bottom).combined(with:.opacity),removal:.opacity))
                    }
                }
        }
        .sheet(item:$sheet) { value in
            NavigationStack {
                switch value { case .note:NoteEditor();case .entry:RecordEditor();case .reminder:ReminderEditor();case .wallet:WalletView();case .profile:SettingsView() }
            }.environmentObject(store).interactiveDismissDisabled(store.busy)
        }
    }
    func quick(_ icon:String,_ title:String,_ target:RootSheet)->some View {
        Button { expanded=false; sheet=target } label: {Image(systemName:icon).font(.system(size:19,weight:.regular)).frame(width:44,height:44).background(Theme.panel(scheme),in:Circle()).foregroundStyle(Theme.accent).shadow(color:.black.opacity(0.08),radius:8,y:2)}.buttonStyle(.plain).accessibilityLabel(title)
    }
    func animate(_ body:()->Void) { withAnimation(reduceMotion ? nil:Theme.normal,body) }
}

struct UnlockView: View {
    @EnvironmentObject var store: AppStore
    @State var password = ""
    @State var confirmation = ""
    @State var showPassword = false
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("LoginWallpaper").resizable().scaledToFill().frame(width:proxy.size.width,height:proxy.size.height).clipped().ignoresSafeArea()
                ScrollView {
                    VStack(spacing:14) {
                        Spacer(minLength:proxy.size.height*0.34)
                        if !store.hasVault { Text("创建你的私人资料库").font(.headline).foregroundStyle(.black.opacity(0.8)) }
                        SecureField(store.hasVault ? "资料库密码":"设置密码（至少12个字符）",text:$password).textContentType(store.hasVault ? .password:.newPassword).padding(14).background(.white.opacity(0.88),in:RoundedRectangle(cornerRadius:14)).foregroundStyle(.black)
                        if !store.hasVault { SecureField("再次输入密码",text:$confirmation).textContentType(.newPassword).padding(14).background(.white.opacity(0.88),in:RoundedRectangle(cornerRadius:14)).foregroundStyle(.black) }
                        Button {
                            if !store.hasVault && password != confirmation { store.error="两次密码不一致"; return }
                            Task { await store.unlock(password:password,creating:!store.hasVault); password="";confirmation="" }
                        } label: { HStack { if store.busy {ProgressView().tint(.white)};Text(store.hasVault ? "解锁":"创建资料库").fontWeight(.semibold) }.frame(maxWidth:.infinity).padding(14) }.buttonStyle(.borderedProminent).disabled(store.busy || password.isEmpty)
                        if store.hasVault && store.biometricEnabled { Button("使用 Face ID / 系统解锁") { Task {await store.unlockBiometric()} }.foregroundStyle(.black.opacity(0.75)).padding(8) }
                        if !store.hasVault { Text("密码用于加密备份，请妥善保存。创建后可在个人详情导入 Android 完整备份。").font(.caption).foregroundStyle(.black.opacity(0.6)).multilineTextAlignment(.center) }
                    }.padding(.horizontal,32).padding(.bottom,80).frame(minHeight:proxy.size.height)
                }.scrollDismissesKeyboard(.interactively)
            }
        }
    }
}

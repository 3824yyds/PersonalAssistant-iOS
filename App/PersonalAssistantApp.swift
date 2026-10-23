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
                    if next == .background { backgroundAt = Date(); store.speech?.cancel();store.voiceCapture=nil;store.activeTask?.cancel() }
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
    @StateObject private var keyboard = KeyboardVisibility()
    let tabs = [("笔记","note.text"),("账本","book.closed"),("提醒","bell"),("助理","bubble.left.and.bubble.right")]
    var body: some View {
        ZStack {
            Theme.background(scheme).ignoresSafeArea()
            VStack(spacing:0) {
            ZStack {
            // One navigation container avoids TabView applying keyboard insets a second time.
            NavigationStack {
                Group {
                    switch tab {
                    case 1: LedgerView()
                    case 2: RemindersView()
                    case 3: ConversationView()
                    default: NotesView()
                    }
                }.toolbar { ToolbarControls(sheet:$sheet) }
            }.id(tab)
            if expanded { Color.black.opacity(0.14).ignoresSafeArea().onTapGesture { animate { expanded=false } } }
            }
            if !keyboard.visible {
            HStack(spacing:0) {
                ForEach(0..<tabs.count,id:\.self) { i in
                    Button { expanded=false; tab=i } label: {
                        VStack(spacing:4) { Image(systemName:tabs[i].1).font(.system(size:18)); Text(tabs[i].0).font(.system(size:10,weight:tab==i ? .semibold:.regular)) }.frame(maxWidth:.infinity,minHeight:46).foregroundStyle(tab==i ? Theme.accent:.secondary)
                    }.buttonStyle(.plain).accessibilityAddTraits(tab==i ? .isSelected:[])
                }
                Button { animate { expanded.toggle() }; UIImpactFeedbackGenerator(style:.light).impactOccurred() } label: {
                    Image(systemName:"plus").font(.system(size:22,weight:.regular)).rotationEffect(.degrees(expanded ? 45:0)).frame(width:44,height:44).appGlass(Circle(),interactive:true,tinted:true).foregroundStyle(.white)
                }.buttonStyle(.plain).accessibilityLabel(expanded ? "收起快捷操作":"展开快捷操作").padding(.leading,8).padding(.trailing,16)
            }.padding(.vertical,6).padding(.leading,8).appGlass(Capsule())
                .overlay(alignment:.bottomTrailing) {
                    if expanded {
                        AppGlassGroup {VStack(spacing:10) {
                            quick("note.text","新建笔记",.note)
                            quick("plus.forwardslash.minus","记一笔",.entry)
                            quick("bell","新建提醒",.reminder)
                        }}.padding(.trailing,16).padding(.bottom,66).transition(.asymmetric(insertion:.move(edge:.bottom).combined(with:.opacity),removal:.opacity))
                    }
                }
                .padding(.horizontal,12).padding(.bottom,4)
            }
            }
            if let voice=store.voiceCapture,let speech=store.speech {VoiceCaptureOverlay(speech:speech,state:voice).ignoresSafeArea().allowsHitTesting(false).zIndex(2)}
        }
        .onChange(of:keyboard.visible) { _,visible in if visible {expanded=false} }
        .sheet(item:$sheet) { value in
            NavigationStack {
                switch value { case .note:NoteEditor();case .entry:RecordEditor();case .reminder:ReminderEditor();case .wallet:WalletView();case .profile:SettingsView() }
            }.environmentObject(store).interactiveDismissDisabled(store.busy)
        }
    }
    func quick(_ icon:String,_ title:String,_ target:RootSheet)->some View {
        Button { expanded=false; sheet=target } label: {Image(systemName:icon).font(.system(size:19,weight:.regular)).frame(width:44,height:44).appGlass(Circle(),interactive:true).foregroundStyle(Theme.accent)}.buttonStyle(.plain).accessibilityLabel(title)
    }
    func animate(_ body:()->Void) { withAnimation(reduceMotion ? nil:Theme.normal,body) }
}

struct UnlockView: View {
    @EnvironmentObject var store: AppStore
    @State var password = ""
    @State var confirmation = ""
    @FocusState private var passwordFocused: Bool
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Paint the physical screen, including both safe areas; the form alone avoids the keyboard.
                GeometryReader { background in
                    Image("LoginWallpaper").resizable().scaledToFill()
                        .frame(width:background.size.width,height:background.size.height).clipped()
                }.ignoresSafeArea().accessibilityIdentifier("unlock.wallpaper")
                ScrollView {
                    VStack(spacing:14) {
                        Spacer(minLength:passwordFocused ? 24:max(24,proxy.size.height*0.28))
                        if !store.hasVault { Text("创建你的私人资料库").font(.headline).foregroundStyle(.black.opacity(0.8)) }
                        SecureField(store.hasVault ? "资料库密码":"设置密码（至少12个字符）",text:$password).textContentType(store.hasVault ? .password:.newPassword).focused($passwordFocused).padding(14).background(.white.opacity(0.92),in:RoundedRectangle(cornerRadius:14)).foregroundStyle(.black)
                        if !store.hasVault { SecureField("再次输入密码",text:$confirmation).textContentType(.newPassword).focused($passwordFocused).padding(14).background(.white.opacity(0.92),in:RoundedRectangle(cornerRadius:14)).foregroundStyle(.black) }
                        Button {
                            if !store.hasVault && password != confirmation { store.error="两次密码不一致"; return }
                            Task { await store.unlock(password:password,creating:!store.hasVault); password="";confirmation="" }
                        } label: { HStack { if store.busy {ProgressView().tint(.white)};Text(store.hasVault ? "解锁":"创建资料库").fontWeight(.semibold) }.frame(maxWidth:.infinity).padding(14).foregroundStyle(password.isEmpty ? Color.black.opacity(0.4):.white).background(password.isEmpty ? Color.white.opacity(0.65):Theme.accent,in:RoundedRectangle(cornerRadius:14)) }.buttonStyle(.plain).disabled(store.busy || password.isEmpty)
                        if store.hasVault {Button {
                            if store.biometricEnabled {Task {await store.unlockBiometric()}}
                            else {store.error="请先使用密码解锁，再到个人详情启用 Face ID / 系统解锁"}
                        } label:{VStack(spacing:6) {Image(systemName:"faceid").font(.system(size:28,weight:.regular)).frame(width:58,height:58).appGlass(Circle(),interactive:true);Text("Face ID 解锁").font(.caption)}}.buttonStyle(.plain).foregroundStyle(.black.opacity(0.8)).accessibilityLabel("Face ID 解锁").disabled(store.busy).padding(.top,4)}
                        if !store.hasVault { Text("密码用于加密备份，请妥善保存。请定期在个人详情导出加密备份。").font(.caption).foregroundStyle(.black.opacity(0.6)).multilineTextAlignment(.center) }
                    }.padding(.horizontal,32).padding(.bottom,32).frame(minHeight:proxy.size.height,alignment:.bottom)
                }.scrollDismissesKeyboard(.interactively)
            }
        }
    }
}

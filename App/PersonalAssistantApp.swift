import UIKit
import SwiftUI

@main struct PersonalAssistantApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var phase
    @State private var backgroundAt: Date?
    init() {
        // The page paints behind the floating controls, including scrolled bar states.
        let navigation=UINavigationBarAppearance();navigation.configureWithTransparentBackground()
        navigation.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance=navigation
        UINavigationBar.appearance().scrollEdgeAppearance=navigation
        UINavigationBar.appearance().compactAppearance=navigation
        UINavigationBar.appearance().compactScrollEdgeAppearance=navigation
        let toolbar=UIToolbarAppearance();toolbar.configureWithTransparentBackground()
        toolbar.shadowColor = .clear
        UIToolbar.appearance().standardAppearance=toolbar
        UIToolbar.appearance().scrollEdgeAppearance=toolbar
    }
    var body: some Scene {
        WindowGroup {
            Group { if store.document != nil { MainTabs() } else { UnlockView() } }
                .environmentObject(store).tint(Theme.accent)
                .background {AppearanceWindow(appearance:store.document==nil ? .light:store.appearance).frame(width:0,height:0).allowsHitTesting(false)}
                .alert("提示",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error=nil}})) { Button("知道了",role:.cancel) {store.error=nil} } message: {Text(store.error ?? "")}
                .onChange(of:phase) { _,next in
                    if next == .background { backgroundAt = Date(); store.speech?.cancel();store.voiceCapture=nil;store.cancelReply() }
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
    @State private var previousTab=0
    @State var expanded = false
    @State var sheet: RootSheet?
    @StateObject private var keyboard = KeyboardVisibility()
    var body: some View {
        ZStack(alignment:.bottomTrailing) {
            Theme.background(scheme).ignoresSafeArea().allowsHitTesting(false)
            if tab==3 {ConversationBackground().ignoresSafeArea().allowsHitTesting(false)}
            // Reserve room for the capsule without creating a separate footer surface.
            NavigationStack {
                Group {
                    switch tab {
                    case 1: LedgerView()
                    case 2: RemindersView()
                    case 3: ConversationView(onBack:{tab=previousTab})
                    default: NotesView()
                    }
                }.appClearChrome().toolbar {ToolbarControls(sheet:$sheet)}
            }.id(tab)
                .safeAreaInset(edge:.bottom,spacing:0) {
                    if !keyboard.visible && tab != 3 {Color.clear.frame(height:60).allowsHitTesting(false)}
                }
            if expanded {
                Color.black.opacity(0.14).ignoresSafeArea().contentShape(Rectangle())
                    .onTapGesture {animate {expanded=false}}
            }
            if !keyboard.visible && tab != 3 {MainNavigation(selection:$tab,expanded:$expanded)}
            if expanded && !keyboard.visible {
                AppGlassGroup {VStack(spacing:10) {
                    quick("note.text","新建笔记",.note)
                    quick("plus.forwardslash.minus","记一笔",.entry)
                    quick("bell","新建提醒",.reminder)
                }}.padding(.trailing,24).padding(.bottom,70)
                    .transition(.asymmetric(insertion:.move(edge:.bottom).combined(with:.opacity),removal:.opacity))
                    .zIndex(1)
            }
            if let voice=store.voiceCapture,let speech=store.speech {VoiceCaptureOverlay(speech:speech,state:voice).ignoresSafeArea().allowsHitTesting(false).zIndex(2)}
        }
        .onChange(of:keyboard.visible) { _,visible in if visible {expanded=false} }
        .onChange(of:tab) {old,new in if new==3 && old != 3 {previousTab=old}}
        .sheet(item:$sheet) { value in
            NavigationStack {
                switch value { case .note:NoteEditor();case .entry:RecordEditor();case .reminder:ReminderEditor();case .wallet:WalletView();case .profile:SettingsView() }
            }.appClearChrome().environmentObject(store).interactiveDismissDisabled(store.busy)
        }
    }
    @ViewBuilder func quick(_ icon:String,_ title:String,_ target:RootSheet)->some View {
        if #available(iOS 26.0,*) {
            Button {openQuick(target)} label:{Image(systemName:icon).font(.system(size:19,weight:.regular)).frame(width:24,height:24)}
                .buttonStyle(.glass).buttonBorderShape(.circle).frame(width:44,height:44).contentShape(Circle()).accessibilityLabel(title)
        } else {
            Button {openQuick(target)} label:{Image(systemName:icon).font(.system(size:19,weight:.regular)).frame(width:44,height:44).appGlass(Circle(),interactive:true).foregroundStyle(Theme.accent)}.buttonStyle(.plain).accessibilityLabel(title)
        }
    }
    func openQuick(_ target:RootSheet) {
        expanded=false
        // Finish removing the glass action surface before UIKit presents the editor sheet.
        Task {try? await Task.sleep(nanoseconds:120_000_000);sheet=target}
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
                    VStack(spacing:0) {
                        Color.clear.frame(height:passwordFocused ? 24:proxy.size.height*0.36).accessibilityHidden(true)
                    VStack(spacing:12) {
                        if !store.hasVault {Text("创建你的私人资料库").font(.headline).foregroundStyle(.black.opacity(0.8)).padding(.bottom,8)}
                        passwordField(store.hasVault ? "资料库密码":"设置密码（至少12个字符）",text:$password,confirmation:false)
                        if !store.hasVault {passwordField("再次输入密码",text:$confirmation,confirmation:true)}
                        Button {
                            if !store.hasVault && password != confirmation { store.error="两次密码不一致"; return }
                            Task { await store.unlock(password:password,creating:!store.hasVault); password="";confirmation="" }
                        } label: { HStack { if store.busy {ProgressView().tint(.white)};Text(store.hasVault ? "解锁":"创建资料库").fontWeight(.semibold) }.frame(maxWidth:.infinity,minHeight:48).foregroundStyle(password.isEmpty ? Color.black.opacity(0.48):.white).background(password.isEmpty ? Color.white.opacity(0.72):Theme.accent,in:RoundedRectangle(cornerRadius:16)) }.buttonStyle(.plain).disabled(store.busy || password.isEmpty)
                        if store.hasVault {Button {
                            if store.biometricEnabled {Task {await store.unlockBiometric()}}
                            else {store.error="请先使用密码解锁，再到个人详情启用 Face ID / 系统解锁"}
                        } label:{Image(systemName:"faceid").font(.system(size:26,weight:.regular)).frame(width:54,height:54).appGlass(Circle(),interactive:true)}.buttonStyle(.plain).foregroundStyle(.black.opacity(0.78)).accessibilityLabel("Face ID 解锁").disabled(store.busy).padding(.top,12)}
                        if !store.hasVault { Text("密码用于加密备份，请妥善保存。请定期在个人详情导出加密备份。").font(.caption).foregroundStyle(.black.opacity(0.6)).multilineTextAlignment(.center) }
                    }.frame(maxWidth:340).frame(maxWidth:.infinity).accessibilityIdentifier("unlock.controls")
                        Spacer(minLength:24)
                    }.padding(.horizontal,28).padding(.bottom,24).frame(minHeight:proxy.size.height,alignment:.top)
                }.scrollDismissesKeyboard(.interactively)
            }
        }
    }
    func passwordField(_ title:String,text:Binding<String>,confirmation:Bool)->some View {
        HStack(spacing:10) {
            Image(systemName:confirmation ? "checkmark.shield":"lock").font(.system(size:16,weight:.regular)).foregroundStyle(.black.opacity(0.46)).accessibilityHidden(true)
            SecureField(title,text:text).textContentType(store.hasVault ? .password:.newPassword).focused($passwordFocused).font(.system(size:16)).foregroundStyle(.black).tint(Theme.accent)
        }.padding(.horizontal,16).frame(height:52)
            .background(.white.opacity(0.9),in:RoundedRectangle(cornerRadius:16))
            .overlay {RoundedRectangle(cornerRadius:16).strokeBorder(.white.opacity(0.65),lineWidth:0.5)}
    }
}

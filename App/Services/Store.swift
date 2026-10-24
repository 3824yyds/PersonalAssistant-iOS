import UIKit
import SwiftUI
import CryptoKit
import LocalAuthentication

struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var role: String
    var content: String
    var source: String = ""
    var sources:[WebSource]? = nil
    var images:[ChatImage]? = nil
}
struct ChatSession: Codable, Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var title = "新对话"
    var updated = Date()
    var messages: [ChatMessage] = []
    var finance: Bool? = nil
}
struct VoiceCaptureState:Equatable {
    var action:VoiceReleaseAction = .send
    var finishing=false
}

@MainActor final class AppStore: ObservableObject {
    @Published private(set) var document: Document?
    @Published var busy = false
    @Published var error: String?
    @Published var errorScopes:[UUID]=[]
    @Published var sessions: [ChatSession] = []
    @Published var messages: [ChatMessage] = []
    @Published var activeSessionID = UUID().uuidString
    @Published var financeMode = false
    @Published var chatDraft = ""
    @Published var noteFolder="收件箱"
    @Published var chatImages:[ChatImage] = []
    @Published var voiceCapture:VoiceCaptureState?
    @Published var assistantBusy = false
    @Published var cloudEnabled = true
    @Published var hasVault = false
    @Published var hasAPIKey = false
    @Published var biometricEnabled = UserDefaults.standard.bool(forKey:"biometricEnabled")
    @Published var model = "deepseek-flash"
    @Published private(set) var appearance=AppAppearance(rawValue:UserDefaults.standard.string(forKey:"appAppearance") ?? "system") ?? .system
    var key = Data(), salt = Data()
    var epoch = UUID()
    var activeTask: Task<Void,Never>?
    var activeReplyID: String?
    var speech: SpeechService?
    init() {
        if let files=try? FileManager.default.contentsOfDirectory(at:FileManager.default.temporaryDirectory,includingPropertiesForKeys:nil) {for file in files where file.lastPathComponent.hasPrefix("note-preview-") {try? FileManager.default.removeItem(at:file)}}
        hasVault = (try? PrivateFiles.url()).map { FileManager.default.fileExists(atPath:$0.path) } ?? false
        hasAPIKey = (try? Keychain.read("deepseek")) != nil
    }
    var current: Document { document ?? Document() }
    var currency: String { current.currency }
    func selectAppearance(_ value:String) {
        guard let selected=AppAppearance(rawValue:value) else {return}
        appearance=selected
        UserDefaults.standard.set(value,forKey:"appAppearance")
        for scene in UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}) {
            for window in scene.windows {window.overrideUserInterfaceStyle=selected.style}
        }
    }
    private func restoreAppearance(_ document:Document) {
        if UserDefaults.standard.string(forKey:"appAppearance")==nil {
            selectAppearance(document.settings.text("theme",fallback:"system"))
        }
    }
    func present(_ error: Error) { if !(error is CancellationError) { self.error = error.localizedDescription } }
    func unlock(password: String, creating: Bool = false) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let unlockEpoch=epoch
        let attemptData = (try? Keychain.read("attempts")) ?? Data()
        let attempts = (try? JSONDecoder().decode([String:Double].self,from:attemptData)) ?? [:]
        if (attempts["until"] ?? 0) > Date().timeIntervalSince1970 { error = "尝试次数较多，请稍后再试"; return }
        do {
            let result: (Document,Data,Data) = try await Task.detached(priority:.userInitiated) {
                if creating {
                    guard !FileManager.default.fileExists(atPath:try PrivateFiles.url().path) else { throw AppError.message("资料库已经存在，请解锁") }
                    let salt = try VaultCrypto.random(32), key = try VaultCrypto.derive(password:password,salt:salt)
                    var d = Document(); var a = Item.make(["name":.string("现金"),"currency":.string("CNY"),"type":.string("cash"),"openingDate":.int(1)])
                    a.set("openingCents",Int64(0)); d.accounts = [a]
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-layout-fixture") {d=DebugFixtures.document()}
                    #endif
                    try PrivateFiles.write(VaultCrypto.encrypt(d.encoded(),key:key,salt:salt))
                    return (d,key,salt)
                }
                let encrypted = try PrivateFiles.boundedRead(PrivateFiles.url()), salt = try VaultCrypto.salt(encrypted), key = try VaultCrypto.derive(password:password,salt:salt)
                let d = try JSONDecoder().decode(Document.self,from:VaultCrypto.decrypt(encrypted,key:key)).validated()
                return (d,key,salt)
            }.value
            guard unlockEpoch==epoch else {return}
            key = result.1; salt = result.2; var d = result.0
            #if DEBUG
            // Each UI test receives its own deterministic in-memory content, even after relaunch.
            if ProcessInfo.processInfo.arguments.contains("--ui-layout-fixture") {d=DebugFixtures.document()}
            #endif
            d.accounts = Finance.accounts(d); d=Loans.refreshReminders(d); document = d; hasVault = true
            NotificationService.sync(d.records)
            cloudEnabled = d.settings.bool("cloudEnabled",fallback:true); model = DeepSeekModels.current(d.settings.text("model",fallback:"deepseek-flash"))
            restoreAppearance(d)
            Keychain.delete("attempts"); epoch = UUID(); await loadHistory()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            let failures = (attempts["count"] ?? 0)+1
            let delay = failures >= 5 ? min(3600,pow(2,failures-5)*30):0
            try? Keychain.save(JSONEncoder().encode(["count":failures,"until":Date().timeIntervalSince1970+delay]),name:"attempts")
            present(error)
        }
    }
    func unlockBiometric() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            guard let saved = try Keychain.read("vault-biometric",prompt:"解锁个人助理资料库") else { throw AppError.message("请先用密码解锁，并在设置中启用系统解锁") }
            let encrypted = try PrivateFiles.boundedRead(PrivateFiles.url())
            let d = try JSONDecoder().decode(Document.self,from:VaultCrypto.decrypt(encrypted,key:saved)).validated()
            key = saved; salt = try VaultCrypto.salt(encrypted); var next = d; next.accounts = Finance.accounts(d); next=Loans.refreshReminders(next);document = next
            NotificationService.sync(next.records)
            cloudEnabled = d.settings.bool("cloudEnabled",fallback:true); model = DeepSeekModels.current(d.settings.text("model",fallback:"deepseek-flash")); epoch = UUID(); await loadHistory()
            restoreAppearance(d)
        } catch { present(error) }
    }
    func lock() {
        epoch = UUID(); cancelReply()
        speech?.cancel(); LocalModel.shared.cancel()
        document = nil; messages = []; sessions = []; chatDraft="";chatImages=[];noteFolder="收件箱";voiceCapture=nil;key.resetBytes(in:0..<key.count); key = Data(); salt = Data()
        LocalModel.shared.release()
    }
    func cancelReply() {
        activeReplyID=nil;activeTask?.cancel();activeTask=nil;assistantBusy=false;LocalModel.shared.cancel()
        messages.removeAll {$0.role=="assistant" && $0.content.isEmpty}
    }
    @discardableResult func commit(_ change: (inout Document) throws -> Void) async -> Bool {
        guard var next = document, !busy else { return false }
        busy = true; let token = epoch; let key = key, salt = salt; defer { busy = false }
        do {
            try change(&next); next=Loans.refreshReminders(next);next = try next.validated(); let snapshot = next
            try await Task.detached(priority:.userInitiated) { try PrivateFiles.write(VaultCrypto.encrypt(snapshot.encoded(),key:key,salt:salt)) }.value
            guard token == epoch, document != nil else { return false }
            document = next; cloudEnabled = next.settings.bool("cloudEnabled",fallback:true); model = DeepSeekModels.current(next.settings.text("model",fallback:"deepseek-flash"))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotificationService.sync(next.records); return true
        } catch { present(error); return false }
    }
    func setting(_ key: String, _ value: JSONValue) async {
        if key=="theme",case .string(let choice)=value {selectAppearance(choice)}
        await commit { var s = $0.settings; s.raw[key] = value; $0.settings = s }
    }
    func setAPIKey(_ value: String) {
        do { if value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { Keychain.delete("deepseek"); hasAPIKey = false } else { try Keychain.save(Data(value.trimmingCharacters(in:.whitespacesAndNewlines).utf8),name:"deepseek"); hasAPIKey = true } } catch { present(error) }
    }
    func setBiometric(_ enabled: Bool) async {
        do {
            if enabled {
                let context = LAContext(); var error: NSError?
                guard context.canEvaluatePolicy(.deviceOwnerAuthentication,error:&error), try await context.evaluatePolicy(.deviceOwnerAuthentication,localizedReason:"启用系统解锁") else { throw AppError.message("请先在系统设置中启用锁屏密码或 Face ID") }
                try Keychain.save(key,name:"vault-biometric",biometric:true)
            } else { Keychain.delete("vault-biometric") }
            biometricEnabled = enabled; UserDefaults.standard.set(enabled,forKey:"biometricEnabled")
        } catch { present(error) }
    }
    func importBackup(_ data: Data, password: String) async -> Bool {
        guard document != nil, !busy else { return false }
        do {
            let imported = try await Task.detached(priority:.userInitiated) {
                let salt = try VaultCrypto.salt(data), key = try VaultCrypto.derive(password:password,salt:salt)
                return try JSONDecoder().decode(Document.self,from:VaultCrypto.decrypt(data,key:key)).validated()
            }.value
            return await commit { $0 = imported; $0.accounts = Finance.accounts(imported) }
        } catch { present(error); return false }
    }
    func backup() async throws -> Data {
        guard let d = document else { throw AppError.message("请先解锁资料库") }; let key = key, salt = salt
        return try await Task.detached { try VaultCrypto.encrypt(d.encoded(),key:key,salt:salt) }.value
    }
    private func snapshotCurrentHistory() {
        guard document != nil, !key.isEmpty else { return }
        let retention = current.settings.int("chatRetentionDays",fallback:7)
        sessions.removeAll { $0.updated < Date().addingTimeInterval(-Double(retention)*86400) }
        if !messages.isEmpty {
            let existing = sessions.first { $0.id == activeSessionID }
            let s = ChatSession(id:activeSessionID,title:existing?.title ?? String((messages.first { $0.role == "user" }?.content ?? "新对话").prefix(24)),updated:Date(),messages:messages,finance:financeMode)
            sessions.removeAll { $0.id == s.id }; sessions.insert(s,at:0)
        }
    }
    private func persistHistory() async {
        guard document != nil,!key.isEmpty else{return}
        do {
            var saved=Array(sessions.prefix(100))
            var data=try JSONEncoder().encode(saved)
            while data.count>24*1024*1024 && saved.count>1 {saved.removeLast();data=try JSONEncoder().encode(saved)}
            let key=key,salt=salt
            try await Task.detached { try PrivateFiles.write(VaultCrypto.encrypt(data,key:key,salt:salt),name:"chat.pavault") }.value
        } catch { present(error) }
    }
    func saveHistory() async {snapshotCurrentHistory();await persistHistory()}
    func loadHistory() async {
        do {
            if let data = try? PrivateFiles.boundedRead(PrivateFiles.url("chat.pavault")) {
                sessions = try JSONDecoder().decode([ChatSession].self,from:VaultCrypto.decrypt(data,key:key))
                sessions.removeAll { $0.updated < Date().addingTimeInterval(-Double(current.settings.int("chatRetentionDays",fallback:7))*86400) }
            }
        } catch { self.error = "历史对话未能读取，当前资料库不受影响" }
    }
    func newChat(finance:Bool?=nil) async {cancelReply();snapshotCurrentHistory();messages=[];chatImages=[];activeSessionID=UUID().uuidString;if let finance {financeMode=finance};await persistHistory()}
}

import Foundation
import Combine

@MainActor final class CompanionSession: ObservableObject {
    @Published private(set) var data: CompanionData
    @Published var draft = ""
    @Published private(set) var busy = false
    @Published private(set) var partial = ""
    @Published private(set) var status = ""
    @Published var error: String?
    @Published var compression:CompanionCompressionPreview?
    private unowned let store: AppStore
    private var request: Task<Void,Never>?
    private var requestID = UUID()
    private let epoch: UUID
    private var interaction = Date()
    var visible = false
    var active = true
    var editing = false
    var panelOpen = false
    var title: String { data.profile.title }
    var cloudAvailable: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-companion-fixture") {return true}
        #endif
        return store.cloudEnabled && store.hasAPIKey
    }
    init(store: AppStore) {
        self.store = store; epoch = store.epoch
        do { data = try CompanionData.read(store.current) }
        catch { data = CompanionData(); self.error = error.localizedDescription }
    }
    func touch() { interaction = Date() }
    private var unlocked: Bool { store.document != nil && store.epoch == epoch }
    @discardableResult func update(_ edit: (inout CompanionData) throws -> Void) async -> Bool {
        guard unlocked else { return false }
        if store.busy { error = "资料正在保存，请稍后重试"; return false }
        let saved = await store.commit { document in
            var next = try CompanionData.read(document)
            try edit(&next); try next.write(to:&document)
        }
        guard unlocked else { return false }
        if saved { data = (try? CompanionData.read(store.current)) ?? data }
        else { error = store.error ?? "伙伴资料未能保存，请稍后重试" }
        return saved
    }
    func open() async {
        visible = true; touch()
        guard data.messages.isEmpty || data.profile.nameRecoveryChecked != true else { return }
        await update {
            CompanionRules.recoverLegacyName(in:&$0)
            guard $0.messages.isEmpty else { return }
            $0.messages.append(CompanionMessage(role:"assistant",content:$0.profile.name == nil ? "你来啦，今天过得怎么样？也可以先给我取个名字呀。":"我在呢，今天想聊点什么？",source:"伙伴问候"))
            $0.awaitingProactiveReply = true; $0.lastProactive = Date()
        }
    }
    func cancel() {
        requestID = UUID(); request?.cancel(); request = nil
        busy = false; partial = ""; status = ""; touch()
    }
    func close() { visible = false; cancel() }
    func send() {
        let question = draft.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !busy, !question.isEmpty else { return }
        guard question.count <= 1200 else { error = "这段话较长，请分段发送（每条最多1200字）"; return }
        guard CompanionContext.canSend(question,data:data) else {error="当前窗口上下文已达上限，请先精简并开启新窗口。输入的文字已保留。";return}
        touch(); begin(question:question,proactive:false)
    }
    func retryLast() {
        guard !busy, let message=data.messages.last, message.role == "user" else { return }
        begin(question:message.content,proactive:false,retry:true)
    }
    func sendSticker(_ sticker:CompanionSticker) {
        let question="[表情包："+sticker.title+"，"+sticker.meaning+"]"
        guard !busy else {return}
        guard CompanionContext.canSend(CompanionMessage(role:"user",content:question,stickerID:sticker.id).contextText,data:data) else {error="当前窗口上下文已满，请先精简并新开窗口";return}
        touch();begin(question:question,proactive:false,stickerID:sticker.id)
    }
    private func begin(question:String, proactive:Bool, retry:Bool=false,stickerID:String?=nil) {
        guard unlocked, !busy else { return }
        let id=UUID(); requestID=id; busy=true; error=nil; partial=""; status=proactive ? "正在接着话题想…":"正在想…"
        request=Task { [weak self] in
            guard let self else { return }
            defer { if self.requestID == id { self.busy=false; self.status=""; self.partial=""; self.request=nil; self.touch() } }
            let previous=retry ? Array(self.data.messages.dropLast()):self.data.messages
            var repliedLocally=false
            if !retry {
                guard await self.update({ state in
                    if proactive { state.lastProactive=Date(); state.awaitingProactiveReply=true }
                    else {
                        repliedLocally=try CompanionRules.appendUserTurn(question,to:&state)
                        if let stickerID,let index=state.messages.lastIndex(where:{$0.role=="user"}) {state.messages[index].stickerID=stickerID}
                    }
                }) else { return }
                if !proactive, stickerID==nil,self.draft.trimmingCharacters(in:.whitespacesAndNewlines) == question { self.draft="" }
            }
            if repliedLocally {return}
            guard self.requestID==id, self.unlocked, !Task.isCancelled else { return }
            do {
                let text:String,source:String,sources:[WebSource],proposal:String?,sticker:String?
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-companion-fixture"),!CompanionRules.needsWeb(question) {
                    try await Task.sleep(nanoseconds:ProcessInfo.processInfo.arguments.contains("--ui-companion-slow-fixture") ? 3_000_000_000:300_000_000)
                    text="我在呢，接着聊。";source="界面测试夹具";sources=[];proposal=nil
                    sticker=ProcessInfo.processInfo.arguments.contains("--ui-companion-sticker-fixture") && self.data.profile.stickers != false ? "hug":nil
                } else {
                    guard self.store.cloudEnabled else {throw AppError.message("伙伴聊天需要云端智能，请在个人详情开启后重试")}
                    (text,source,sources,proposal,sticker)=try await self.cloudReply(question:question,previous:previous,proactive:proactive,id:id)
                }
                #else
                guard self.store.cloudEnabled else {throw AppError.message("伙伴聊天需要云端智能，请在个人详情开启后重试")}
                (text,source,sources,proposal,sticker)=try await self.cloudReply(question:question,previous:previous,proactive:proactive,id:id)
                #endif
                try Task.checkCancellation()
                guard self.requestID==id, self.unlocked else { return }
                let message=CompanionMessage(role:"assistant",content:text,source:source,sources:sources,nameProposal:proposal,stickerID:sticker)
                _=await self.update { $0.messages.append(message) }
            } catch {
                guard self.requestID==id,self.unlocked,!(error is CancellationError),!Task.isCancelled else{return}
                self.error=error.localizedDescription
            }
        }
    }
    private func cloudReply(question:String,previous:[CompanionMessage],proactive:Bool,id:UUID) async throws -> (String,String,[WebSource],String?,String?) {
        try await CompanionReplyService.answer(question:question,data:data,history:previous,proactive:proactive,
            client:DeepSeekWebClient(apiKey:try AIService.credential()),onStatus:{ [weak self] value in
                guard let self,self.requestID==id,self.unlocked else{return};self.status=value
            })
    }
    func tick() {
        guard CompanionRules.mayInitiate(data:data,visible:visible && !panelOpen,active:active,editing:editing,draft:draft,busy:busy || store.busy,now:Date(),lastInteraction:interaction),cloudAvailable else {return}
        begin(question:"用户仍停留在聊天页。请根据前文或记忆主动说一句简短、自然的话，可以接着未完话题；没有依据就问候，不虚构经历，不催促回复。",proactive:true)
    }
    func undoName(_ message:CompanionMessage) async {
        guard !busy,CompanionRules.canUndoName(message,data:data) else {return}
        await update {
            $0.profile.name=message.renamedFrom.flatMap {$0.isEmpty ? nil:$0}
            if let index=$0.messages.firstIndex(where:{$0.id==message.id}) {$0.messages[index].renamedTo=nil;$0.messages[index].renamedFrom=nil}
        }
    }
    func removeMemory(_ id:String) async { _=await update {$0.memories.removeAll {$0.id==id}} }
    func prepareCompression(manual:Bool=false) {
        guard !busy,unlocked,!store.busy else {return}
        if manual {compression=CompanionCompressionPreview(text:CompanionContext.summary(data),expectedLastID:data.messages.last?.id,expectedWindowID:data.windows?.last?.id,expectedMessages:CompanionContext.current(data),expectedSummary:CompanionContext.summary(data));return}
        let id=UUID();requestID=id;busy=true;error=nil;status="正在精简上下文…"
        request=Task { [weak self] in
            guard let self else {return}
            defer {if self.requestID==id {self.busy=false;self.status="";self.request=nil;self.touch()}}
            do {
                let result:CompanionCompressionPreview
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-companion-fixture") {
                    try await Task.sleep(nanoseconds:300_000_000)
                    result=CompanionCompressionPreview(text:"用户说：周六准备去杭州面试，想提前准备。",expectedLastID:self.data.messages.last?.id,expectedWindowID:self.data.windows?.last?.id,expectedMessages:CompanionContext.current(self.data),expectedSummary:CompanionContext.summary(self.data))
                } else {
                    guard self.store.cloudEnabled else {throw AppError.message("自动精简需要开启云端智能，也可以手动整理")}
                    result=try await self.compressionPreview(id:id)
                }
                #else
                guard self.store.cloudEnabled else {throw AppError.message("自动精简需要开启云端智能，也可以手动整理")}
                result=try await self.compressionPreview(id:id)
                #endif
                guard self.unlocked,self.requestID==id,!Task.isCancelled else {return}
                self.compression=result
            } catch {guard self.unlocked,self.requestID==id,!(error is CancellationError),!Task.isCancelled else {return};self.error=error.localizedDescription}
        }
    }
    private func compressionPreview(id:UUID) async throws -> CompanionCompressionPreview {
        try await CompanionCompressionService.preview(data:data,client:DeepSeekWebClient(apiKey:try AIService.credential()),onStatus:{[weak self] value in
            guard let self,self.requestID==id,self.unlocked else {return};self.status=value
        })
    }
    func applyCompression(_ preview:CompanionCompressionPreview) async -> Bool {
        guard !busy else {return false}
        let saved=await update {state in
            guard CompanionContext.apply(preview,to:&state) else {throw AppError.message("摘要为空、过长或聊天已经变化，请重新整理；原聊天没有删除")}
        }
        if saved {compression=nil;error=nil;touch()}
        return saved
    }
    func confirmName(_ message:CompanionMessage) async {
        guard !busy else {return}
        _=await update {_=try CompanionRules.confirmNameProposal(message,in:&$0)}
    }
    func undoMemory(_ message:CompanionMessage) async {
        guard !busy else {return}
        _=await update {_=CompanionRules.undoMemory(message,in:&$0)}
    }
}

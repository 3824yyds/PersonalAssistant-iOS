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
    @Published var replyTo:CompanionQuote?
    @Published var target:CompanionPersona?
    @Published private(set) var speaking:CompanionPersona?
    let space:CompanionSpace
    private unowned let store: AppStore
    private var request: Task<Void,Never>?
    private var requestID = UUID()
    private let epoch: UUID
    private var interaction = Date()
    private var peerProfiles:[CompanionPersona:CompanionProfile]=[:]
    private var storedMembers:[CompanionPersona]=[]
    private var lastPreview=Date.distantPast
    var visible = false
    var active = true
    var editing = false
    var panelOpen = false
    var title: String { data.profile.title }
    var isGroup:Bool {space.isGroup}
    var persona:CompanionPersona {data.profile.persona}
    var members:[CompanionPersona] {storedMembers}
    func profile(_ persona:CompanionPersona)->CompanionProfile {if !isGroup,self.persona==persona {return data.profile};return peerProfiles[persona] ?? persona.initial.profile}
    var canRetry:Bool {
        guard let turn=CompanionContext.current(data).last(where:{$0.role=="user"}) else {return false}
        return isGroup ? !CompanionDirectory.pending(turn,in:data).isEmpty:CompanionContext.current(data).last?.role=="user"
    }
    var cloudAvailable: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-companion-fixture") {return true}
        #endif
        return store.cloudEnabled && store.hasAPIKey
    }
    init(store: AppStore,space:CompanionSpace = .direct(.female)) {
        self.store = store;self.space=space;epoch = store.epoch
        do { data = try CompanionDirectory.read(space,in:store.current) }
        catch { data = space.persona.initial; self.error = error.localizedDescription }
        peerProfiles=Dictionary(uniqueKeysWithValues:CompanionPersona.allCases.map {($0,(try? CompanionDirectory.read(.direct($0),in:store.current).profile) ?? $0.initial.profile)})
        if case .group(let id)=space {storedMembers=(try? CompanionDirectory.groups(store.current).first {$0.id==id}?.members) ?? []}else{storedMembers=[space.persona]}
    }
    func touch() { interaction = Date() }
    private func showPreview(_ value:String,id:UUID) {
        guard requestID==id,unlocked,!Task.isCancelled else {return}
        guard value.isEmpty || Date().timeIntervalSince(lastPreview)>=0.14 else {return}
        lastPreview=Date();partial=value
    }
    private var unlocked: Bool { store.document != nil && store.epoch == epoch }
    @discardableResult func update(_ edit: (inout CompanionData) throws -> Void) async -> Bool {
        guard unlocked else { return false }
        if store.busy { error = "资料正在保存，请稍后重试"; return false }
        let saved = await store.commit { document in
            var next = try CompanionDirectory.read(self.space,in:document)
            try edit(&next); try CompanionDirectory.write(next,space:self.space,to:&document)
        }
        guard unlocked else { return false }
        if saved {
            data = (try? CompanionDirectory.read(space,in:store.current)) ?? data
            if let replyTo,!data.messages.contains(where:{$0.id==replyTo.messageID}) {self.replyTo=nil}
        }
        else { error = store.error ?? "伙伴资料未能保存，请稍后重试" }
        return saved
    }
    func open() async {
        visible = true; touch()
        guard !isGroup else {return}
        guard data.messages.isEmpty || data.profile.nameRecoveryChecked != true || data.profile.confirmationRecoveryChecked != true else { return }
        await update {
            CompanionNaming.recoverConfirmedName(in:&$0)
            CompanionRules.recoverLegacyName(in:&$0)
            guard $0.messages.isEmpty else { return }
            let greeting=$0.profile.persona == .male ? ($0.profile.name==nil ? "我还没取名，你想怎么叫我？":"我在，接着聊。"):($0.profile.name == nil ? "你来啦，今天过得怎么样？也可以先给我取个名字呀。":"我在呢，今天想聊点什么？")
            $0.messages.append(CompanionMessage(role:"assistant",content:greeting,source:"伙伴问候"))
            $0.awaitingProactiveReply = true; $0.lastProactive = Date()
        }
    }
    func cancel() {
        requestID = UUID(); request?.cancel(); request = nil
        busy = false; partial = ""; status = "";speaking=nil; touch()
    }
    func close() { visible = false; cancel() }
    func send() {
        let question = draft.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !busy, !question.isEmpty else { return }
        guard question.count <= 1200 else { error = "这段话较长，请分段发送（每条最多1200字）"; return }
        guard CompanionContext.canSend(CompanionMessage(role:"user",content:question,replyTo:replyTo).contextText,data:data) else {error="当前窗口上下文已达上限，请先精简并开启新窗口。输入的文字已保留。";return}
        touch(); begin(question:question,proactive:false,quote:replyTo)
    }
    func retryLast() {
        if isGroup {
            guard !busy,let turn=CompanionContext.current(data).last(where:{$0.role=="user"}),!CompanionDirectory.pending(turn,in:data).isEmpty else {return}
            beginGroup(question:turn.content,retry:turn,stickerID:turn.stickerID,quote:turn.replyTo);return
        }
        guard !busy, let message=CompanionContext.current(data).last, message.role == "user" else { return }
        begin(question:message.content,proactive:false,retry:true,quote:message.replyTo)
    }
    func sendSticker(_ sticker:CompanionSticker) {
        let question=sticker.title
        guard !busy else {return}
        guard data.availableStickers.contains(where:{$0.id==sticker.id}) else {error="这个表情已移除，请重新选择";return}
        guard CompanionContext.canSend(CompanionMessage(role:"user",content:question,stickerID:sticker.id,stickerMeaning:sticker.description,replyTo:replyTo).contextText,data:data) else {error="当前窗口上下文已满，请先精简并新开窗口";return}
        touch();begin(question:question,proactive:false,stickerID:sticker.id,quote:replyTo)
    }
    func selectReply(_ message:CompanionMessage) {
        guard !busy,data.messages.contains(where:{$0.id==message.id}) else {return}
        replyTo=CompanionQuote.snapshot(message,data:data);touch()
    }
    func addSticker(_ sticker:CompanionCustomSticker) async -> Bool {guard !busy else {return false};return await update {try $0.addSticker(sticker)}}
    func removeSticker(_ id:String) async {guard !busy else {return};_=await update {$0.removeSticker(id)}}
    func setStickerAllowed(_ id:String,_ allowed:Bool) async {
        guard !busy else {return};_=await update {state in if let index=state.customStickers?.firstIndex(where:{$0.id==id}) {state.customStickers?[index].allowAssistant=allowed}}
    }
    private func begin(question:String, proactive:Bool, retry:Bool=false,stickerID:String?=nil,quote:CompanionQuote?=nil) {
        if isGroup {if !proactive {beginGroup(question:question,retry:nil,stickerID:stickerID,quote:quote)};return}
        guard unlocked, !busy else { return }
        let id=UUID(); requestID=id; busy=true; error=nil; partial=""; status=proactive ? "正在接着话题想…":"正在想…"
        request=Task { [weak self] in
            guard let self else { return }
            defer { if self.requestID == id { self.busy=false; self.status=""; self.partial=""; self.request=nil; self.touch() } }
            let previous=retry ? Array(self.data.messages.dropLast()):self.data.messages
            var repliedLocally=false
            if retry,let restored=CompanionRules.localRetry(self.data) {
                _=await self.update {state in
                    guard state.messages.last?.id==restored.messages.dropLast().last?.id else {throw AppError.message("消息已变化，请重新选择重试")}
                    state=restored
                }
                return
            }
            if !retry {
                guard await self.update({ state in
                    if proactive { state.lastProactive=Date(); state.awaitingProactiveReply=true }
                    else {
                        repliedLocally=try CompanionRules.appendUserTurn(question,to:&state,replyTo:quote)
                        if let stickerID,let index=state.messages.lastIndex(where:{$0.role=="user"}) {let meaning=state.descriptor(stickerID)?.description;state.messages[index].stickerID=stickerID;state.messages[index].stickerMeaning=meaning}
                    }
                }) else { return }
                if !proactive, stickerID==nil,self.draft.trimmingCharacters(in:.whitespacesAndNewlines) == question { self.draft="" }
                if !proactive,self.replyTo==quote {self.replyTo=nil}
            }
            if repliedLocally {return}
            guard self.requestID==id, self.unlocked, !Task.isCancelled else { return }
            do {
                let text:String,source:String,sources:[WebSource],proposal:String?,sticker:String?
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-companion-delivery-fixture") {
                    (text,source,sources,proposal,sticker)=try await CompanionReplyService.answer(question:question,data:self.data,history:previous,client:CompanionDeliveryFixture.client(),replyTo:quote,onPartial:{[weak self] value in self?.showPreview(value,id:id)})
                } else if ProcessInfo.processInfo.arguments.contains("--ui-companion-fixture"),!CompanionRules.needsWeb(question) {
                    try await Task.sleep(nanoseconds:ProcessInfo.processInfo.arguments.contains("--ui-companion-slow-fixture") ? 3_000_000_000:300_000_000)
                    text=quote == nil ? "我在呢，接着聊。":"收到，你是在回复这条消息，我接着这句聊。";source="界面测试夹具";sources=[];proposal=nil
                    sticker=ProcessInfo.processInfo.arguments.contains("--ui-companion-sticker-fixture") && self.data.profile.stickers != false ? "hug":nil
                } else {
                    guard self.store.cloudEnabled else {throw AppError.message("伙伴聊天需要云端智能，请在个人详情开启后重试")}
                    (text,source,sources,proposal,sticker)=try await self.cloudReply(question:question,previous:previous,proactive:proactive,id:id,quote:quote)
                }
                #else
                guard self.store.cloudEnabled else {throw AppError.message("伙伴聊天需要云端智能，请在个人详情开启后重试")}
                (text,source,sources,proposal,sticker)=try await self.cloudReply(question:question,previous:previous,proactive:proactive,id:id,quote:quote)
                #endif
                try Task.checkCancellation()
                guard self.requestID==id, self.unlocked else { return }
                let message=CompanionMessage(role:"assistant",content:text,source:source,sources:sources,nameProposal:proposal,stickerID:sticker,stickerMeaning:self.data.descriptor(sticker)?.description)
                _=await self.update { $0.messages.append(message) }
            } catch {
                guard self.requestID==id,self.unlocked,!(error is CancellationError),!Task.isCancelled else{return}
                self.error=error.localizedDescription
            }
        }
    }
    private func cloudReply(question:String,previous:[CompanionMessage],proactive:Bool,id:UUID,quote:CompanionQuote?) async throws -> (String,String,[WebSource],String?,String?) {
        try await CompanionReplyService.answer(question:question,data:data,history:previous,proactive:proactive,
            client:DeepSeekWebClient(apiKey:try AIService.credential()),replyTo:quote,onPartial:{[weak self] value in self?.showPreview(value,id:id)},onStatus:{ [weak self] value in
                guard let self,self.requestID==id,self.unlocked else{return};self.status=value
            })
    }
    func tick() {
        guard !isGroup else {return}
        guard replyTo==nil,CompanionRules.mayInitiate(data:data,visible:visible && !panelOpen,active:active,editing:editing,draft:draft,busy:busy || store.busy,now:Date(),lastInteraction:interaction),cloudAvailable else {return}
        begin(question:"用户仍停留在聊天页。请根据前文或记忆主动说一句简短、自然的话，可以接着未完话题；没有依据就问候，不虚构经历，不催促回复。",proactive:true)
    }
    private func beginGroup(question:String,retry:CompanionMessage?,stickerID:String?,quote:CompanionQuote?) {
        guard unlocked,!busy,case .group(let roomID)=space else {return}
        let requestToken=UUID();requestID=requestToken;busy=true;error=nil;partial="";status="正在接话…"
        request=Task { [weak self] in
            guard let self else {return}
            defer {if self.requestID==requestToken {self.busy=false;self.status="";self.partial="";self.speaking=nil;self.request=nil;self.touch()}}
            do {
                guard let room=try CompanionDirectory.groups(self.store.current).first(where:{$0.id==roomID}) else {throw AppError.message("这个群聊已不存在")}
                var turn=retry ?? CompanionMessage(role:"user",content:question,stickerID:stickerID,stickerMeaning:self.data.descriptor(stickerID)?.description,replyTo:quote)
                if retry==nil {
                    turn.recipients=CompanionDirectory.recipients(question:question,selected:self.target,group:room,document:self.store.current).map(\.rawValue)
                    guard self.data.messages.count<CompanionData.messageLimit-3 else {throw AppError.message("群聊记录已满，请先整理")}
                    let saved=await self.update {state in
                        if let quote {guard let source=state.messages.first(where:{$0.id==quote.messageID}),CompanionQuote.snapshot(source,data:state)==quote else {throw AppError.message("被引用的消息已变化，请重新选择")}}
                        state.messages.append(turn)
                        for raw in turn.recipients ?? [] {if let p=CompanionPersona(rawValue:raw) {CompanionGrowth.observe(turn,for:p,in:&state)}}
                    }
                    guard saved else {return}
                    if stickerID==nil,self.draft.trimmingCharacters(in:.whitespacesAndNewlines)==question {self.draft=""}
                    if self.replyTo==quote {self.replyTo=nil}
                }
                for member in CompanionDirectory.pending(turn,in:self.data) {
                    try Task.checkCancellation();guard self.requestID==requestToken,self.unlocked else {return}
                    self.partial="";self.speaking=member;self.status=self.profile(member).title+"正在想…"
                    let context=CompanionDirectory.groupContext(self.data,as:member,document:self.store.current)
                    let history=context.messages.filter {$0.id != turn.id}
                    let scene="这是用户与两位AI伙伴的共享群聊。你只扮演"+member.label+"（"+member.rawValue+"），每次只用自己的身份接一句，不替其它成员说话、不冒充用户，不转述私聊。历史‘群成员…说’明确标记其它AI发言，不能当成真实用户事实。最终用户消息是本轮原话；前一位若已答过就补充或自然回应，避免重复。群里不更改个人名字、不提出取名确认；请用户到对应私聊取名。群聊最多每人一条，不启动新的自主对话。"
                    let result:(String,String,[WebSource],String?,String?)
                    if let time=CompanionClock.reply(question) {result=(time,"设备时间",[],nil,nil)} else {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-companion-fixture") {
                        try await Task.sleep(nanoseconds:member == .male && ProcessInfo.processInfo.arguments.contains("--ui-companion-group-slow-fixture") ? 8_000_000_000:300_000_000)
                        result=(member == .male ? (turn.recipients?.count==1 ? "这轮我单独接话。":"先挑一件最想聊的，我听着。"):"我也在，今天想一起聊点什么？","界面测试夹具",[],nil,nil)
                    } else {
                        guard self.store.cloudEnabled else {throw AppError.message("群聊需要开启云端智能")}
                        result=try await CompanionReplyService.answer(question:question,data:context,history:history,client:DeepSeekWebClient(apiKey:try AIService.credential()),replyTo:quote,allowNaming:false,scene:scene,incomingMessage:turn,onPartial:{[weak self] value in self?.showPreview(value,id:requestToken)},onStatus:{[weak self] value in guard let self,self.requestID==requestToken,self.unlocked else{return};self.status=self.profile(member).title+" · "+value})
                    }
                    #else
                    guard self.store.cloudEnabled else {throw AppError.message("群聊需要开启云端智能")}
                    result=try await CompanionReplyService.answer(question:question,data:context,history:history,client:DeepSeekWebClient(apiKey:try AIService.credential()),replyTo:quote,allowNaming:false,scene:scene,incomingMessage:turn,onPartial:{[weak self] value in self?.showPreview(value,id:requestToken)},onStatus:{[weak self] value in guard let self,self.requestID==requestToken,self.unlocked else{return};self.status=self.profile(member).title+" · "+value})
                    #endif
                    }
                    try Task.checkCancellation();guard self.requestID==requestToken,self.unlocked else {return}
                    self.partial=""
                    let answer=CompanionMessage(role:"assistant",content:result.0,source:result.1,sources:result.2,stickerID:result.4,stickerMeaning:context.descriptor(result.4)?.description,speakerID:member.rawValue,turnID:turn.id)
                    guard await self.update({state in
                        guard state.messages.contains(where:{$0.id==turn.id}),!state.messages.contains(where:{$0.turnID==turn.id && $0.speakerID==member.rawValue}) else {throw AppError.message("这条群消息已处理，请重新进入查看")}
                        state.messages.append(answer)
                    }) else {return}
                }
            } catch {guard self.requestID==requestToken,self.unlocked,!(error is CancellationError),!Task.isCancelled else {return};self.error=error.localizedDescription}
        }
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

import Foundation
import Combine

enum CompanionWeb {
    /// Public question context only; no ledger, notes, private memory or full conversation.
    static func messages(_ question: String, data: CompanionData, previousQuestion: String?) -> [[String:Any]] {
        var result: [[String:Any]] = [["role":"system", "content":CompanionRules.system(data, cloud:true)]]
        if let previousQuestion, previousQuestion != question {
            result.append(["role":"user", "content":"上一条公开查询：" + String(previousQuestion.prefix(500))])
            result.append(["role":"assistant", "content":"请结合该查询理解用户下一句；当前结果必须重新核实。"])
        }
        result.append(["role":"user", "content":question])
        return result
    }
}

@MainActor final class CompanionSession: ObservableObject {
    @Published private(set) var data: CompanionData
    @Published var draft = ""
    @Published private(set) var busy = false
    @Published private(set) var partial = ""
    @Published private(set) var status = ""
    @Published var error: String?
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
    var modelAvailable: Bool { LocalModel.shared.companionAvailable }
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
        guard data.messages.isEmpty else { return }
        await update {
            guard $0.messages.isEmpty else { return }
            $0.messages.append(CompanionMessage(role:"assistant",content:"你来啦，今天过得怎么样？也可以先给我取个名字呀。",source:"伙伴问候"))
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
        touch(); begin(question:question,proactive:false)
    }
    func retryLast() {
        guard !busy, let message=data.messages.last, message.role == "user" else { return }
        begin(question:message.content,proactive:false,retry:true)
    }
    private func begin(question:String, proactive:Bool, retry:Bool=false) {
        guard unlocked, !busy else { return }
        let id=UUID(); requestID=id; busy=true; error=nil; partial=""; status=proactive ? "正在接着话题想…":"正在想…"
        request=Task { [weak self] in
            guard let self else { return }
            defer { if self.requestID == id { self.busy=false; self.status=""; self.partial=""; self.request=nil; self.touch() } }
            let previous=retry ? Array(self.data.messages.dropLast()):self.data.messages
            let proposed=proactive ? nil:CompanionRules.proposedName(question)
            let memory=proactive || retry ? nil:CompanionRules.newMemory(question)
            let memoryWasKnown=memory.map {candidate in self.data.memories.contains {$0.text==candidate.text}} ?? false
            let beforeName=self.data.profile.name
            if !retry {
                guard await self.update({ state in
                    guard state.messages.count < 999 else { throw AppError.message("伙伴聊天记录已满，请先导出备份，再清理聊天") }
                    if proactive { state.lastProactive=Date(); state.awaitingProactiveReply=true }
                    else {
                        state.messages.append(CompanionMessage(role:"user",content:question))
                        state.awaitingProactiveReply=false
                        if let proposed { state.profile.name=proposed }
                        if let memory, !state.memories.contains(where:{$0.text == memory.text}) {
                            guard state.memories.count < 200 else { throw AppError.message("记忆已满，请先整理记忆后重试") }
                            state.memories.append(memory)
                        }
                    }
                }) else { return }
                if !proactive, self.draft.trimmingCharacters(in:.whitespacesAndNewlines) == question { self.draft="" }
            }
            guard self.requestID==id, self.unlocked, !Task.isCancelled else { return }
            do {
                var text: String, source="本机伙伴", sources:[WebSource]=[]
                if let proposed {
                    text="好呀，那我就叫\(proposed)啦！"; source="伙伴资料"
                } else if let identity=proactive ? nil:CompanionRules.selfReply(question,profile:self.data.profile) {
                    text=identity; source="伙伴资料"
                } else if let recalled=proactive ? nil:CompanionRules.recallReply(question,data:self.data,history:previous) {
                    text=recalled; source="伙伴记忆"
                } else if let memory {
                    text=memoryWasKnown ? "记得呀，\(memory.text)。":"记住啦，\(memory.text)。"; source="伙伴记忆"
                } else {
                    let previousWeb=previous.last?.source.hasPrefix("联网") == true
                    if !proactive, CompanionRules.needsWeb(question,previousWeb:previousWeb) {
                        guard self.data.profile.web else { throw AppError.message("联网查询已关闭，可在她的资料中开启后重试") }
                        guard self.store.cloudEnabled else { throw AppError.message("云端智能已关闭，请在个人详情开启后再查询") }
                        self.status="正在联网查询…"
                        let prior=previousWeb ? previous.last(where:{$0.role=="user"})?.content:nil
                        let client=DeepSeekWebClient(apiKey:try AIService.credential())
                        let result=try await client.answer(messages:CompanionWeb.messages(question,data:self.data,previousQuestion:prior),model:"deepseek-flash",responseStyle:"像正在和朋友聊天一样，先简短直接回答，通常一到三句。不要强行列2到4个要点；必要信息和来源必须保留。",onPartial:{ [weak self] value in
                            guard let self,self.requestID==id,self.unlocked else{return};self.partial=value
                        },onSources:{value in sources=value},onStatus:{ [weak self] value in
                            guard let self,self.requestID==id,self.unlocked else{return};self.status=value
                        })
                        text=result.0;source=result.1
                    } else {
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("--ui-companion-fixture") {
                            try await Task.sleep(nanoseconds:200_000_000)
                            text="我在呢，想听你说说今天的事。"; source="界面测试夹具"
                        } else {
                            text=try await LocalModel.shared.companion(system:CompanionRules.system(self.data,cloud:false,query:question),history:previous,input:question)
                        }
                        #else
                        text=try await LocalModel.shared.companion(system:CompanionRules.system(self.data,cloud:false,query:question),history:previous,input:question)
                        #endif
                    }
                }
                try Task.checkCancellation()
                guard self.requestID==id, self.unlocked else { return }
                var message=CompanionMessage(role:"assistant",content:text,source:source,sources:sources)
                if let proposed { message.renamedFrom=beforeName ?? ""; message.renamedTo=proposed }
                if let memory,!memoryWasKnown { message.memoryID=self.data.memories.first(where:{$0.text==memory.text})?.id }
                _=await self.update { $0.messages.append(message) }
            } catch {
                guard self.requestID==id,self.unlocked,!(error is CancellationError),!Task.isCancelled else{return}
                self.error=error.localizedDescription
            }
        }
    }
    func tick() {
        guard CompanionRules.mayInitiate(data:data,visible:visible && !panelOpen,active:active,editing:editing,draft:draft,busy:busy || store.busy,now:Date(),lastInteraction:interaction),modelAvailable else {return}
        begin(question:"用户仍停留在聊天页。请根据前文或记忆主动说一句简短、自然的话，可以接着未完话题；没有依据就问候，不虚构经历，不催促回复。",proactive:true)
    }
    func undoName(_ message:CompanionMessage) async {
        guard !busy, let name=message.renamedTo, data.profile.name==name else {return}
        await update {
            $0.profile.name=message.renamedFrom.flatMap {$0.isEmpty ? nil:$0}
            if let index=$0.messages.firstIndex(where:{$0.id==message.id}) {$0.messages[index].renamedTo=nil;$0.messages[index].renamedFrom=nil}
        }
    }
    func removeMemory(_ id:String) async { _=await update {$0.memories.removeAll {$0.id==id}} }
}

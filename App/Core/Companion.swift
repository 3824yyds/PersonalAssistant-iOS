import Foundation

struct CompanionProfile: Codable, Equatable, Sendable {
    var name: String? = nil
    var appearance = "蓝色长发、蓝眼睛，白色蕾丝发饰和蓝色侧边装饰，穿深蓝色裙装、白色围裙，领口系深色蝴蝶结。"
    var personality = "热情、亲近，愿意主动接话，记得用户说过的事。"
    var proactive = true
    var web = true
    // Optional fields keep Build 10 encrypted backups readable without rewriting them.
    var tone: CompanionTone? = nil
    var gentleUntil: Date? = nil
    var nameRecoveryChecked: Bool? = nil
    var stickers: Bool? = nil
    var title: String { name ?? "伙伴" }
    func effectiveTone(at now:Date = Date()) -> CompanionTone {
        if let gentleUntil, gentleUntil > now {return .gentle}
        return tone ?? .playful
    }
}

struct CompanionMemory: Codable, Equatable, Identifiable, Sendable {
    var id = UUID().uuidString
    var text: String
    var kind = "preference"
    var quote = ""
    var date = Date()
}

struct CompanionMessage: Codable, Equatable, Identifiable, Sendable {
    var id = UUID().uuidString
    var role: String
    var content: String
    var date = Date()
    var source = ""
    var sources: [WebSource] = []
    var memoryID: String? = nil
    var rememberedText: String? = nil
    var replacedMemories: [CompanionMemory]? = nil
    var renamedFrom: String? = nil
    var renamedTo: String? = nil
    var nameProposal: String? = nil
    var stickerID: String? = nil
}

struct CompanionData: Codable, Equatable, Sendable {
    static let messageLimit=5000
    var profile = CompanionProfile()
    var messages: [CompanionMessage] = []
    var memories: [CompanionMemory] = []
    var lastProactive: Date? = nil
    var awaitingProactiveReply = false
    var windows: [CompanionWindow]? = nil
    static func read(_ document: Document) throws -> Self {
        guard let raw = document.root.raw["companionResearch"] else { return Self() }
        do { return try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(raw)) }
        catch { throw AppError.message("伙伴资料无法读取，请保留备份，勿清空原有资料") }
    }
    func write(to document: inout Document) throws {
        try validate()
        document.root.raw["companionResearch"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(self))
    }
    func validate() throws {
        guard profile.name == nil || CompanionRules.cleanName(profile.name!) == profile.name,
              !profile.appearance.isEmpty, profile.appearance.count <= 400,
              !profile.personality.isEmpty, profile.personality.count <= 200,
              memories.count <= 200, messages.count <= Self.messageLimit,
              CompanionContext.validWindows(windows ?? [],messageCount:messages.count),
              Set(memories.map(\.id)).count == memories.count,
              Set(messages.map(\.id)).count == messages.count,
              memories.allSatisfy({ ["preference", "topic"].contains($0.kind) && !$0.text.isEmpty && $0.text.count <= 300 && $0.quote.count <= 1200 }),
              messages.allSatisfy({ ["user", "assistant"].contains($0.role) && !$0.content.isEmpty && $0.content.count <= 12000 && $0.sources.count <= 10 && ($0.stickerID == nil || CompanionSticker.find($0.stickerID) != nil) && ($0.nameProposal == nil || ($0.role=="assistant" && CompanionRules.cleanName($0.nameProposal!)==$0.nameProposal)) && ($0.rememberedText?.count ?? 0)<=300 && ($0.replacedMemories?.count ?? 0)<=8 && ($0.replacedMemories ?? []).allSatisfy({ !$0.text.isEmpty && $0.text.count<=300 && $0.quote.count<=1200 && ["preference","topic"].contains($0.kind) }) })
        else { throw AppError.message("伙伴资料内容无效或容量已满，请先导出备份并清理不需要的聊天或记忆") }
    }
}

enum CompanionRules {
    static func cleanName(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 20,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !value.contains("<|"), !value.contains("|>") else { return nil }
        return value
    }
    /// Statements may rename her; suggestions and bare names require a naming context.
    static func proposedName(_ input: String, history:[CompanionMessage] = []) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains("如果"), !value.contains("假如"), !value.contains("假设") else { return nil }
        let pattern = #"^(?:记住[，,：:]?\s*)?(?:我说[，,：:]?\s*)?(?:那)?(?:以后(?:就)?叫你|从现在起叫你|(?:我)?给你(?:取个名字叫|取名字叫|起个名字叫|取名(?:为|叫)?|起名(?:为|叫)?)|把你的名字改成|你的名字(?:就叫|是|叫)|你就叫)[「『“\"]?(.+?)[」』”\"]?(?:吧|啦)?[。！!]*$"#
        if !value.contains("？"),!value.contains("?"), let name=captureName(value,pattern:pattern) {return name}
        let last=history.last
        let invited=last?.role=="assistant" && last!.content.range(of:"给我取个名字|你想怎么叫我|想给我取什么名字|你想叫我什么|那我叫什么名字",options:.regularExpression) != nil
        let correcting=last?.renamedTo != nil || history.suffix(2).contains {$0.role=="user" && proposedName($0.content) != nil}
        if correcting,let name=captureName(value,pattern:#"^(?:不[，,]?\s*)?(?:就是|我说的是|名字是)[「『“\"]?(.+?)[」』”\"]?[。！!]*$"#) {return name}
        guard invited else {return nil}
        if let name=captureName(value,pattern:#"^[「『“\"]?(.+?)[」』”\"]?(?:这个名字)?(?:怎么样|如何)[？?。！!]*$"#) {return contextualName(name)}
        // The mixed welcome also asks about the day: only a name suggestion is unambiguous there.
        guard !last!.content.contains("今天过得怎么样") else {return nil}
        return contextualName(value.trimmingCharacters(in:CharacterSet(charactersIn:"。！!「」『』“”\"")))
    }
    private static func captureName(_ value:String,pattern:String)->String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return validProposedName(String(value[range]))
    }
    private static func validProposedName(_ name:String)->String? {
        guard name.range(of: #"[，。！？；：\n,;:<>?]|怎么样|好不好|还是|或者|然后|并且|的话|吗$|呢$"#, options: .regularExpression) == nil,
              !["嗯","嗯嗯","哦","好","好的","好呀","好吧","那好吧","行","可以","随便","你好","谢谢","再见","什么","什么名字","啥","谁","今天有点累","我一个人"].contains(name) else { return nil }
        return cleanName(name)
    }
    private static func contextualName(_ name:String)->String? {
        let words=String(name.filter {$0.isLetter || $0.isNumber})
        guard !words.isEmpty,!["嗯","嗯嗯","哦","好","好的","好呀","好吧","对","对的","是","是的","谢谢","名字","你的名字"].contains(words),
              name.range(of:"我|你|他说|她说|取名|起名|叫|今天|帮忙|以后|给你|吃饭|睡觉|累了|不想|不知道",options:.regularExpression)==nil else {return nil}
        return validProposedName(name)
    }
    static func newMemory(_ input: String) -> CompanionMemory? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("记住：") || text.hasPrefix("记住:") {
            let value = String(text.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 300 else { return nil }
            if value.range(of:#"^(?:我|其实我|以后叫我|请叫我)"#,options:.regularExpression) != nil,var fact=newMemory(value) {fact.quote=text;return fact}
            return CompanionMemory(text: value, kind: "topic", quote: text)
        }
        if let regex=try? NSRegularExpression(pattern:#"^(?:以后叫我|请叫我|我叫|我的名字是)([\p{Han}A-Za-z0-9· _-]{1,20}?)(?:吧)?[。！!]*$"#),
           let match=regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let range=Range(match.range(at:1),in:text) {
            let name=String(text[range]).trimmingCharacters(in:.whitespaces)
            if !name.hasPrefix("你"),!name.hasPrefix("他"),!name.hasPrefix("她"),!name.contains("去"),!name.isEmpty {return CompanionMemory(text:"用户称呼："+name,quote:text)}
        }
        let fact=text.replacingOccurrences(of:#"^(?:其实|现在|其实现在)?我(?:现在)?"#,with:"",options:.regularExpression)
        guard text.count <= 100, text != fact, fact.range(of: #"^(?:喜欢|不喜欢|更喜欢)[^？?。！!\n]+[。！!]*$"#, options: .regularExpression) != nil,
              fact.range(of:"如果|假如|要是|以前|过去|但是|不过|但|也不|吗|呢|就|，|,",options:.regularExpression) == nil else { return nil }
        let clean=fact.trimmingCharacters(in:CharacterSet(charactersIn:"。！!" )).replacingOccurrences(of:"了$",with:"",options:.regularExpression)
        return CompanionMemory(text: clean, quote: text)
    }
    static func needsWeb(_ question: String, previousWeb: Bool = false) -> Bool {
        if question.range(of: "写.*(故事|小说|诗)|假设|假如|不要联网|不用联网", options: .regularExpression) != nil { return false }
        if question.range(of: "帮我查|查一下|查查|搜索|联网|核实|天气|气温|下雨|新闻|最新|热梗|什么梗|这个梗|流行语|营业时间|票价|实时|今日汇率|当前汇率|现在.*(价格|汇率|版本)", options: .regularExpression) != nil { return true }
        return previousWeb && question.count <= 50 && question.range(of: "明天|后天|周末|那.+呢|那里|这个|那个", options: .regularExpression) != nil
    }
    static func selfReply(_ question: String, profile: CompanionProfile) -> String? {
        let value = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: #"^(?:你|那你)(?:是男生还是女生|是男的还是女的|是什么性别|的性别是什么|是女生吗|是女孩吗)[？?。！!]*$"#, options: .regularExpression) != nil { return "我是女生呀。" }
        if value.range(of: #"^(?:你|那你)(?:叫什么|叫什么名字|叫啥|叫啥名字|的名字是什么|名字是什么|的名字是啥|是谁)[？?。！!]*$"#, options: .regularExpression) != nil {
            return profile.name.map { "我叫\($0)呀。" } ?? "还没取名字呢，你想怎么叫我？"
        }
        if value.range(of: #"^(?:你|那你)(?:是什么样子的|长什么样|穿什么衣服|今天穿什么|是什么样子|的形象是什么)[？?。！!]*$"#, options: .regularExpression) != nil || value.range(of:#"^(?:你穿的|你穿着|你的头发|你的眼睛|你的服装|你的穿搭)"#,options:.regularExpression) != nil { return "我的形象是\(profile.appearance)" }
        return nil
    }
    /// Explicit recall uses recorded evidence; a small fine-tuned model must not swap subjects.
    static func recallReply(_ question:String, data:CompanionData, history:[CompanionMessage])->String? {
        let q=question.trimmingCharacters(in:.whitespacesAndNewlines)
        if q.range(of:#"^(?:我叫什么|我叫什么名字|我的名字是什么|你记得我的名字吗|你记得我叫什么吗)[？?。！!]*$"#,options:.regularExpression) != nil {
            return data.memories.last(where:{$0.text.hasPrefix("用户称呼：")}).map {"你让我叫你\($0.text.dropFirst(5))。"} ?? "你的称呼我还没记下来，你想让我怎么叫你？"
        }
        if q.range(of:#"^我(?:刚才|刚刚)(?:说|聊|提到).*[？?。！!]*$"#,options:.regularExpression) != nil {
            if history.isEmpty,!CompanionContext.summary(data).isEmpty {return nil}
            guard let message=history.last(where:{$0.role=="user"}) else {return "这段对话里还没有更早的发言，你愿意再告诉我一次吗？"}
            return "你刚才说：“\(message.content)”"
        }
        guard q.count<=100,q.range(of:"我喜欢什么|我喜欢哪|我不喜欢什么|我的偏好|记得我.*喜欢|我喜欢.*记得|关于我的记忆",options:.regularExpression) != nil else {return nil}
        let dislikes=q.contains("不喜欢")
        let topics=["地方","颜色","食物","音乐","运动","水果","电影","穿搭"].filter {q.contains($0)}
        let candidates=data.memories.filter {memory in
            memory.kind=="preference" && memory.text.range(of:#"^(?:喜欢|更喜欢|不喜欢)"#,options:.regularExpression) != nil && (dislikes ? memory.text.hasPrefix("不喜欢"):!memory.text.hasPrefix("不喜欢")) &&
            (topics.isEmpty || topics.contains(where:{memory.text.contains($0)}))
        }
        let facts=relevantMemories(candidates,query:q).prefix(2).map(\.text)
        guard !facts.isEmpty else {return "这点我还没记下来，你愿意告诉我吗？"}
        return "我记下的是：\(facts.joined(separator:"；"))。"
    }
    static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "<|", with: "＜｜").replacingOccurrences(of: "|>", with: "｜＞")
    }
    static func relevantMemories(_ values:[CompanionMemory], query:String)->[CompanionMemory] {
        let characters=Array(query.lowercased().filter {$0.isLetter || $0.isNumber})
        let pairs=Set(zip(characters,characters.dropFirst()).map {String([$0.0,$0.1])})
        func score(_ value:CompanionMemory)->Int {pairs.reduce(0) {$0+(value.text.lowercased().contains($1) ? 1:0)}}
        return Array(values.sorted {left,right in let a=score(left),b=score(right);return a==b ? left.date>right.date:a>b}.prefix(8))
    }
    static func mayInitiate(data: CompanionData, visible: Bool, active: Bool, editing: Bool, draft: String, busy: Bool, now: Date, lastInteraction: Date) -> Bool {
        let activeMessages=CompanionContext.current(data)
        if let last=activeMessages.last,last.role=="assistant",last.content.contains("？") || last.content.contains("?") {return false}
        let lastStatement=activeMessages.last {message in message.role=="user" && !["嗯","嗯嗯","好","好的","哦"].contains(message.content)}
        if let lastStatement,lastStatement.content.range(of:#"^(?:今天)?(?:晚安|再见|先不聊了|不想聊了|别主动找我|我要休息了|我睡了)[。！!～~]*$"#,options:.regularExpression) != nil {return false}
        return !CompanionContext.full(data) && data.profile.proactive && visible && active && !editing && draft.isEmpty && !busy &&
        !data.awaitingProactiveReply && now.timeIntervalSince(lastInteraction) >= 30 &&
        now.timeIntervalSince(data.lastProactive ?? .distantPast) >= 600 && data.messages.count < CompanionData.messageLimit-1
    }
}

import Foundation

enum CompanionNaming {
    /// One upgrade-only repair for a confirmed name missed by older prose matching.
    /// Never overwrite an existing name, a saved rename/undo, or a later cancellation.
    static func recoverConfirmedName(in data:inout CompanionData) {
        guard data.profile.confirmationRecoveryChecked != true else {return}
        data.profile.confirmationRecoveryChecked=true
        guard data.profile.name==nil,!data.messages.contains(where:{$0.renamedTo != nil || $0.renamedFrom != nil}) else {return}
        let history=CompanionContext.current(data)
        for index in history.indices.reversed() where history[index].role=="user" && history[index].replyTo==nil && affirmative(history[index].content) {
            guard let name=pending(Array(history[..<index])) else {continue}
            let later=history.suffix(from:history.index(after:index))
            guard !later.contains(where:{$0.role=="user" && $0.content.range(of:"取消取名|撤销名字|不要这个名字|别叫|不叫|名字不要|名字不是",options:.regularExpression) != nil}) else {return}
            guard data.messages.count<CompanionData.messageLimit else {return}
            data.profile.name=name
            // Do not hide an unanswered weather/sticker turn behind a synthetic receipt.
            if data.messages.last?.role != "user" {data.messages.append(CompanionMessage(role:"assistant",content:"你之前确认的名字是\(name)，已经补存好了。",source:"伙伴资料",renamedFrom:"",renamedTo:name))}
            return
        }
    }
    static func affirmative(_ text:String) -> Bool {
        let clean=text.trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"。！!～~"))
        if ["对","对的","是","是的","好","好的","嗯","就这个","就叫这个","确认","没错","对呀","就是这个名字"].contains(clean) {return true}
        return clean.range(of:#"^(?:(?:对|对的|是|是的|好|好的|嗯|没错|确认|确定)(?:[，, ]?(?:就|就是|就用|用|就叫|叫)(?:这个|这个名字))?|就叫这个|就是这个名字|就这个)(?:吧|呀|啊|啦|哦)?$"#,options:.regularExpression) != nil
    }
    /// Recover only a direct confirmation question backed by a recent USER-provided name.
    /// Assistant prose alone is never evidence, and an unrelated reply expires this context.
    static func pending(_ history:[CompanionMessage]) -> String? {
        guard let last=history.last,last.role=="assistant" else { return nil }
        if let name=last.nameProposal { return CompanionRules.cleanName(name) }
        guard last.replyTo==nil,last.content.range(of:"[？?]|确认|确定",options:.regularExpression) != nil,
              last.content.range(of:"如果|假如|假设|比如|例如|不要|不叫|别叫|取消",options:.regularExpression)==nil else {return nil}
        let earlier=Array(history.dropLast().suffix(5))
        // Ground the candidate in a real, recent user turn, then require a direct self-naming
        // relationship in the assistant's question. Quoting a name somewhere is insufficient.
        for user in earlier.reversed() where user.role=="user" && user.replyTo==nil {
            let raw=user.content.trimmingCharacters(in:CharacterSet(charactersIn:"。！!「」『』“”\" "))
            guard let name=CompanionRules.proposedName(user.content) ?? CompanionRules.contextualName(raw) else {continue}
            let escaped=NSRegularExpression.escapedPattern(for:name)
            let quoted="[「『“\"]?"+escaped+"[」』”\"]?"
            let relation="(?:叫我|我(?:就|以后|应该|要)?叫|让我叫|我的名字(?:是|叫|改成)|把我的名字改成)\\s*"+quoted+"|"+quoted+"\\s*(?:当|作为|做|是)(?:我)?的?名字|"+quoted+"\\s*(?:是)?给我(?:的|取的|起的)名字"
            guard last.content.range(of:relation,options:.regularExpression) != nil else {continue}
            let index=earlier.firstIndex(where:{$0.id==user.id})!
            let later=earlier.suffix(from:earlier.index(after:index)).filter {$0.role=="user"}
            guard later.allSatisfy({clarification($0.content)}) else {return nil}
            return name
        }
        return nil
    }
    static func clarification(_ text:String)->Bool {
        ["名字","你的名字","我说你的名字","给你取名字","取名"].contains(text.trimmingCharacters(in:CharacterSet(charactersIn:"。！! ")))
    }
    static func isNamingRequest(_ question:String,history:[CompanionMessage])->Bool {
        let q=question.trimmingCharacters(in:.whitespacesAndNewlines)
        guard q.range(of:"如果|假如|假设|故事|引用|原样|翻译|我朋友|同事|我叫|我的名字|他叫|她叫|别改|不改|不要|取消|不叫|撤销",options:.regularExpression)==nil else {return false}
        if affirmative(q) {return pending(history) != nil}
        if clarification(q) {return history.last?.role=="assistant" && history.last!.content.range(of:"名字|取名|叫我",options:.regularExpression) != nil}
        if CompanionRules.proposedName(q) != nil || q.range(of:"给你.{0,8}(?:名|叫)|你的名字|改名|叫你|以后你.{0,8}名字|取个名|起个名",options:.regularExpression) != nil {return true}
        return CompanionRules.contextualName(q) != nil && history.last?.role=="assistant" && history.last!.content.range(of:"给我取个名字|给我取名|你想怎么叫我|想给我取什么名字|你想叫我什么|我还没取名",options:.regularExpression) != nil
    }
    /// Allows a short clarification (e.g. “名字”) to refer to the immediately discussed candidate.
    static func validEvidence(name:String,quote:String,question:String,history:[CompanionMessage]) -> Bool {
        guard isNamingRequest(question,history:history),!quote.isEmpty,quote.contains(name),CompanionRules.cleanName(name)==name else { return false }
        if question.contains(quote) { return true }
        if affirmative(question),pending(history)==name {return history.suffix(5).contains {$0.role=="user" && $0.replyTo==nil && $0.content.contains(quote)}}
        let clean=question.trimmingCharacters(in:CharacterSet(charactersIn:"。！! "))
        guard ["名字","你的名字","我说你的名字","给你取名字","取名"].contains(clean),
              let last=history.last,last.role=="assistant",last.content.range(of:"名字|取名|叫我",options:.regularExpression) != nil,
              let user=history.dropLast().last,user.role=="user",user.content.contains(quote) else { return false }
        return user.content.trimmingCharacters(in:CharacterSet(charactersIn:"。！!「」『』“”\" "))==name || CompanionRules.proposedName(user.content)==name
    }
}

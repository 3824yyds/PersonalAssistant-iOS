import Foundation

enum CompanionNaming {
    static func affirmative(_ text:String) -> Bool {
        let clean=text.trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"。！!～~"))
        return ["对","对的","是","是的","好","好的","嗯","就这个","就叫这个","确认","没错","对呀","就是这个名字"].contains(clean)
    }
    /// Recover only a direct confirmation question backed by a recent USER-provided name.
    /// Assistant prose alone is never evidence, and an unrelated reply expires this context.
    static func pending(_ history:[CompanionMessage]) -> String? {
        guard let last=history.last,last.role=="assistant" else { return nil }
        if let name=last.nameProposal { return CompanionRules.cleanName(name) }
        guard last.content.range(of:"对吧|对吗|确认一下|确认后|可以吗",options:.regularExpression) != nil,
              let regex=try? NSRegularExpression(pattern:#"(?:叫我|我的名字(?:就)?叫|把我的名字改成)[“「『\"]([^”」』\"\n]{1,20})[”」』\"]"#),
              let match=regex.firstMatch(in:last.content,range:NSRange(last.content.startIndex...,in:last.content)),
              let range=Range(match.range(at:1),in:last.content) else { return nil }
        let name=String(last.content[range])
        guard CompanionRules.cleanName(name)==name else { return nil }
        let earlier=Array(history.dropLast().suffix(5))
        guard let evidence=earlier.lastIndex(where:{message in
            message.role=="user" && (message.content.trimmingCharacters(in:CharacterSet(charactersIn:"。！!「」『』“”\" "))==name || CompanionRules.proposedName(message.content)==name)
        }) else { return nil }
        let later=earlier.suffix(from:earlier.index(after:evidence)).filter { $0.role=="user" }
        guard later.allSatisfy({ ["名字","你的名字","我说你的名字","给你取名字","取名"].contains($0.content.trimmingCharacters(in:CharacterSet(charactersIn:"。！! "))) }) else { return nil }
        return name
    }
    /// Allows a short clarification (e.g. “名字”) to refer to the immediately discussed candidate.
    static func validEvidence(name:String,quote:String,question:String,history:[CompanionMessage]) -> Bool {
        guard !quote.isEmpty,quote.contains(name),CompanionRules.cleanName(name)==name else { return false }
        if question.contains(quote) { return true }
        let clean=question.trimmingCharacters(in:CharacterSet(charactersIn:"。！! "))
        guard ["名字","你的名字","我说你的名字","给你取名字","取名"].contains(clean),
              let last=history.last,last.role=="assistant",last.content.range(of:"名字|取名|叫我",options:.regularExpression) != nil,
              let user=history.dropLast().last,user.role=="user",user.content.contains(quote) else { return false }
        return user.content.trimmingCharacters(in:CharacterSet(charactersIn:"。！!「」『』“”\" "))==name || CompanionRules.proposedName(user.content)==name
    }
}

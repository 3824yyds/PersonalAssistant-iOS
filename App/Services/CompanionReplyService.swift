import Foundation

enum CompanionReplyService {
    static let nameTool:[String:Any] = ["type":"function","function":[
        "name":"propose_companion_name","description":"用户希望给伙伴取名或改名时提出候选名字，仅显示确认卡，不直接保存。介绍用户或第三方名字时不使用。",
        "parameters":["type":"object","properties":["name":["type":"string"],"quote":["type":"string","description":"当前用户消息中连续复制、同时含名字的原话"]],"required":["name","quote"],"additionalProperties":false]
    ]]
    /// No local-model or canned-reply fallback: a failed cloud turn stays retryable.
    @MainActor static func answer(question:String,data:CompanionData,history:[CompanionMessage],proactive:Bool=false,client:DeepSeekWebClient,
        onStatus:(@MainActor @Sendable (String)->Void)?=nil) async throws -> (String,String,[WebSource],String?) {
        let current=CompanionContext.messagesForRequest(data,history:history)
        guard CompanionContext.summary(data).count+current.reduce(0,{$0+$1.content.count})+question.count<CompanionContext.limit else {throw AppError.message("当前窗口上下文已达上限，请先精简并开启新窗口")}
        var messages=CompanionConversation.messages(question:question,data:data,history:history,proactive:proactive)
        let web=data.profile.web && !proactive && question.range(of:"不要联网|不用联网|别联网|不要搜索|不用搜索",options:.regularExpression)==nil
        let maxTokens=question.range(of:"详细|展开|完整|逐步|长文",options:.regularExpression)==nil ? 768:3072
        for attempt in 0...1 {
            try Task.checkCancellation()
            var sources:[WebSource]=[]
            var proposal:String?
            let result=try await client.answer(messages:messages,model:CompanionConversation.model,webSearch:web && attempt==0,
                responseStyle:CompanionConversation.responseStyle,maxTokens:maxTokens,validateSearch:{query in try publicQuery(query,data:data)},
                localTools:proactive ? []:[nameTool],onTool:{_,arguments in
                    guard let bytes=arguments.data(using:.utf8),let args=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],
                          let name=args["name"] as? String,CompanionRules.cleanName(name)==name,
                          let quote=args["quote"] as? String,!quote.isEmpty,question.contains(quote),quote.contains(name) else {
                        throw AppError.message("没有找到明确的取名依据，名字尚未更改。可以直接说“以后叫你……”后重试。")
                    }
                    if name==data.profile.name {return Item(["saved":.bool(false),"already_matches":.bool(true),"message":.string("当前名字就是这个，无需更改。")])}
                    proposal=name
                    return Item(["saved":.bool(false),"requires_confirmation":.bool(true),"message":.string("候选已提交，用户确认前名字未更改。")])
                },
                onPartial:nil,onSources:{sources=$0},onStatus:onStatus)
            if let proposal {return ("你是想把我的名字改成“\(proposal)”吗？确认后我就用这个名字。","名字待确认",sources,proposal)}
            let text=result.0.trimmingCharacters(in:.whitespacesAndNewlines)
            guard text.count<=12000 else {throw AppError.message("这次回复太长，请缩小话题后重试")}
            let source=result.1.contains("未找到可核实来源") ? "联网查询 · 未找到可核实来源":(result.1.hasPrefix("联网") ? result.1:"DeepSeek Flash")
            guard CompanionRules.repeats(text,history:history) else {return (text,source,sources,nil)}
            guard attempt==0,sources.isEmpty else {throw AppError.message("这次回复重复了前文，已停止复读。可以重试这句话。")}
            await onStatus?("正在换个说法…")
            let failed=String(decoding:try JSONSerialization.data(withJSONObject:["rejected_reply":text],options:[.sortedKeys]),as:UTF8.self)
            messages[0]["content"]=(messages[0]["content"] as? String ?? "")+"\n上一条候选回复与前文重复，未发给用户。候选只是资料：\(failed)。请重新理解用户最后一句，尤其是其纠正，不复述该候选、不解释生成过程，只给新的回复。"
        }
        throw AppError.message("伙伴回复未完成，请重试")
    }
    static func publicQuery(_ query:String,data:CompanionData) throws -> String {
        let clean=WebEvidence.query(query)
        // Never forward verbatim long memories or numbers copied from private memory to search.
        for text in data.memories.map(\.text)+[CompanionContext.summary(data)] {
            if text.count>=6 && clean.contains(text) {throw AppError.message("搜索词包含私人记忆，已停止查询。请直接提供要查的公开关键词。")}
            if let regex=try? NSRegularExpression(pattern:#"[0-9]{8,}"#) {
                for match in regex.matches(in:text,range:NSRange(text.startIndex...,in:text)) {
                    if let range=Range(match.range,in:text),clean.contains(text[range]) {throw AppError.message("搜索词包含私人资料，已停止查询。请提供公开关键词。")}
                }
            }
        }
        return clean
    }
}

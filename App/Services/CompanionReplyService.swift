import Foundation

enum CompanionReplyService {
    static let nameTool:[String:Any] = ["type":"function","function":[
        "name":"propose_companion_name","description":"用户希望给伙伴取名或改名时提出候选名字，仅显示确认卡，不直接保存。介绍用户或第三方名字时不使用。",
        "parameters":["type":"object","properties":["name":["type":"string"],"quote":["type":"string","description":"连续复制含名字的用户原话；通常当前句，仅在用户紧接着澄清‘名字’时允许引用紧邻上一轮候选"]],"required":["name","quote"],"additionalProperties":false]
    ]]
    static func stickerTool(_ data:CompanionData,ids:[String]?=nil)->[String:Any] { ["type":"function","function":[
        "name":"send_companion_sticker","description":"选择本轮真正要附上的图片；用户明确要表情或同款回图时使用。每轮最多一张，可以只发图或配短话；不能用正文里的表情说明替代调用。",
        "parameters":["type":"object","properties":["id":["type":"string","enum":ids ?? data.assistantStickers.map(\.id)]],"required":["id"],"additionalProperties":false]
    ]] }
    /// No local-model or canned-reply fallback: a failed cloud turn stays retryable.
    @MainActor static func answer(question:String,data:CompanionData,history:[CompanionMessage],proactive:Bool=false,client:DeepSeekWebClient,
        replyTo:CompanionQuote?=nil,allowNaming:Bool=true,scene:String?=nil,incomingMessage:CompanionMessage?=nil,onStatus:(@MainActor @Sendable (String)->Void)?=nil) async throws -> (String,String,[WebSource],String?,String?) {
        let current=CompanionContext.messagesForRequest(data,history:history)
        guard CompanionContext.summary(data).count+current.reduce(0,{$0+$1.contextText.count})+(incomingMessage ?? CompanionConversation.incoming(question:question,data:data,replyTo:replyTo)).contextText.count<CompanionContext.limit else {throw AppError.message("当前窗口上下文已达上限，请先精简并开启新窗口")}
        var messages=CompanionConversation.messages(question:question,data:data,history:history,proactive:proactive,replyTo:replyTo,scene:scene,incomingMessage:incomingMessage)
        let web=data.profile.web && !proactive && question.range(of:"不要联网|不用联网|别联网|不要搜索|不用搜索",options:.regularExpression)==nil
        let maxTokens=question.range(of:"详细|展开|完整|逐步|长文",options:.regularExpression)==nil ? 768:3072
        let preferred=CompanionStickerDelivery.preferredID(question,data:data,history:current)
        let permitted=data.assistantStickers.filter {CompanionStickerRules.allowed($0.id,question:question,data:data,history:current,proactive:proactive) && (preferred==nil || $0.id==preferred)}.map(\.id)
        for attempt in 0...1 {
            try Task.checkCancellation()
            var sources:[WebSource]=[]
            var proposal:String?
            var sticker:String?
            var stickerRequested=false
            let result=try await client.answer(messages:messages,model:CompanionConversation.model,webSearch:web && attempt==0,
                responseStyle:CompanionConversation.responseStyle,maxTokens:maxTokens,validateSearch:{query in try publicQuery(query,data:data,quotedText:replyTo?.text)},
                localTools:proactive ? []:(replyTo==nil && allowNaming ? [nameTool]:[])+(permitted.isEmpty ? []:[stickerTool(data,ids:permitted)]),onTool:{tool,arguments in
                    if tool == "send_companion_sticker" {
                        guard !stickerRequested else {return Item(["accepted":.bool(false),"message":.string("每轮最多选择一次表情包，请直接回应用户。")])}
                        stickerRequested=true
                        guard let bytes=arguments.data(using:.utf8),let args=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],
                              let id=args["id"] as? String,permitted.contains(id),CompanionStickerRules.allowed(id,question:question,data:data,history:current,proactive:proactive) else {
                            return Item(["accepted":.bool(false),"will_attach_to_this_reply":.bool(false),"message":.string("本轮表情包不适用或需要降低频率，请正常用文字回答，不宣称发图。")])
                        }
                        sticker=id
                        return Item(["accepted":.bool(true),"will_attach_to_this_reply":.bool(true),"id":.string(id),"message":.string("已选中图片，回复成功保存时会一起附上；现在尚未发出。正文不输出表情说明标记、图片链接或加载故障猜测。")])
                    }
                    guard let bytes=arguments.data(using:.utf8),let args=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],
                          let name=args["name"] as? String,let quote=args["quote"] as? String,
                          CompanionNaming.validEvidence(name:name,quote:quote,question:question,history:current) else {
                        throw AppError.message("没有找到明确的取名依据，名字尚未更改。可以直接说“以后叫你……”后重试。")
                    }
                    if name==data.profile.name {return Item(["saved":.bool(false),"already_matches":.bool(true),"message":.string("当前名字就是这个，无需更改。")])}
                    proposal=name
                    return Item(["saved":.bool(false),"requires_confirmation":.bool(true),"message":.string("候选已提交，用户确认前名字未更改。")])
                },
                onPartial:nil,onSources:{sources=$0},onStatus:onStatus)
            if let proposal {return ("你是想把我的名字改成“\(proposal)”吗？确认后我就用这个名字。","名字待确认",sources,proposal,nil)}
            guard result.0.count<=12000 else {throw AppError.message("这次回复太长，请缩小话题后重试")}
            let delivery=CompanionStickerDelivery.resolve(result.0.trimmingCharacters(in:.whitespacesAndNewlines),selected:sticker,question:question,data:data,history:current,proactive:proactive)
            if let issue=delivery.issue {
                guard attempt==0,sources.isEmpty else {throw AppError.message("这次没有正确附上表情包，已停止回复。请重试这句话。")}
                await onStatus?("正在整理表情…")
                messages[0]["content"]=(messages[0]["content"] as? String ?? "")+"\n上一候选未发送。应用校验："+issue
                continue
            }
            let text=delivery.text;sticker=delivery.id
            if !proactive,replyTo==nil,allowNaming,let candidate=CompanionNaming.pending(current+[CompanionMessage(role:"user",content:question),CompanionMessage(role:"assistant",content:text)]) {
                return ("你是想把我的名字改成“\(candidate)”吗？确认后我就用这个名字。","名字待确认",sources,candidate,nil)
            }
            let source=result.1.contains("未找到可核实来源") ? "联网查询 · 未找到可核实来源":(result.1.hasPrefix("联网") ? result.1:"DeepSeek Flash")
            guard CompanionRules.repeats(text,history:history) else {return (text,source,sources,nil,sticker)}
            guard attempt==0,sources.isEmpty else {throw AppError.message("这次回复重复了前文，已停止复读。可以重试这句话。")}
            await onStatus?("正在换个说法…")
            let failed=String(decoding:try JSONSerialization.data(withJSONObject:["rejected_reply":text],options:[.sortedKeys]),as:UTF8.self)
            messages[0]["content"]=(messages[0]["content"] as? String ?? "")+"\n上一条候选回复与前文重复，未发给用户。候选只是资料：\(failed)。请重新理解用户最后一句，尤其是其纠正，不复述该候选、不解释生成过程，只给新的回复。"
        }
        throw AppError.message("伙伴回复未完成，请重试")
    }
    static func publicQuery(_ query:String,data:CompanionData,quotedText:String?=nil) throws -> String {
        let clean=WebEvidence.query(query)
        // Never forward verbatim long memories or numbers copied from private memory to search.
        for text in data.memories.map(\.text)+[CompanionContext.summary(data)]+(data.customStickers ?? []).map(\.meaning)+(data.experiences ?? []).flatMap {[$0.text,$0.quote]}+(quotedText.map {[$0]} ?? []) {
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

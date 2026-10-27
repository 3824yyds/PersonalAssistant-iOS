import Foundation

/// Converts only known, trailing legacy attachment annotations. Text never names a file or URL.
enum CompanionStickerDelivery {
    /// Ephemeral stream preview only; never expose unfinished attachment metadata or
    /// an unverified send receipt. The final validated message remains atomic with its image.
    static func preview(_ text:String,question:String,data:CompanionData)->String {
        guard !claimsMissingImage(text) else {return ""}
        if discussingText(question) {return text}
        var clean=annotations(text,data:data).text
        let markers=["[表情", "【表情", "<sticker", "{\"sticker", "{\"attached_sticker"]
        for marker in markers {
            if let range=clean.range(of:marker) {clean=String(clean[..<range.lowerBound])}
        }
        if let opening=clean.lastIndex(where:{"[【<{".contains($0)}),markers.contains(where:{$0.hasPrefix(String(clean[opening...]))}) {clean=String(clean[..<opening])}
        return clean.trimmingCharacters(in:.whitespacesAndNewlines)
    }
    struct Annotation {
        var text:String
        var ids:[String]
        var found:Bool
        var unknown:Bool
    }
    static func annotations(_ text:String,data:CompanionData)->Annotation {
        guard let regex=try? NSRegularExpression(pattern:#"[\[【]表情包\s*[：:]\s*([^\]\n】]+)[\]】](?=\s*(?:$|\n))"#) else {return Annotation(text:text,ids:[],found:false,unknown:false)}
        let matches=regex.matches(in:text,range:NSRange(text.startIndex...,in:text))
        var ids:[String]=[],unknown=false,clean=text
        for match in matches {
            guard let range=Range(match.range(at:1),in:text) else {continue}
            let body=String(text[range]).trimmingCharacters(in:.whitespacesAndNewlines)
            let candidates=data.availableStickers.filter {sticker in
                [sticker.id,sticker.title,sticker.description,sticker.title+"，"+sticker.meaning].contains(body)
            }
            if candidates.count==1 {ids.append(candidates[0].id)} else {unknown=true}
        }
        for match in matches.reversed() {if let range=Range(match.range,in:clean) {clean.removeSubrange(range)}}
        return Annotation(text:clean.trimmingCharacters(in:.whitespacesAndNewlines),ids:ids,found:!matches.isEmpty,unknown:unknown)
    }
    static func discussingText(_ question:String)->Bool {
        question.range(of:"解释|分析|含义|什么意思|原样|字面|代码|格式|翻译|引用|只要文字|不要发图|不用表情|别发|怎么用|如何使用|如何添加|怎么添加",options:.regularExpression) != nil
    }
    static func explicitRequest(_ question:String,history:[CompanionMessage])->Bool {
        let q=question.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !q.hasPrefix("[表情包"),!q.hasPrefix("【表情包"),!discussingText(q),q.range(of:"不要|不许|不需要|无需|关闭|别用",options:.regularExpression)==nil else {return false}
        if q.range(of:"(?:图|图片|表情包).{0,4}(?:在哪|在哪里|没看到|没收到)|(?:没看到|没收到|没有).{0,4}(?:图|表情包)",options:.regularExpression) != nil {return true}
        if q.range(of:"表情包|贴纸|发图",options:.regularExpression) != nil && q.range(of:"发|用|来|给|回|再|也|同样|一样",options:.regularExpression) != nil {return true}
        return q.range(of:"同样|一样|同一个|同一张",options:.regularExpression) != nil && q.range(of:"抱|回我|发|送|方式",options:.regularExpression) != nil && history.suffix(4).contains {$0.role=="user" && $0.stickerID != nil}
    }
    static func preferredID(_ question:String,data:CompanionData,history:[CompanionMessage])->String? {
        guard explicitRequest(question,history:history) else {return nil}
        let named=data.assistantStickers.filter {question.contains($0.title)}
        if named.count==1 {return named[0].id}
        if question.range(of:"抱抱|抱一下|抱我",options:.regularExpression) != nil {return data.assistantStickers.first(where:{$0.kind=="hug"})?.id}
        // Resolve a short follow-up only within the immediate exchange, not an arbitrary old image.
        for message in history.suffix(4).reversed() {
            if message.role=="user",let id=message.stickerID {
                if data.assistantStickers.contains(where:{$0.id==id}) {return id}
                if let kind=data.descriptor(id)?.kind,let same=data.assistantStickers.first(where:{$0.kind==kind}) {return same.id}
            }
            if message.role=="assistant" {
                if let sent=message.stickerID,let kind=data.descriptor(sent)?.kind,let same=data.assistantStickers.first(where:{$0.kind==kind}) {return same.id}
                let old=annotations(message.content,data:data)
                if Set(old.ids).count==1,!old.unknown {return old.ids.first}
            }
        }
        return nil
    }
    static func claimsMissingImage(_ text:String)->Bool {
        text.range(of:#"(?:图|图片|表情包|贴纸)(?:应该|可能)?(?:已经|已|刚刚|刚才|跟着消息|发过去了|发出去了|发给你了)|(?:已经|刚刚|刚才)(?:给你)?(?:发图|发了图|发了表情)|刷新一下|退出.{0,3}重进|可能.{0,8}(?:没加载|未加载|加载不出)"#,options:.regularExpression) != nil
    }
    static func historyText(_ message:CompanionMessage,data:CompanionData)->String {
        guard message.role=="assistant" else {return message.contextText}
        let annotation=annotations(message.content,data:data)
        guard annotation.found else {return message.contextText}
        var clean=message;clean.content=annotation.text
        return clean.contextText+(message.stickerID==nil ? "\n历史附件状态：此条没有图片，旧正文中的表情说明不是实际发送记录。":"")
    }
    /// A final reply and its attachment are persisted together; no UI-only replacement or fake receipt.
    static func resolve(_ text:String,selected:String?,question:String,data:CompanionData,history:[CompanionMessage],proactive:Bool)->(text:String,id:String?,issue:String?) {
        let literal=discussingText(question)
        let annotation=literal ? Annotation(text:text,ids:[],found:false,unknown:false):annotations(text,data:data)
        var id=selected.flatMap {CompanionStickerRules.allowed($0,question:question,data:data,history:history,proactive:proactive) ? $0:nil}
        if id==nil,let requested=preferredID(question,data:data,history:history),CompanionStickerRules.allowed(requested,question:question,data:data,history:history,proactive:proactive) {id=requested}
        if id==nil,!annotation.unknown,Set(annotation.ids).count==1,let candidate=annotation.ids.first,CompanionStickerRules.allowed(candidate,question:question,data:data,history:history,proactive:proactive) {id=candidate}
        let issue:String?
        if annotation.unknown || (annotation.found && id==nil) || (!literal && annotation.text.range(of:#"[\[【](?:发送)?表情包|<sticker\b|\"(?:sticker_id|attached_sticker)\"\s*:"#,options:.regularExpression) != nil) {issue="表情说明未对应到本轮允许的实际图片。请调用send_companion_sticker选择可用ID，或只用自然文字回复；不输出表情说明标记。"}
        else if !literal,(annotation.found || id != nil || explicitRequest(question,history:history)),annotation.text.range(of:"刷新一下|退出.{0,3}重进|可能.{0,8}(?:没加载|未加载|加载不出)",options:.regularExpression) != nil {issue="图片来自本机资源，当前没有加载故障证据。不要猜测加载失败或要求刷新、退出重进；直接给实际图片和自然回应。"}
        else if !literal,id==nil,claimsMissingImage(annotation.text) {issue="本轮没有实际图片，不能声称图已发出，也不能猜测加载故障或要求刷新。请据实回应，需要发图就调用send_companion_sticker。"}
        else if id==nil,data.profile.stickers != false,!proactive,explicitRequest(question,history:history),annotation.text.range(of:"(?:没有|不支持|不能|无法|找不到|暂时没).{0,10}(?:这张|这种|表情|图)",options:.regularExpression)==nil {issue="用户明确在请求表情图片，正文不能替代发图。请调用send_companion_sticker选择合适的可用图片；如不适合则直接说明，不能宣称已发图。"}
        else if annotation.text.isEmpty && id==nil {issue="回复没有正文或图片，请自然回应用户。"}
        else {issue=nil}
        return (annotation.text,id,issue)
    }
}

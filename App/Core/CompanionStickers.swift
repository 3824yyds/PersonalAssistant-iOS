import Foundation

/// The model chooses a semantic ID, never an image URL or an arbitrary asset name.
struct CompanionSticker: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let meaning: String
    let scene: String
    var asset: String { "CompanionSticker_" + id }
    var description: String { title + "：" + meaning }
    static let all: [Self] = [
        .init(id:"happy",title:"开心",meaning:"开心、庆祝好消息，双手握拳欢呼，眼睛笑弯",scene:"好消息、共同庆祝；不用于难过或认真求助"),
        .init(id:"hug",title:"抱抱",meaning:"张开双臂，温柔地表示安慰、关心和支持",scene:"用户需要安慰或表达亲近；不替代实际建议"),
        .init(id:"confused",title:"疑惑",meaning:"歪头思考、带问号，表示没听懂或需要澄清",scene:"轻松的困惑；仍要用文字提出具体问题"),
        .init(id:"speechless",title:"无语",meaning:"半眯眼、无奈叹气，表示熟人之间轻轻吐槽",scene:"双方轻松互损；不用于脆弱倾诉、痛苦或温柔语气"),
        .init(id:"smug",title:"得意",meaning:"俏皮挑眉、自信的小笑，表示小得意或善意调侃",scene:"玩笑和小成就；不嘲笑用户的失败或脆弱"),
        .init(id:"goodnight",title:"晚安",meaning:"抱着枕头、困倦闭眼，表示晚安和结束聊天",scene:"用户道晚安或准备休息；不主动赶用户离开")
    ]
    static func find(_ id:String?) -> Self? { all.first { $0.id == id } }
    static var guide: String { all.map { "\($0.id)｜\($0.description)｜适用：\($0.scene)" }.joined(separator:"\n") }
}

enum CompanionStickerRules {
    static func preference(_ question:String) -> Bool? {
        switch question.trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"。！!")) {
        case "别发表情包","不要发表情包","关闭表情包","不用表情包了": return false
        case "开启表情包","可以发表情包","恢复表情包": return true
        default: return nil
        }
    }
    static func allowed(_ id:String,question:String,data:CompanionData,history:[CompanionMessage],proactive:Bool) -> Bool {
        guard CompanionSticker.find(id) != nil, data.profile.stickers != false, !proactive else { return false }
        let continuation=["嗯","嗯嗯","好","好的","谢谢","唉","😭","😢","💔","🥲"].contains(question.trimmingCharacters(in:.whitespacesAndNewlines))
        let emotionalContext=(continuation ? (history.last(where:{$0.role=="user"})?.content ?? ""):"")+question
        let sensitive=emotionalContext.range(of:"难过|伤心|崩溃|失恋|去世|抑郁|痛苦|害怕|生病|别开玩笑|别损|😭|😢|💔|🥲|😞|😔",options:.regularExpression) != nil
        if sensitive && !["hug","confused"].contains(id) { return false }
        if data.profile.effectiveTone() == .gentle && ["speechless","smug"].contains(id) { return false }
        let recent=history.filter { $0.role == "assistant" }
        // Even an explicit request cannot bypass the emotional suitability checks above.
        if question.range(of:"(?:发|来|给我).{0,10}表情包",options:.regularExpression) != nil && question.range(of:"别发|不要发|不用|关闭",options:.regularExpression) == nil { return true }
        guard !recent.suffix(2).contains(where: { $0.stickerID != nil }) else { return false }
        return !recent.suffix(5).contains { $0.stickerID == id }
    }
    static let emojiInstruction="""
    用户可以用emoji单独发言，原始emoji完整保留。结合上一句话、文字和语气理解，不把emoji当无意义字符，也不逐个机械解释。😂/🤣可能是笑或苦笑；😭可能是难过也可能是夸张感动；🙂/🙃可能礼貌、无奈或反讽；👍可能赞同或结束话题，不能据此自动更名或保存事实；🙏可能感谢、拜托或祈愿；💀可能是“笑死/绷不住”，不能仅据此判断真实危险。注意组合、肤色、旗帜、ZWJ和否定语境；不确定就轻轻确认。不要因一个emoji给用户做心理诊断，也不声称看见未提供的图片。示例：用户“又加班🙂”→接住无奈，不祝贺；“笑死🤣”→接玩笑；“今天真的撑不住了😭”→先关心，不毒舌。
    """
}

extension CompanionMessage {
    var contextText:String {
        guard let sticker=CompanionSticker.find(stickerID) else { return content }
        return content + "\n[本角色表情包：" + sticker.description + "]"
    }
}

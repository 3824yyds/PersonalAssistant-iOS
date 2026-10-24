import Foundation

public enum ChatPreferences {
    public static let styles=["default","professional","friendly","concise","candid"]
    public static let styleLabels=["default":"默认","professional":"专业","friendly":"友好","concise":"简洁","candid":"坦诚"]
    public static let levels=["less","default","more"]
    public static let levelLabels=["less":"减弱","default":"默认","more":"增强"]
    public static func prompt(_ value:Item) -> String {
        var instructions=["以下为用户的表达偏好，仅调整措辞和排版；不得改变事实、隐瞒不确定性或编造内容。"]
        switch value.text("style") {
        case "professional":instructions.append("使用专业、清晰、克制的语气，必要时解释术语。")
        case "friendly":instructions.append("使用自然友好的日常表达。")
        case "concise":instructions.append("先给核心答案，减少铺垫，除非用户要求详细说明。")
        case "candid":instructions.append("直接表达判断，有依据地指出问题，保持尊重。")
        default:break
        }
        for (key,less,more) in [
            ("warmth","减少寒暄和亲昵称呼，保持礼貌。","语气更温和、体贴，避免空洞恭维。"),
            ("enthusiasm","语气平静，减少感叹号。","表达适度热情，用具体内容鼓励用户。"),
            ("emoji","不主动使用表情符号。","在适合的日常交流中少量使用表情符号，严肃话题保持克制。"),
            ("visuals","优先短段落，仅在必要时使用表格或列表。","适合比较或步骤的信息优先使用简洁表格或清单；不强行把简单答案拆成多节，不声称生成未提供的图表。")
        ] {
            if value.text(key)=="less" {instructions.append(less)}
            if value.text(key)=="more" {instructions.append(more)}
        }
        return instructions.joined(separator:"\n")
    }
}
public enum ChatGreetings {
    public static let chat=["今天心情怎么样？","今天想聊点什么？","有什么新鲜事想分享？","有个想法想一起聊聊吗？","今天有什么小期待？","想从哪件事开始？","有什么我能帮你理一理？","忙里偷闲，聊一会儿吧。","最近有什么让你开心的事？","想聊生活，还是探索新知？","把今天的灵感说给我听。","今天想一起解决什么？"]
    public static let finance=["一起理清你的财务。","今天想先看看哪笔账？","一起把还款计划安排好。","有什么财务问题想聊聊？","从今天的收支开始吧。"]
    public static func next(after previous:String,finance mode:Bool=false)->String {
        (mode ? finance:chat).filter {$0 != previous}.randomElement() ?? "今天想聊点什么？"
    }
}

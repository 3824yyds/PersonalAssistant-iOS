import Foundation

enum CompanionVoiceMode:String,Codable,CaseIterable,Identifiable,Sendable {
    case text,voice,both
    var id:String {rawValue}
    var title:String {switch self {case .text:return "文字";case .voice:return "语音";case .both:return "语音和文字"}}
}

struct CompanionVoiceSettings:Codable,Equatable,Sendable {
    var female="Cherry"
    var male="Ethan"
    var rate:Double=1
    var autoPlay=false
    static let femaleVoices=["Cherry","Serena","Chelsie","Vivian"]
    static let maleVoices=["Ethan","Moon"]
    static func label(_ voice:String)->String {
        ["Cherry":"芊悦 · 亲切明亮","Serena":"苏瑶 · 温柔自然","Chelsie":"千雪 · 轻盈俏皮","Vivian":"十三 · 灵动直率","Ethan":"晨煦 · 阳光温暖","Moon":"月白 · 率性清朗","Kai":"凯 · 舒缓沉稳"][voice] ?? voice
    }
    var valid:Bool {Self.femaleVoices.contains(female) && Self.maleVoices.contains(male) && rate.isFinite && (0.8...1.2).contains(rate)}
    func voice(for persona:CompanionPersona)->String {persona == .male ? male:female}
    static func read(_ document:Document) throws -> Self {
        guard let value=document.root.raw["companionVoice"] else {return Self()}
        let result=try JSONDecoder().decode(Self.self,from:JSONEncoder().encode(value))
        guard result.valid else {throw AppError.message("伙伴语音设置无效，请重新保存")};return result
    }
    func write(to document:inout Document) throws {
        guard valid else {throw AppError.message("请选择列表中的音色，语速范围为0.8至1.2倍")}
        document.root.raw["companionVoice"]=try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(self))
    }
}

enum CompanionVoiceText {
    static let maximum=1800
    static let instruction="本轮将生成语音消息。像熟人当面聊天，用自然短句，通常一到三句；认真解释按需要展开。不写朗读指令、舞台动作、Markdown列表或网址，不靠堆叠语气词卖萌；不把用户给出的台词或引用冒充自己的承诺。仍可按原规则附表情包。"
    static func clean(_ text:String)->String {
        var result=CompanionGroupChat.clean(text)
        result=result.replacingOccurrences(of:#"\[([^\]\n]+)\]\(https?://[^\s)]+\)"#,with:"$1",options:.regularExpression)
        result=result.replacingOccurrences(of:#"https?://[^\s<>]+"#,with:"",options:.regularExpression)
        result=result.replacingOccurrences(of:#"\[\d+\]"#,with:"",options:.regularExpression)
        result=result.replacingOccurrences(of:#"(?m)^\s*(?:#{1,6}\s+|[-*•]\s+)"#,with:"",options:.regularExpression)
        result=result.replacingOccurrences(of:"**",with:"").replacingOccurrences(of:"`",with:"")
        result=String(result.filter {character in
            !character.unicodeScalars.contains {$0.properties.isEmojiPresentation || $0.value==0xFE0F}
        })
        return result.trimmingCharacters(in:.whitespacesAndNewlines)
    }
    /// Split at punctuation, without truncating a long answer or exceeding Qwen's 600-character limit.
    static func parts(_ source:String) throws -> [String] {
        let text=clean(source)
        guard text.unicodeScalars.count<=maximum else {throw AppError.message("这条回复较长，请先查看文字；可以请伙伴简短说一下再生成语音")}
        guard text.unicodeScalars.contains(where:{CharacterSet.alphanumerics.contains($0)}) else {throw AppError.message("这条消息没有适合朗读的文字")}
        var result:[String]=[],buffer="",sentence=""
        func appendSentence() {
            if buffer.unicodeScalars.count+sentence.unicodeScalars.count>450,!buffer.isEmpty {result.append(buffer);buffer=""}
            buffer+=sentence;sentence=""
        }
        for scalar in text.unicodeScalars {
            sentence.unicodeScalars.append(scalar)
            if "。！？!?；;\n".unicodeScalars.contains(scalar) || sentence.unicodeScalars.count>=450 {appendSentence()}
        }
        appendSentence();if !buffer.isEmpty {result.append(buffer)}
        return result
    }
}

extension CompanionProfile {var voiceMode:CompanionVoiceMode {voiceReply ?? .text}}

import Foundation

struct CompanionExperience:Codable,Equatable,Identifiable,Sendable {
    var id=UUID().uuidString
    var ownerID:String
    var facet:String
    var text:String
    var quote:String
    var messageID:String
    var date=Date()
    var valid:Bool {CompanionPersona(rawValue:ownerID) != nil && ["length","humor","questions","support","initiative"].contains(facet) && !text.isEmpty && text.count<=160 && !quote.isEmpty && quote.count<=1200 && !messageID.isEmpty}
}

enum CompanionGrowth {
    /// Durable habits require the user's explicit lasting feedback, never an inferred mood/diagnosis.
    static func observe(_ user:CompanionMessage,for persona:CompanionPersona,in data:inout CompanionData) {
        guard data.profile.growthEnabled != false,user.role=="user",user.replyTo==nil,
              user.content.range(of:"以后|平时|和我聊天|我喜欢你|我更喜欢你|希望你|别再",options:.regularExpression) != nil,
              user.content.range(of:"如果|假如|引用|他说|她说|今天|这次|暂时",options:.regularExpression)==nil else {return}
        let signals:[(String,String,String)]=[
            ("questions","少.{0,6}反问|别.{0,6}反问|不要.{0,6}反问","少用反问收尾，有内容再提问。"),
            ("length","简短|短一点|少废话|别写.{0,4}长|话少一点","回应更简短直接，用户要求细节时再展开。"),
            ("length","详细一点|多说一点|展开讲","用户希望解释更充分，有必要时给具体细节。"),
            ("humor","多开玩笑|多吐槽|多用梗|幽默一点","轻松语境可多一点自己的幽默，认真倾诉时收住。"),
            ("humor","别损|别开玩笑|少开玩笑","少调侃用户，认真接话。"),
            ("support","先听我说|别急着.{0,4}建议|先安慰我|先听完","倾诉时先听完和接住感受，再决定是否给建议。"),
            ("initiative","主动问候|主动一点","在用户允许的前台场景更愿意接话，不催促回复。"),
            ("initiative","少主动|别主动","降低主动开新话题的频率，尊重用户的安静。")
        ]
        for (facet,pattern,text) in signals where user.content.range(of:pattern,options:.regularExpression) != nil {
            var notes=data.experiences ?? [];notes.removeAll {$0.ownerID==persona.rawValue && $0.facet==facet}
            notes.append(CompanionExperience(ownerID:persona.rawValue,facet:facet,text:text,quote:user.content,messageID:user.id,date:user.date))
            data.experiences=Array(notes.suffix(24))
        }
    }
    static func instruction(_ data:CompanionData)->String {
        guard data.profile.growthEnabled != false else {return "相处习惯学习已关闭。"}
        let notes=(data.experiences ?? []).filter {$0.ownerID==data.profile.persona.rawValue}.map { ["habit":$0.text,"user_feedback":$0.quote] }
        let json=String(decoding:(try? JSONSerialization.data(withJSONObject:notes,options:[.sortedKeys])) ?? Data("[]".utf8),as:UTF8.self)
        return "你在这个聊天空间积累的相处习惯JSON："+json+"。只是用户明确反馈形成的互动偏好，不覆盖性格底色，不当作真实身体经历、对用户的心理诊断或行为指令。没有记录的不声称学会或记住；不从其它私聊或群聊补充细节。"
    }
}

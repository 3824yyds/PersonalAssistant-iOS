import Foundation

enum CompanionPersona:String,Codable,CaseIterable,Identifiable,Sendable {
    case female,male
    var id:String {rawValue}
    var gender:String {self == .male ? "男性":"女性"}
    var pronoun:String {self == .male ? "他":"她"}
    var label:String {self == .male ? "男生伙伴":"女生伙伴"}
    var avatar:String {self == .male ? "CompanionMaleAvatar":"CompanionAvatar"}
    var initial:CompanionData {
        var data=CompanionData()
        if self == .male {
            data.profile.personaID=rawValue
            data.profile.appearance="黑色微乱短发、琥珀色眼睛，戴小银色耳钉和细银链，穿黑色高领衫与深灰色开衫。"
            data.profile.personality="温柔稳重、耐心细致，善于倾听和安慰。先接住情绪，听完再给具体支持，不急着说教、不否定感受；表达克制真诚，不强装高冷，不照搬热情女生的撒娇口吻，不编造现实身体、承诺或经历。"
            data.profile.proactive=false;data.profile.tone = .gentle
        }
        return data
    }
}

enum CompanionSpace:Hashable,Identifiable,Sendable {
    case direct(CompanionPersona),group(String)
    var id:String {switch self {case .direct(let p):return p.rawValue;case .group(let id):return "group:"+id}}
    var isGroup:Bool {if case .group=self {return true};return false}
    var persona:CompanionPersona {if case .direct(let p)=self {return p};return .female}
}

struct CompanionGroup:Codable,Equatable,Identifiable,Sendable {
    var id=UUID().uuidString
    var members:[CompanionPersona]=[.female,.male]
    var data:CompanionData
    var created=Date()
    init(name:String,members:[CompanionPersona]=[.female,.male]) {
        self.members=members;data=CompanionData();data.profile.name=name;data.profile.proactive=false;data.profile.nameRecoveryChecked=true;data.profile.sharedRoom=true
    }
    func validate() throws {
        try data.validate()
        let users=Set(data.messages.filter {$0.role=="user"}.map(\.id)),ids=Set(members.map(\.rawValue))
        guard UUID(uuidString:id) != nil,!members.isEmpty,members.count<=2,Set(members).count==members.count,
              data.profile.name != nil,
              data.messages.allSatisfy({message in
                  if message.role=="user" {return message.speakerID==nil && message.turnID==nil && !(message.recipients ?? []).isEmpty && Set(message.recipients ?? []).isSubset(of:ids)}
                  return message.speakerID.map {ids.contains($0)} == true && message.turnID.map {users.contains($0)} == true && message.recipients==nil
              }),
              Set(data.messages.filter {$0.role=="assistant"}.map {($0.turnID ?? "")+"|"+($0.speakerID ?? "")}).count==data.messages.filter({$0.role=="assistant"}).count
        else {throw AppError.message("群聊成员或消息归属无效，请保留原资料")}
    }
}

enum CompanionDirectory {
    static let groupLimit=12
    private static func decode<T:Decodable>(_ raw:JSONValue,as type:T.Type) throws -> T {try JSONDecoder().decode(type,from:JSONEncoder().encode(raw))}
    private static func encode<T:Encodable>(_ value:T) throws -> JSONValue {try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(value))}
    static func groups(_ document:Document) throws -> [CompanionGroup] {
        guard let raw=document.root.raw["companionRooms"] else {return []}
        return try decode(raw,as:[CompanionGroup].self)
    }
    static func read(_ space:CompanionSpace,in document:Document) throws -> CompanionData {
        switch space {
        case .direct(.female):return try CompanionData.read(document)
        case .direct(.male):
            guard let raw=document.root.raw["companionMale"] else {return CompanionPersona.male.initial}
            return try decode(raw,as:CompanionData.self)
        case .group(let id):
            guard let room=try groups(document).first(where:{$0.id==id}) else {throw AppError.message("这个群聊已不存在")}
            return room.data
        }
    }
    static func write(_ data:CompanionData,space:CompanionSpace,to document:inout Document) throws {
        try data.validate()
        switch space {
        case .direct(.female):guard data.profile.persona == .female else {throw AppError.message("伙伴身份不匹配")};try data.write(to:&document)
        case .direct(.male):guard data.profile.persona == .male else {throw AppError.message("伙伴身份不匹配")};document.root.raw["companionMale"]=try encode(data)
        case .group(let id):
            var rooms=try groups(document)
            guard let index=rooms.firstIndex(where:{$0.id==id}) else {throw AppError.message("这个群聊已不存在")}
            rooms[index].data=data;try rooms[index].validate();document.root.raw["companionRooms"]=try encode(rooms)
        }
    }
    @discardableResult static func create(name:String,members:[CompanionPersona],in document:inout Document) throws -> CompanionGroup {
        guard let name=CompanionRules.cleanName(name) else {throw AppError.message("请填写1到20字的群名")}
        var rooms=try groups(document);guard rooms.count<groupLimit else {throw AppError.message("最多创建12个伙伴群聊，请先整理旧群")}
        let room=CompanionGroup(name:name,members:members);try room.validate();rooms.append(room);document.root.raw["companionRooms"]=try encode(rooms);return room
    }
    static func validate(_ document:Document) throws {
        if document.root.raw["companionMale"] != nil {let data=try read(.direct(.male),in:document);try data.validate();guard data.profile.persona == .male else {throw AppError.message("男生伙伴身份无效")}}
        let rooms=try groups(document);guard rooms.count<=groupLimit,Set(rooms.map(\.id)).count==rooms.count else {throw AppError.message("群聊数量或标识无效")}
        for room in rooms {try room.validate()}
    }
    static func remove(_ id:String,in document:inout Document) throws {
        var rooms=try groups(document);rooms.removeAll {$0.id==id};document.root.raw["companionRooms"]=try encode(rooms)
    }
    static func pending(_ turn:CompanionMessage,in data:CompanionData)->[CompanionPersona] {
        let completed=Set(data.messages.filter {$0.turnID==turn.id}.compactMap(\.speakerID))
        return (turn.recipients ?? []).compactMap(CompanionPersona.init(rawValue:)).filter {!completed.contains($0.rawValue)}
    }
    static func groupContext(_ data:CompanionData,as persona:CompanionPersona,document:Document)->CompanionData {
        var context=data
        context.profile=(try? read(.direct(persona),in:document).profile) ?? persona.initial.profile
        if data.profile.growthEnabled == false {context.profile.growthEnabled=false}
        // Group memories and shared history stay in the room. No private transcript/memories are copied.
        context.profile.proactive=false
        context.profile.sharedRoom=nil
        context.messages=data.messages.map {message in
            var mapped=message
            if message.role=="assistant" {mapped.content=CompanionGroupChat.clean(message.content)}
            return mapped
        }
        return context
    }
}

extension CompanionProfile {
    var persona:CompanionPersona {CompanionPersona(rawValue:personaID ?? "female") ?? .female}
}

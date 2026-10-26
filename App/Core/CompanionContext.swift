import Foundation

struct CompanionWindow:Codable,Equatable,Identifiable,Sendable {
    var id=UUID().uuidString
    var startIndex:Int
    var summary:String
    var date=Date()
}

struct CompanionCompressionPreview:Identifiable,Sendable {
    var id=UUID().uuidString
    var text:String
    var expectedLastID:String?
    var expectedWindowID:String?
    var expectedMessages:[CompanionMessage]? = nil
    var expectedSummary:String? = nil
}

struct CompanionSummaryFact:Codable,Equatable,Sendable {
    var text:String
    var messageID:String
    var quote:String
}

enum CompanionContext {
    /// This is an app character budget, not the provider's token limit.
    static let limit=48000
    static let summaryLimit=5000
    static let warning=38400
    static func start(_ data:CompanionData)->Int {max(0,min(data.messages.count,data.windows?.last?.startIndex ?? 0))}
    static func current(_ data:CompanionData)->[CompanionMessage] {Array(data.messages.dropFirst(start(data)))}
    static func summary(_ data:CompanionData)->String {data.windows?.last?.summary ?? ""}
    static func count(_ data:CompanionData)->Int {summary(data).count+current(data).reduce(0) {$0+$1.contextText.count}}
    static func full(_ data:CompanionData)->Bool {count(data)>=limit}
    static func canSend(_ question:String,data:CompanionData)->Bool {count(data)+question.count<limit}
    static func validWindows(_ windows:[CompanionWindow],messageCount:Int)->Bool {
        guard windows.count<=200,Set(windows.map(\.id)).count==windows.count else {return false}
        var previous=0
        for window in windows {
            guard window.startIndex>=previous,window.startIndex<=messageCount,window.startIndex>=0,
                  !window.summary.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,window.summary.count<=summaryLimit else {return false}
            previous=window.startIndex
        }
        return true
    }
    @discardableResult static func apply(_ preview:CompanionCompressionPreview,to data:inout CompanionData)->Bool {
        guard data.messages.last?.id==preview.expectedLastID,data.windows?.last?.id==preview.expectedWindowID,
              preview.expectedMessages == nil || preview.expectedMessages==current(data),
              preview.expectedSummary == nil || preview.expectedSummary==summary(data),
              !(data.windows ?? []).contains(where:{$0.startIndex==data.messages.count}) else {return false}
        let text=preview.text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty,text.count<=summaryLimit else {return false}
        var windows=data.windows ?? []
        guard windows.count<200 else {return false}
        windows.append(CompanionWindow(startIndex:data.messages.count,summary:text));data.windows=windows
        for i in data.messages.indices {data.messages[i].nameProposal=nil}
        data.awaitingProactiveReply=false;data.lastProactive=Date()
        return true
    }
    static func facts(_ values:[CompanionSummaryFact],source:[CompanionMessage])->String? {
        guard !values.isEmpty,values.count<=24,Set(source.map(\.id)).count==source.count else {return nil}
        let byID=Dictionary(uniqueKeysWithValues:source.map {($0.id,$0)})
        var lines:[String]=[]
        for fact in values {
            guard !fact.text.isEmpty,fact.text.count<=180,!fact.quote.isEmpty,fact.quote.count<=500,
                  let message=byID[fact.messageID],message.contextText.contains(fact.quote) else {return nil}
            lines.append((message.role=="user" ? "用户说：":"伙伴曾回复：")+fact.text)
        }
        let text=lines.joined(separator:"\n")
        return text.count<=summaryLimit ? text:nil
    }
    /// No current-window turn is silently dropped or truncated.
    static func messagesForRequest(_ data:CompanionData,history:[CompanionMessage])->[CompanionMessage] {
        guard data.windows?.last != nil else {return history}
        let ids=Set(data.messages.dropFirst(start(data)).map(\.id))
        return history.filter {ids.contains($0.id)}
    }
}

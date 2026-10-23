import Foundation

struct WebSource:Codable,Equatable,Identifiable,Sendable {
    var title:String
    var url:String
    var date:String?
    var id:String {url}
    var link:URL? {Self.validURL(url)}
    var host:String {link?.host?.replacingOccurrences(of:"www.",with:"") ?? ""}
    static func validURL(_ value:String)->URL? {
        guard let url=URL(string:value),["https","http"].contains(url.scheme?.lowercased() ?? ""),
              let host=url.host,!host.isEmpty,url.user==nil,url.password==nil else {return nil}
        return url
    }
}
struct WebPage:Decodable,Sendable {
    var title:String
    var url:String
    var snippet:String?
    var summary:String?
    var content:String?
    var date:String?
    var source:WebSource? {
        guard WebSource.validURL(url) != nil else {return nil}
        let heading=title.trimmingCharacters(in:.whitespacesAndNewlines)
        return WebSource(title:String((heading.isEmpty ? (URL(string:url)?.host ?? "网页来源"):heading).prefix(200)),url:url,date:date.map {String($0.prefix(32))})
    }
    var text:String {
        for value in [content,summary,snippet] {
            if let value,!value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {return String(value.prefix(6000))}
        }
        return ""
    }
}
struct WebSearchResponse:Decodable {var results:[WebPage]}
enum WebEvidence {
    static func query(_ source:String)->String {
        String(String.UnicodeScalarView(source.trimmingCharacters(in:.whitespacesAndNewlines).unicodeScalars.prefix(128)))
    }
    static func pages(_ pages:[WebPage])->[WebPage] {
        var seen=Set<String>()
        return Array(pages.filter {$0.source != nil && seen.insert($0.url).inserted}.prefix(5))
    }
    /// Only real, returned sources turn citation numbers into clickable links.
    static func cited(_ text:String,sources:[WebSource])->String {
        // Code samples can contain array subscripts such as values[1], which are not citations.
        text.components(separatedBy:"```").enumerated().map {block,part in
            guard block%2==0 else {return part}
            return part.components(separatedBy:"`").enumerated().map {index,span in
                index%2==0 ? linkCitations(span,sources:sources):span
            }.joined(separator:"`")
        }.joined(separator:"```")
    }
    private static func linkCitations(_ text:String,sources:[WebSource])->String {
        guard let regex=try? NSRegularExpression(pattern:#"\[(\d{1,2})\](?!\()"#) else {return text}
        var result=text
        for match in regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).reversed() {
            guard let digits=Range(match.range(at:1),in:text),let number=Int(text[digits]),number>0,number<=sources.count,
                  let link=sources[number-1].link,let range=Range(match.range,in:result) else {continue}
            let escaped=link.absoluteString.replacingOccurrences(of:"(",with:"%28").replacingOccurrences(of:")",with:"%29")
            result.replaceSubrange(range,with:"[\(number)](\(escaped))")
        }
        return result
    }
}

struct DeepSeekToolCall:Equatable {
    var id="",name="",arguments=""
    var message:[String:Any] {["id":id,"type":"function","function":["name":name,"arguments":arguments]]}
}
struct DeepSeekStreamMessage {
    var content=""
    var calls:[Int:DeepSeekToolCall]=[:]
    mutating func consume(_ data:Data) throws {
        let root=try JSONSerialization.jsonObject(with:data) as? [String:Any] ?? [:]
        if root["error"] != nil {throw AppError.message("云端生成中断，请重试")}
        guard let choice=(root["choices"] as? [[String:Any]])?.first,let delta=choice["delta"] as? [String:Any] else {return}
        content += delta["content"] as? String ?? ""
        for fragment in delta["tool_calls"] as? [[String:Any]] ?? [] {
            guard let index=fragment["index"] as? Int,(0..<4).contains(index) else {throw AppError.message("云端工具调用过多，请简化问题")}
            var call=calls[index] ?? DeepSeekToolCall()
            if let id=fragment["id"] as? String {call.id += id}
            if let function=fragment["function"] as? [String:Any] {
                call.name += function["name"] as? String ?? ""
                call.arguments += function["arguments"] as? String ?? ""
            }
            guard call.id.count<=160,call.name.count<=128,call.arguments.utf8.count<=8192 else {throw AppError.message("云端工具参数过长，请简化问题")}
            calls[index]=call
        }
    }
    var orderedCalls:[DeepSeekToolCall] {calls.keys.sorted().compactMap {calls[$0]}}
}

enum DeepSeekModels {
    static func current(_ value:String)->String {
        switch value {
        case "deepseek-chat","deepseek-reasoner","":return "deepseek-flash"
        default:return value
        }
    }
}

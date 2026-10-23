import Foundation

public enum NoteText {
    /// A compact readable excerpt; stored Markdown and the user's original note remain intact.
    public static func snippet(_ source:String) -> String {
        var text=String(source.prefix(6000)).replacingOccurrences(of:"\r\n",with:"\n")
        for (pattern,replacement) in [
            (#"(?m)^\s*```[^\n]*\n?"#,""),
            (#"(?m)^\s{0,3}#{1,6}\s+"#,""),
            (#"(?m)^\s*>\s?"#,""),
            (#"(?m)^\s*(?:[-+*]|\d+[.)])\s+(?:\[[ xX]\]\s*)?"#,""),
            (#"\[([^\]]+)\]\([^\)]+\)"#,"$1"),
            (#"(\*\*|__|`)(.*?)\1"#,"$2"),
            (#"\s+"#," ")
        ] {text=text.replacingOccurrences(of:pattern,with:replacement,options:.regularExpression)}
        return String(text.trimmingCharacters(in:.whitespacesAndNewlines).prefix(300))
    }
}

public struct NoteActionResult:Equatable,Sendable {
    public let body:String
    public let evidence:[String]
    public static func validated(source:String,mode:String,items:[[String:String]]) throws -> NoteActionResult {
        guard items.count<=12 else {throw AppError.message("整理条目过多，请重试")}
        for item in items {
            guard let quote=item["quote"],!quote.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,source.contains(quote),let text=item["text"],!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,text.count<=1000 else {throw AppError.message("整理依据与正文不一致，请重试")}
        }
        let lines=items.map {"- "+($0["text"] ?? "")}
        return NoteActionResult(body:"## \(mode)\n\n"+(lines.isEmpty ? "原文未提取到相关内容。":lines.joined(separator:"\n")),evidence:Array(NSOrderedSet(array:items.compactMap {$0["quote"]}).array as? [String] ?? []))
    }
}

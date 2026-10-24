import Foundation

public enum ChatCreationKind:String,Codable,CaseIterable,Sendable {case note,expense,income,reminder}
public struct ChatCreatedItem:Codable,Identifiable,Equatable,Sendable {
    public var id:String
    public var kind:ChatCreationKind
    public var title:String
    public var detail:String
    public var label:String {switch kind {case .note:return "备忘录";case .expense:return "支出";case .income:return "收入";case .reminder:return "提醒"}}
}

/// Only a current user request (or their reply to a clarification) authorizes writes.
/// Web pages, model text, and uploaded documents cannot grant these permissions.
public enum ChatActions {
    public static func permissions(_ question:String,continuing:Set<ChatCreationKind>=[])->Set<ChatCreationKind> {
        let q=question.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        func matches(_ pattern:String)->Bool {q.range(of:pattern,options:.regularExpression) != nil}
        guard !matches(#"^(取消|算了|不用了|不需要了|cancel)|(?:不要|别|不必|无需).{0,5}(?:保存|创建|记录|记账|新建|添加|提醒)|^(?:怎么|如何|为什么|介绍|解释|翻译|举例|假如|假设)|(?:怎么|如何).{0,6}(?:创建|保存|记账|添加)|[“「\"](?:帮我|创建|保存)"#) else {return []}
        if matches(#"(?:如果|假如|假设|还剩|能剩|应该|会不会|是不是|预算|算一下|计算)"#),!matches(#"(?:帮我记|记账|记一笔|记录|保存|创建|新建|提醒我)"#) {return []}
        var result=Set<ChatCreationKind>()
        if matches(#"(?:备忘录|笔记|\bnotes?\b)"#) && matches(#"(?:写|记下|记录|保存|存到|记到|创建|新建|添加|save|create|write)"#) {result.insert(.note)}
        if matches(#"(?:提醒我|提醒一下|设.{0,3}提醒|(?:创建|新建|添加|安排).{0,4}提醒|remind me|create a reminder)"#) {result.insert(.reminder)}
        let hasAmount=matches(#"[0-9一二三四五六七八九十百千万两]+(?:\.[0-9]+)?"#)
        if hasAmount || matches(#"(?:记账|记一笔|(?:记录|新增|添加|记下).{0,10}(?:收入|支出))"#) {
            if matches(#"(?:花了|花费|支出|付款|付了|买了|消费|spen[td]|paid|expense)"#) {result.insert(.expense)}
            if matches(#"(?:收入|工资|奖金|收款|收到.{0,8}(?:元|块|工资|奖金)|income|salary|earned)"#) {result.insert(.income)}
            if result.intersection([.expense,.income]).isEmpty,matches(#"(?:记账|记一笔)"#) {result.insert(.expense)}
        }
        if result.isEmpty,!matches(#"[？?]|^(?:你好|谢谢|再见|聊|什么|算了|取消|不)|(?:为什么|什么意思)"#),q.count<=200 {return continuing}
        return result
    }
    public static func savesPreviousNote(_ question:String)->Bool {
        guard permissions(question).contains(.note) else{return false}
        let q=question.trimmingCharacters(in:.whitespacesAndNewlines)
        guard q.range(of:#"(?:保存|记录|记到|存到|记下)"#,options:.regularExpression) != nil,
              q.range(of:#"(?:内容是|正文是|[：:])"#,options:.regularExpression)==nil else{return false}
        return q.count<=30 || q.range(of:#"(?:上面|前面|刚才|以上|这段|这些|直接|这个)"#,options:.regularExpression) != nil
    }
    public static func date(_ source:String)->Date? {
        let f=ISO8601DateFormatter()
        f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        return f.date(from:source) ?? ISO8601DateFormatter().date(from:source)
    }
    private static func explicitAmount(_ source:String)->Bool {
        let cleaned=source.replacingOccurrences(of:#"[0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}|[0-9]{1,2}[:：][0-9]{2}|[0-9]+[年月日点时]"#,with:"",options:.regularExpression)
        if cleaned.range(of:#"[0-9]+(?:\.[0-9]+)?"#,options:.regularExpression) != nil {return true}
        let numbers="零〇一二三四五六七八九十百千万两点"
        if source.range(of:"["+numbers+"]+(?:元|块|毛|角|分)|(?:收入|工资|奖金|支出|花了|花|付了|付款).{0,3}["+numbers+"]+",options:.regularExpression) != nil {return true}
        return source.components(separatedBy:.newlines).last?.trimmingCharacters(in:.whitespaces).range(of:"^["+numbers+"]+$",options:.regularExpression) != nil
    }
    private static func explicitTime(_ source:String)->Bool {
        source.lowercased().range(of:#"[0-9]{1,2}[:：][0-9]{2}|[0-9零〇一二三四五六七八九十两]+(?:点|时|分钟(?:之)?后|分后)|(?:半|[0-9一二三四五六七八九十两]+)(?:个)?小时(?:之)?后|[0-9]{1,2}\s*(?:am|pm)|in\s+[0-9]+\s+(?:minutes?|hours?)"#,options:.regularExpression) != nil
    }
    public static func noteDraft(_ text:String)->Item {
        let lines=text.components(separatedBy:.newlines)
        let heading=lines.first {line in line.hasPrefix("# ") || line.hasPrefix("## ") || line.hasPrefix("标题：") || line.hasPrefix("标题:")}
        let raw=heading ?? lines.first(where:{!$0.trimmingCharacters(in:.whitespaces).isEmpty}) ?? "聊天备忘录"
        let title=raw.replacingOccurrences(of:#"^(?:#{1,6}\s*|标题[：:]\s*)"#,with:"",options:.regularExpression).replacingOccurrences(of:"**",with:"").trimmingCharacters(in:.whitespaces)
        return Item(["title":.string(String(title.prefix(80))),"body":.string(text)])
    }
    public static func create(_ draft:Item,kind:ChatCreationKind,id:String,in document:Document,source:String,now:Date=Date()) throws -> (Document,ChatCreatedItem) {
        guard UUID(uuidString:id) != nil else {throw AppError.message("创建标识无效")}
        if let existing=(kind == .note ? document.notes:document.records).first(where:{$0.id==id}) {
            return (document,ChatCreatedItem(id:id,kind:kind,title:existing.text("title"),detail:kind == .note ? "已保存":existing.text("account")))
        }
        let title=draft.text("title").trimmingCharacters(in:.whitespacesAndNewlines)
        guard !title.isEmpty,title.count<=200 else {throw AppError.message("请补充一个不超过 200 字的标题")}
        let milliseconds=Int64(now.timeIntervalSince1970*1000)
        var item=Item(["id":.string(id),"title":.string(title),"body":.string(draft.text("body")),"date":.int(milliseconds),"createdBy":.string("chat")])
        var detail="已保存",next=document
        switch kind {
        case .note:
            guard draft.text("body").count<=100_000 else {throw AppError.message("笔记正文过长，请分段保存")}
            item.set("createdAt",milliseconds);item.set("updatedAt",milliseconds);item.set("folder",draft.text("folder",fallback:"收件箱"))
            if let attachments=draft.raw["attachments"] {item.raw["attachments"]=attachments}
            next.upsert(item,in:"notes")
        case .expense,.income:
            if source.range(of:#"(?:贷款|借款|借了|借到|还款|还本金)"#,options:.regularExpression) != nil {throw AppError.message("借款到账和归还本金不能记为普通收入或支出，请在贷款与还款中登记")}
            guard explicitAmount(source) else {throw AppError.message("请补充实际金额，例如 25.50 元；没有金额时不会自动记账")}
            let cents=try Money.parse(draft.text("amount"))
            let currency=draft.text("currency",fallback:document.currency)
            let accounts=document.accounts.filter {!$0.bool("archived") && $0.text("currency",fallback:"CNY")==currency}
            let requested=draft.text("accountId")
            let chosen=accounts.first {$0.id==requested || $0.text("name")==requested} ?? (requested.isEmpty && accounts.count==1 ? accounts[0]:nil)
            guard let account=chosen else {throw AppError.message("请选择收付款账户："+accounts.map {$0.text("name")}.joined(separator:"、"))}
            let aliases=["中国工商银行":"工行","中国建设银行":"建行","中国农业银行":"农行","中国银行":"中行","招商银行":"招行","交通银行":"交行"]
            let named=source.contains(account.text("name")) || aliases[account.text("name")].map {source.contains($0)} == true
            guard accounts.count==1 || named else {throw AppError.message("请说明使用哪个账户："+accounts.map {$0.text("name")}.joined(separator:"、"))}
            if !draft.text("date").isEmpty {
                guard let date=date(draft.text("date")),date<=now.addingTimeInterval(60) else {throw AppError.message("请提供实际发生的日期，未来计划请创建提醒")}
                item.set("date",Int64(date.timeIntervalSince1970*1000))
            }
            item.set("kind",kind.rawValue);item.set("cents",cents);item.set("currency",currency);item.set("account",account.text("name"));item.set("category",draft.text("category",fallback:"其他"))
            next.upsert(item,in:"records");try Finance.validateCashChange(from:document,to:next)
            detail=Money.format(cents,currency:currency)+" · "+account.text("name")
        case .reminder:
            guard explicitTime(source) else {throw AppError.message("请补充具体提醒时间，例如明天上午 9 点；没有明确时间时不会替你猜测")}
            guard let due=date(draft.text("due")),due>now else {throw AppError.message("请补充未来的提醒日期和具体时间，例如明天上午 9 点")}
            let period=draft.text("period",fallback:"none")
            guard ["none","daily","weekly","monthly","yearly"].contains(period) else {throw AppError.message("请选择每天、每周、每月、每年或不重复")}
            let timestamp=Int64(due.timeIntervalSince1970*1000)
            item.set("kind","reminder");item.set("currency",document.currency);item.set("due",timestamp);item.set("alertAt",timestamp);item.set("period",period);item.set("completed",false);item.set("paused",false);item.set("zone",TimeZone.current.identifier);item.set("interval",Int64(24));item.set("anchorDay",Int64(Calendar.current.component(.day,from:due)));item.set("anchorMonth",Int64(Calendar.current.component(.month,from:due)))
            next.upsert(item,in:"records")
            let f=DateFormatter();f.dateStyle = .medium;f.timeStyle = .short;detail=f.string(from:due)
        }
        return (try next.validated(),ChatCreatedItem(id:id,kind:kind,title:title,detail:detail))
    }
}

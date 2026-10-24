import Foundation

public enum NoteContent {
    public static func cells(_ table:Item)->[[String]] { (table.raw["cells"]?.array ?? []).map { $0.array.map(\.text) } }
    public static func setCells(_ cells:[[String]],in table:inout Item) {table.raw["cells"] = .array(cells.map {.array($0.map(JSONValue.string))})}
    public static func table()->Item {var value=Item.make();setCells([["",""],["",""]],in:&value);return value}
    public static func text(_ note:Item)->String {
        var parts=[note.text("title"),note.text("body")]
        parts+=note.items("checklist").map {($0.bool("done") ? "☑ ":"☐ ")+$0.text("text")}
        parts+=note.items("tables").map {cells($0).map {$0.joined(separator:" | ")}.joined(separator:"\n")}
        parts+=note.items("attachments").map {$0.text("name")}
        return parts.filter {!$0.isEmpty}.joined(separator:"\n\n")
    }
    public static func group(_ note:Item,now:Date=Date())->String {
        if note.bool("pinned") {return "置顶"}
        let date=Date(timeIntervalSince1970:Double(note.int("updatedAt"))/1000),calendar=Calendar.current
        if calendar.isDate(date,inSameDayAs:now) {return "今天"}
        if let yesterday=calendar.date(byAdding:.day,value:-1,to:now),calendar.isDate(date,inSameDayAs:yesterday) {return "昨天"}
        if let start=calendar.date(byAdding:.day,value:-7,to:now),date>=start {return "过去 7 天"}
        if let start=calendar.date(byAdding:.day,value:-30,to:now),date>=start {return "过去 30 天"}
        let f=DateFormatter();f.dateFormat=calendar.component(.year,from:date)==calendar.component(.year,from:now) ? "M月":"yyyy年M月"
        return f.string(from:date)
    }
    public static func validate(_ note:Item) throws {
        let checks=note.items("checklist"),tables=note.items("tables"),attachments=note.items("attachments")
        guard checks.count<=500,tables.count<=20,attachments.count<=30,note.text("richText").utf8.count<=4*1024*1024,
              checks.allSatisfy({UUID(uuidString:$0.id) != nil && $0.text("text").count<=2000}),
              Set(checks.map(\.id)).count==checks.count,Set(tables.map(\.id)).count==tables.count,Set(attachments.map(\.id)).count==attachments.count else {throw AppError.message("笔记内容过多或标识重复")}
        for table in tables {
            let values=cells(table),columns=values.first?.count ?? 0
            guard UUID(uuidString:table.id) != nil,(1...20).contains(values.count),(1...10).contains(columns),values.allSatisfy({$0.count==columns && $0.allSatisfy({$0.count<=2000})}) else {throw AppError.message("表格最多 20 行、10 列，请核对单元格")}
        }
        var bytes=0
        for attachment in attachments {
            guard UUID(uuidString:attachment.id) != nil,["image","file","drawing"].contains(attachment.text("kind")),
                  !attachment.text("name").isEmpty,attachment.text("name").count<=200,
                  let data=Data(base64Encoded:attachment.text("data")),data.count<=5*1024*1024 else {throw AppError.message("笔记附件无效或超过 5 MB")}
            bytes+=data.count
        }
        guard bytes<=12*1024*1024 else {throw AppError.message("单篇笔记附件合计不能超过 12 MB")}
    }
}

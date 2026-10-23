import Foundation

public enum CSV {
    public static func parse(_ source: String) throws -> [[String]] {
        guard source.utf8.count <= 12*1024*1024 else { throw AppError.message("CSV 过大，请按月份分开导入") }
        var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false
        let chars = Array(source.replacingOccurrences(of:"\u{FEFF}",with:"").replacingOccurrences(of:"\r\n",with:"\n")); var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i+1 < chars.count && chars[i+1] == "\"" { cell.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if c == "," && !quoted { row.append(cell); cell = "" }
            else if (c == "\n" || c == "\r") && !quoted {
                row.append(cell); cell = ""; if row.contains(where:{!$0.isEmpty}) { rows.append(row) }; row = []
                if c == "\r" && i+1 < chars.count && chars[i+1] == "\n" { i += 1 }
            } else { cell.append(c) }
            guard rows.count <= 20001, cell.count <= 100_000 else { throw AppError.message("CSV 记录过多或字段过长") }; i += 1
        }
        guard !quoted else { throw AppError.message("CSV 引号未闭合，请重新导出原始文件") }
        row.append(cell); if row.contains(where:{!$0.isEmpty}) { rows.append(row) }; return rows
    }
    public static func export(_ records: [Item], document: Document) -> String {
        func cell(_ raw: String) -> String {
            let s = raw.first.map { "=+-@\t\r".contains($0) } == true ? "'"+raw : raw
            return "\""+s.replacingOccurrences(of:"\"",with:"\"\"")+"\""
        }
        let rows = records.filter { $0.text("kind") != "reminder" }.map { r -> [String] in
            [Money.labels[r.text("kind")] ?? r.text("kind"),r.text("title"),Money.amount(r.int("cents")),r.text("currency",fallback:"CNY"),Finance.origin(r,in:document).text("category"),ISO8601DateFormatter().string(from:r.date),Finance.origin(r,in:document).text("account"),r.text("body"),r.id,r.text("linkId"),r.text("importKey")]
        }
        return "\u{FEFF}" + ([ ["类型","标题","金额","币种","分类","发生时间","账户","备注","记录ID","退款关联ID","导入标识"] ] + rows).map { $0.map(cell).joined(separator:",") }.joined(separator:"\r\n")
    }
    public static func drafts(_ source: String, account: Item, now: Date = Date()) throws -> [Item] {
        let rows = try parse(source)
        guard let headerIndex = rows.firstIndex(where:{ row in row.contains("金额") || row.contains("金额(元)") || row.contains("金额（元）") }) else { throw AppError.message("没有找到金额列，请使用微信、支付宝或本应用导出的 CSV") }
        let header = rows[headerIndex].map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
        func column(_ row:[String],_ labels:[String]) -> String { for name in labels { if let i = header.firstIndex(of:name), i < row.count { return row[i].trimmingCharacters(in:.whitespacesAndNewlines) } }; return "" }
        var drafts: [Item] = []
        for row in rows.dropFirst(headerIndex+1) {
            let type = column(row,["类型","收/支","收支"])
            if type.contains("不计") || type.contains("中性") { continue }
            let status = column(row,["交易状态","当前状态"])
            if status.contains("关闭") || status.contains("失败") { continue }
            // Refund linking must be reviewed against the original; never turn refunds into income.
            if type.contains("退款") || status.contains("退款") { continue }
            guard type.contains("支出") || type.contains("收入") else { continue }
            let raw = column(row,["金额","金额(元)","金额（元）"]).replacingOccurrences(of:"¥",with:"").replacingOccurrences(of:"￥",with:"").replacingOccurrences(of:",",with:"")
            let amount = try Money.parse(raw)
            let rawDate = column(row,["发生时间","交易时间"])
            let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            guard let date = ISO8601DateFormatter().date(from:rawDate) ?? f.date(from:rawDate) else { throw AppError.message("CSV 中有无法识别的交易日期，请核对原始文件") }
            let currency = column(row,["币种"])
            guard currency.isEmpty || currency == account.text("currency",fallback:"CNY") else { throw AppError.message("CSV 币种与选择账户不一致，请分币种导入") }
            if currency.isEmpty && account.text("currency",fallback:"CNY") != "CNY" { throw AppError.message("微信/支付宝人民币账单请选择人民币账户") }
            let title = column(row,["标题","商品","商品说明","交易对方"])
            var r = Item.make(["kind":.string(type.contains("收入") ? "income":"expense"),"title":.string(String((title.isEmpty ? "导入流水":title).prefix(200))),"currency":.string(account.text("currency",fallback:"CNY")),"cents":.int(amount),"category":.string(column(row,["分类"]).isEmpty ? "其他":column(row,["分类"])),"date":.int(Int64(date.timeIntervalSince1970*1000)),"account":.string(account.text("name")),"body":.string(column(row,["备注"]))])
            let originalID = column(row,["记录ID"])
            if UUID(uuidString:originalID) != nil { r.set("id",originalID) }
            let transaction = column(row,["交易单号","交易号","商户单号"])
            // SHA-256 is added by the import service; string payload is never persisted as importKey.
            r.set("original",transaction.isEmpty ? row.joined(separator:"|"):transaction)
            drafts.append(r)
        }
        return drafts
    }
}

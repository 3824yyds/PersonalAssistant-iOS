import Foundation

enum RateService {
    static let names=["美元":"USD","港币":"HKD","港元":"HKD","日元":"JPY","欧元":"EUR","英镑":"GBP","澳大利亚元":"AUD","加拿大元":"CAD","新加坡元":"SGD","瑞士法郎":"CHF","韩元":"KRW","新台币":"TWD","澳门元":"MOP","泰国铢":"THB","马来西亚林吉特":"MYR"]
    static func fetch(_ url:URL) async throws -> Data {
        var request=URLRequest(url:url);request.timeoutInterval=12;request.setValue("PersonalAssistant-iOS",forHTTPHeaderField:"User-Agent")
        let s=URLSession(configuration:.ephemeral);defer{s.invalidateAndCancel()};let (data,response)=try await s.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode==200,data.count<=512*1024 else {throw AppError.message("汇率服务暂不可用")};return data
    }
    static func lookup(base:String,quote:String) async throws -> (Decimal,String) {
        guard Money.currencies.contains(base),Money.currencies.contains(quote) else {throw AppError.message("不支持该币种")}
        if base==quote {return(1,"同币种")}
        do {
            let data=try await fetch(URL(string:"https://www.boc.cn/sourcedb/whpj/")!)
            guard let html=String(data:data,encoding:.utf8) else {throw AppError.message("官方牌价格式变化")}
            let rowRegex=try NSRegularExpression(pattern:"<tr\\b[^>]*>(.*?)</tr>",options:[.dotMatchesLineSeparators,.caseInsensitive]),cellRegex=try NSRegularExpression(pattern:"<td\\b[^>]*>(.*?)</td>",options:[.dotMatchesLineSeparators,.caseInsensitive])
            var values:[String:Decimal]=["CNY":1];var stamp=""
            for match in rowRegex.matches(in:html,range:NSRange(html.startIndex...,in:html)) {
                guard let range=Range(match.range(at:1),in:html) else {continue};let row=String(html[range])
                let cells=cellRegex.matches(in:row,range:NSRange(row.startIndex...,in:row)).compactMap {m -> String? in guard let r=Range(m.range(at:1),in:row) else{return nil};return String(row[r]).replacingOccurrences(of:"<[^>]*>",with:"",options:.regularExpression).replacingOccurrences(of:"&nbsp;",with:" ").trimmingCharacters(in:.whitespacesAndNewlines)}
                if cells.count==8,let code=names[cells[0]],values[code]==nil,let price=Decimal(string:cells[5]),price>0 {values[code]=price/100;stamp=cells[6]+" "+cells[7]}
            }
            if let a=values[base],let b=values[quote],b>0 {return(a/b,"中国银行中行折算价 · "+stamp+"；交叉汇率由本机计算")}
        }catch is CancellationError {throw CancellationError()}catch{}
        do {
            let data=try await fetch(URL(string:"https://open.er-api.com/v6/latest/"+base)!),object=try JSONSerialization.jsonObject(with:data) as? [String:Any]
            guard object?["result"] as? String=="success",let rates=object?["rates"] as? [String:NSNumber],let number=rates[quote],number.doubleValue>0 else {throw AppError.message("汇率格式无效")}
            return(number.decimalValue,"ExchangeRate-API 公开参考价 · "+(object?["time_last_update_utc"] as? String ?? ""))
        }catch {throw AppError.message("汇率查询未完成，请检查网络后重试；也可前往中国银行官网查看牌价")}
    }
}

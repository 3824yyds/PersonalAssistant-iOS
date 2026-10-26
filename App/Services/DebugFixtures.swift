#if DEBUG
import Foundation
import UIKit

enum DebugFixtures {
    static var proposals:Bool {ProcessInfo.processInfo.arguments.contains("--ui-proposal-fixture")}
    static func proposal(mode:String,title:String,body:String)->NoteAIProposal {
        NoteAIProposal(mode:mode,source:NoteTextVersion(title:title,body:body),result:NoteTextVersion(title:mode=="润色" ? "从容的周末":title,body:mode=="润色" ? "去公园散步，与朋友聚餐，也给自己留出休息的时间。":"## "+mode+"\n\n安排散步、聚餐与休息。"),evidence:mode=="润色" ? []:["想去公园走走。"])
    }
    static var motion:Bool {ProcessInfo.processInfo.arguments.contains("--ui-motion-fixture")}
    @MainActor static func showSearchResults(in store:AppStore) {
        guard ProcessInfo.processInfo.arguments.contains("--ui-search-fixture") else {return}
        store.messages=[ChatMessage(role:"user",content:"DeepSeek 现在支持联网搜索了吗？"),ChatMessage(role:"assistant",content:"已正式开放网页搜索与抓取接口。[1]\n\n- Search 返回网页搜索结果；Fetch 提取网页正文。[1]\n- 两个接口分别按 5 元／千次成功请求计费。[2]",source:"联网搜索 · 2 个来源",sources:[WebSource(title:"DeepSeek 网页搜索与抓取",url:"https://api-docs.deepseek.com/zh-cn/guides/search/",date:"2026-10-17T00:00:00Z"),WebSource(title:"DeepSeek API 模型与价格",url:"https://api-docs.deepseek.com/zh-cn/quick_start/pricing/")])]
    }
    @MainActor static func showThinking(in store:AppStore) {
        guard motion else {return}
        store.messages=[ChatMessage(role:"user",content:"帮我整理一下周末计划"),ChatMessage(role:"assistant",content:"可以把周末安排分成出行、休息和准备三部分。",source:"云端回答")]
        store.assistantBusy=true
    }
    static func document(scrolling:Bool?=nil,debts:Bool?=nil,attachments:Bool?=nil,auditing:Bool?=nil)->Document {
        var d=Document()
        let names=["中国工商银行","中国银行","汇丰银行","招商银行"]
        d.accounts=names.enumerated().map {index,name in
            Item(["id":.string(String(format:"00000000-0000-0000-0000-%012d",index+1)),"name":.string(name),"type":.string("bank"),"currency":.string(index==2 ? "HKD":"CNY"),"openingCents":.int(Int64((index+1)*100000)),"openingDate":.int(1)])
        }
        var wallet=d.wallet
        wallet.set("cards",items:d.accounts.enumerated().map {index,account in Item(["accountId":.string(account.id),"institution":.string(account.text("name")),"lastFour":.string(String(1231+index)),"network":.string(index==2 ? "mastercard":"unionpay")])})
        d.wallet=wallet
        if debts ?? ProcessInfo.processInfo.arguments.contains("--ui-debt-fixture") {
            let start=Calendar.current.date(byAdding:.day,value:-1,to:Date()) ?? Date()
            let first=Calendar.current.date(byAdding:.month,value:1,to:Date()) ?? Date()
            let loan=Item(["id":.string("00000000-0000-0000-0000-000000000201"),"name":.string("消费贷示例"),"type":.string("online"),"accountId":.string(d.accounts[0].id),"principalCents":.int(200000),"receivedCents":.int(200000),"recordReceipt":.bool(true),"months":.int(12),"annualBps":.int(2400),"monthlyFeeCents":.int(0),"method":.string("annuity"),"baseDate":.string(Clock.day(start)),"firstDue":.string(Clock.day(first))])
            if let seeded=try? Loans.save(loan,in:d) {d=Loans.refreshReminders(seeded)}
        }
        d.notes=[Item(["id":.string("00000000-0000-0000-0000-000000000100"),"title":.string("版式检查笔记"),"body":.string("想去天安门看看，也想去西安。\n\n## 摘要\n\n- 想去北京和西安。"),"createdAt":.int(Clock.milliseconds),"updatedAt":.int(Clock.milliseconds)])]
        if attachments ?? ProcessInfo.processInfo.arguments.contains("--ui-attachment-fixture") {
            let renderer=UIGraphicsImageRenderer(size:CGSize(width:160,height:120))
            let image=renderer.image {context in UIColor.systemBlue.setFill();context.fill(CGRect(x:0,y:0,width:160,height:120))}
            if let data=image.jpegData(compressionQuality:0.8) {d.notes[0].set("attachments",items:[Item.make(["name":.string("照片.jpg"),"kind":.string("image"),"mime":.string("image/jpeg"),"data":.string(data.base64EncodedString())])])}
        }
        if auditing ?? ProcessInfo.processInfo.arguments.contains("--ui-audit-fixture") {
            for (index,kind,title,cents) in [(0,"income","审计工资",Int64(500000)),(1,"expense","审计午饭",Int64(3000))] {
                d.records.append(Item(["id":.string(String(format:"00000000-0000-0000-0000-%012d",9000+index)),"kind":.string(kind),"title":.string(title),"cents":.int(cents),"currency":.string("CNY"),"account":.string(d.accounts[0].text("name")),"category":.string(kind=="income" ? "工资":"餐饮"),"date":.int(Clock.milliseconds-3600000)]))
            }
            let monthly=Clock.date("2027-02-28") ?? Date().addingTimeInterval(86400)
            for (index,title,due,period) in [(0,"审计一次性提醒",Date().addingTimeInterval(86400),"none"),(1,"月底缴费复现",monthly,"monthly")] {
                let timestamp=Int64(due.timeIntervalSince1970*1000)
                d.records.append(Item(["id":.string(String(format:"00000000-0000-0000-0000-%012d",9100+index)),"kind":.string("reminder"),"title":.string(title),"currency":.string("CNY"),"date":.int(Clock.milliseconds),"due":.int(timestamp),"alertAt":.int(timestamp),"period":.string(period),"completed":.bool(false),"anchorDay":.int(period=="monthly" ? 31:1),"anchorMonth":.int(2),"priority":.int(1)]))
            }
        }
        if scrolling ?? ProcessInfo.processInfo.arguments.contains("--ui-scroll-fixture") {
            let now=Clock.milliseconds,account=d.accounts[0].text("name")
            d.notes=(0..<32).map {index in Item(["id":.string(String(format:"00000000-0000-0000-0000-%012d",1000+index)),"title":.string("笔记 \(index+1)"),"body":.string("滚动检查页面背景与悬浮控件。"),"createdAt":.int(now-Int64(index)),"updatedAt":.int(now-Int64(index))])}
            d.records += (0..<32).flatMap {index -> [Item] in
                let due=now+Int64(index+1)*3600000
                return [Item(["id":.string(String(format:"00000000-0000-0000-0000-%012d",2000+index)),"kind":.string("reminder"),"title":.string("提醒 \(index+1)"),"date":.int(now),"due":.int(due),"alertAt":.int(due),"period":.string("none"),"currency":.string("CNY"),"completed":.bool(false)]),
                 Item(["id":.string(String(format:"00000000-0000-0000-0000-%012d",3000+index)),"kind":.string("expense"),"title":.string("账目 \(index+1)"),"cents":.int(100),"currency":.string("CNY"),"account":.string(account),"category":.string("其他"),"date":.int(now-Int64(index)*3600000)])]
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-companion-legacy-name-fixture") {
            var state=CompanionData()
            state.messages=[CompanionMessage(role:"user",content:"你的名字是大肥鱼"),CompanionMessage(role:"assistant",content:"那我叫阿肥。",source:"本机伙伴")]
            try? state.write(to:&d)
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-companion-name-proposal-fixture") {
            var state=CompanionData()
            state.messages=[CompanionMessage(role:"user",content:"想好啦，以后你就用小鱼这个名字"),CompanionMessage(role:"assistant",content:"你想叫我小鱼吗？确认后我就用这个名字。",source:"名字待确认",nameProposal:"小鱼")]
            try? state.write(to:&d)
        }
        return d
    }
    @MainActor static func actionReply(_ question:String,tools:[[String:Any]],handler:ChatToolHandler?) async throws -> (String,String)? {
        guard ProcessInfo.processInfo.arguments.contains("--ui-action-fixture"),let handler,let tool=tools.first?["function"] as? [String:Any],let name=tool["name"] as? String else{return nil}
        var value:[String:Any]
        switch name {
        case "create_note":value=["title":"模拟器创建备忘录","body":"准备好水和运动鞋。"]
        case "create_record":
            let properties=(tool["parameters"] as? [String:Any])?["properties"] as? [String:Any]
            let kinds=(properties?["kind"] as? [String:Any])?["enum"] as? [String] ?? ["expense"]
            let kind=kinds.first ?? "expense"
            value=["kind":kind,"title":kind=="income" ? "模拟器收入":"模拟器午饭","amount":kind=="income" ? "200.00":"25.00","currency":"CNY","accountId":question.contains("中国工商银行") ? "00000000-0000-0000-0000-000000000001":"","category":"其他"]
        case "create_reminder":
            let tomorrow=Calendar.current.date(byAdding:.day,value:1,to:Date()) ?? Date().addingTimeInterval(86400)
            let due=Calendar.current.date(bySettingHour:9,minute:0,second:0,of:tomorrow) ?? tomorrow
            value=["title":"模拟器喝水提醒","body":"喝一杯水","due":ISO8601DateFormatter().string(from:due),"period":"none"]
        default:return nil
        }
        let result=try await handler(name,String(decoding:JSONSerialization.data(withJSONObject:value),as:UTF8.self))
        return (result.bool("saved") ? "保存成功。":result.text("message"),"模拟器工具协议样例")
    }
}
#endif

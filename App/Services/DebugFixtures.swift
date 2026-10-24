#if DEBUG
import Foundation

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
    static func document()->Document {
        var d=Document()
        let names=["中国工商银行","中国银行","汇丰银行","招商银行"]
        d.accounts=names.enumerated().map {index,name in
            Item(["id":.string(String(format:"00000000-0000-0000-0000-%012d",index+1)),"name":.string(name),"type":.string("bank"),"currency":.string(index==2 ? "HKD":"CNY"),"openingCents":.int(Int64((index+1)*100000)),"openingDate":.int(1)])
        }
        var wallet=d.wallet
        wallet.set("cards",items:d.accounts.enumerated().map {index,account in Item(["accountId":.string(account.id),"institution":.string(account.text("name")),"lastFour":.string(String(1231+index)),"network":.string(index==2 ? "mastercard":"unionpay")])})
        d.wallet=wallet
        if ProcessInfo.processInfo.arguments.contains("--ui-debt-fixture") {
            let start=Calendar.current.date(byAdding:.day,value:-1,to:Date()) ?? Date()
            let first=Calendar.current.date(byAdding:.month,value:1,to:Date()) ?? Date()
            let loan=Item(["id":.string("00000000-0000-0000-0000-000000000201"),"name":.string("消费贷示例"),"type":.string("online"),"accountId":.string(d.accounts[0].id),"principalCents":.int(200000),"receivedCents":.int(200000),"recordReceipt":.bool(true),"months":.int(12),"annualBps":.int(2400),"monthlyFeeCents":.int(0),"method":.string("annuity"),"baseDate":.string(Clock.day(start)),"firstDue":.string(Clock.day(first))])
            if let seeded=try? Loans.save(loan,in:d) {d=Loans.refreshReminders(seeded)}
        }
        d.notes=[Item(["id":.string("00000000-0000-0000-0000-000000000100"),"title":.string("版式检查笔记"),"body":.string("想去天安门看看，也想去西安。\n\n## 摘要\n\n- 想去北京和西安。"),"createdAt":.int(Clock.milliseconds),"updatedAt":.int(Clock.milliseconds)])]
        if ProcessInfo.processInfo.arguments.contains("--ui-scroll-fixture") {
            d.notes=(0..<32).map {index in Item(["id":.string("scroll-note-\(index)"),"title":.string("笔记 \(index+1)"),"body":.string("滚动检查页面背景与悬浮控件。"),"updatedAt":.int(Clock.milliseconds-Int64(index))])}
            d.records=(0..<32).flatMap {index -> [Item] in
                [Item(["id":.string("scroll-reminder-\(index)"),"kind":.string("reminder"),"title":.string("提醒 \(index+1)"),"due":.int(Clock.milliseconds+Int64(index)*3600000),"completed":.bool(false)]),
                 Item(["id":.string("scroll-expense-\(index)"),"kind":.string("expense"),"title":.string("账目 \(index+1)"),"cents":.int(100),"currency":.string("CNY"),"date":.int(Clock.milliseconds-Int64(index)*3600000)])]
            }
        }
        return d
    }
}
#endif

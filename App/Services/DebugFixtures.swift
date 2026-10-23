#if DEBUG
import Foundation

enum DebugFixtures {
    static var motion:Bool {ProcessInfo.processInfo.arguments.contains("--ui-motion-fixture")}
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
        d.notes=[Item(["id":.string("00000000-0000-0000-0000-000000000100"),"title":.string("版式检查笔记"),"body":.string("想去天安门看看，也想去西安。\n\n## 摘要\n\n- 想去北京和西安。"),"createdAt":.int(Clock.milliseconds),"updatedAt":.int(Clock.milliseconds)])]
        return d
    }
}
#endif

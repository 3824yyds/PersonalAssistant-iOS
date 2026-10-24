import XCTest
@testable import AssistantCore

final class ChatActionsTests:XCTestCase {
    let now=ISO8601DateFormatter().date(from:"2026-10-24T12:00:00Z")!
    func document(two:Bool=false)->Document {
        var d=Document();d.accounts=[Item.make(["name":.string("现金"),"currency":.string("CNY"),"type":.string("cash"),"openingDate":.int(1),"openingCents":.int(10000)])]
        if two {d.accounts.append(Item.make(["name":.string("支付宝"),"currency":.string("CNY"),"type":.string("bank"),"openingDate":.int(1),"openingCents":.int(20000)]))}
        return d
    }
    func record(_ amount:String="25.50")->Item {Item(["title":.string("午饭"),"amount":.string(amount),"currency":.string("CNY")])}
    func testExplicitCreationAndNaturalFinancialEntriesAreAuthorized() {
        XCTAssertEqual(ChatActions.permissions("帮我写一个备忘录笔记，内容是明天去爬山"),[.note])
        XCTAssertEqual(ChatActions.permissions("帮我直接记录到备忘录笔记里"),[.note])
        XCTAssertEqual(ChatActions.permissions("今天午饭花了25.50元"),[.expense])
        XCTAssertEqual(ChatActions.permissions("工资收入8000元"),[.income])
        XCTAssertEqual(ChatActions.permissions("帮我记一笔25元"),[.expense])
        XCTAssertEqual(ChatActions.permissions("帮我记账"),[.expense])
        XCTAssertEqual(ChatActions.permissions("明天早上9点提醒我喝水"),[.reminder])
    }
    func testQuestionsNegationsQuotedCommandsAndCalculationsNeverAuthorizeWrites() {
        for q in ["不要保存这个笔记","如何创建提醒","我这个月收入多少？","如果花了25元还剩多少","翻译：帮我创建笔记","他说“帮我写一个笔记”","取消"] {XCTAssertTrue(ChatActions.permissions(q,continuing:[.expense]).isEmpty,q)}
    }
    func testClarificationOnlyContinuesPendingKindAndNewIntentReplacesIt() {
        XCTAssertEqual(ChatActions.permissions("支付宝",continuing:[.expense]),[.expense])
        XCTAssertEqual(ChatActions.permissions("明天早上9点",continuing:[.reminder]),[.reminder])
        XCTAssertTrue(ChatActions.permissions("你好",continuing:[.expense]).isEmpty)
        XCTAssertEqual(ChatActions.permissions("帮我创建一篇笔记",continuing:[.expense]),[.note])
    }
    func testExpenseAndIncomeUpdateRealBalancesAndTotals() throws {
        let d=document(),id=UUID().uuidString
        let (spent,receipt)=try ChatActions.create(record(),kind:.expense,id:id,in:d,source:"午饭花了25.50元",now:now)
        XCTAssertEqual(Finance.balance(d.accounts[0],in:spent,at:Clock.milliseconds),7450);XCTAssertEqual(Totals(spent.records).expense,2550)
        XCTAssertEqual(receipt.kind,.expense);XCTAssertTrue(receipt.detail.contains("现金"))
        let (paid,_)=try ChatActions.create(record("8000.00"),kind:.income,id:UUID().uuidString,in:spent,source:"收入8000元",now:now)
        XCTAssertEqual(Totals(paid.records).income,800000);XCTAssertEqual(Finance.balance(d.accounts[0],in:paid,at:Clock.milliseconds),807450)
    }
    func testInsufficientFundsAndInvalidMoneyDoNotCreateAnything() {
        let d=document()
        for value in ["100.01","-1.00","0.00","1.001","NaN"] {XCTAssertThrowsError(try ChatActions.create(record(value),kind:.expense,id:UUID().uuidString,in:d,source:"今天支出"+value+"元",now:now),value)}
        XCTAssertTrue(d.records.isEmpty)
    }
    func testMultipleAccountsNeedExplicitSelectionAndCannotBeInvented() throws {
        let d=document(two:true)
        XCTAssertThrowsError(try ChatActions.create(record(),kind:.expense,id:UUID().uuidString,in:d,source:"花25元",now:now))
        var draft=record();draft.set("accountId",d.accounts[1].id)
        XCTAssertThrowsError(try ChatActions.create(draft,kind:.expense,id:UUID().uuidString,in:d,source:"花25元",now:now))
        let (saved,_)=try ChatActions.create(draft,kind:.expense,id:UUID().uuidString,in:d,source:"用支付宝花25元",now:now)
        XCTAssertEqual(saved.records[0].text("account"),"支付宝")
        draft.set("accountId","不存在的银行")
        XCTAssertThrowsError(try ChatActions.create(draft,kind:.expense,id:UUID().uuidString,in:d,source:"花25元",now:now))
    }
    func testLoanPrincipalIsNeverOrdinaryIncomeOrExpense() {
        for source in ["借款到账2000元","贷款2000元","还本金200元"] {XCTAssertThrowsError(try ChatActions.create(record("20.00"),kind:.income,id:UUID().uuidString,in:document(),source:source,now:now))}
    }
    func testOneCreationIdIsIdempotentAndExistingDataIsNeverOverwritten() throws {
        let id=UUID().uuidString,draft=Item(["title":.string("爬山"),"body":.string("明天去岳麓山")])
        let (saved,receipt)=try ChatActions.create(draft,kind:.note,id:id,in:document(),source:"帮我写笔记",now:now)
        let (again,second)=try ChatActions.create(Item(["title":.string("不应覆盖")]),kind:.note,id:id,in:saved,source:"",now:now)
        XCTAssertEqual(saved,again);XCTAssertEqual(receipt.id,second.id);XCTAssertEqual(again.notes.count,1);XCTAssertEqual(again.notes[0].text("body"),"明天去岳麓山")
    }
    func testReminderRequiresFutureTimeAndPreservesTimeZoneAndRepeat() throws {
        let draft=Item(["title":.string("喝水"),"due":.string("2026-10-25T09:00:00+08:00"),"period":.string("daily")])
        let (d,receipt)=try ChatActions.create(draft,kind:.reminder,id:UUID().uuidString,in:document(),source:"明天9点提醒我喝水",now:now)
        XCTAssertEqual(d.records[0].int("due"),Int64(ChatActions.date("2026-10-25T01:00:00Z")!.timeIntervalSince1970*1000))
        XCTAssertEqual(d.records[0].int("alertAt"),d.records[0].int("due"));XCTAssertEqual(d.records[0].text("period"),"daily");XCTAssertEqual(receipt.kind,.reminder)
        for time in ["","明天","2026-10-23T09:00:00+08:00"] {var invalid=draft;invalid.set("due",time);XCTAssertThrowsError(try ChatActions.create(invalid,kind:.reminder,id:UUID().uuidString,in:document(),source:"明天9点提醒我",now:now))}
    }
    func testFutureFinancialEntriesAreNotFabricatedAsActualCash() {
        var draft=record();draft.set("date","2026-10-25T12:00:00Z")
        XCTAssertThrowsError(try ChatActions.create(draft,kind:.income,id:UUID().uuidString,in:document(),source:"收入25.50元",now:now))
    }
    func testResponseCanBeSavedWithoutAnotherModelRequest() {
        let draft=ChatActions.noteDraft("这里是计划。\n\n标题：明天爬岳麓山\n\n- 带水\n- 查看天气")
        XCTAssertEqual(draft.text("title"),"明天爬岳麓山");XCTAssertTrue(draft.text("body").contains("查看天气"))
    }
    func testSavePreviousIntentDoesNotReplaceAnExplicitNewBody() {
        XCTAssertTrue(ChatActions.savesPreviousNote("帮我直接记录到备忘录笔记里"))
        XCTAssertTrue(ChatActions.savesPreviousNote("把上面的回答保存到备忘录"))
        XCTAssertFalse(ChatActions.savesPreviousNote("帮我保存笔记，内容是明天爬山"))
        XCTAssertFalse(ChatActions.savesPreviousNote("不要保存上面的笔记"))
    }
    func testModelCannotInventMissingMoneyOrReminderTime() {
        XCTAssertThrowsError(try ChatActions.create(record(),kind:.expense,id:UUID().uuidString,in:document(),source:"帮我记一笔午饭",now:now))
        XCTAssertThrowsError(try ChatActions.create(record(),kind:.income,id:UUID().uuidString,in:document(),source:"2026年10月24日工资到账",now:now))
        let draft=Item(["title":.string("喝水"),"due":.string("2026-10-25T09:00:00+08:00")])
        XCTAssertThrowsError(try ChatActions.create(draft,kind:.reminder,id:UUID().uuidString,in:document(),source:"明天提醒我喝水",now:now))
    }
}

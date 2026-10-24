import XCTest
@testable import PersonalAssistant

final class WealthCashTests:XCTestCase {
    private func account(_ opening:Int64=0)->Item {Item.make(["name":.string("现金"),"currency":.string("CNY"),"type":.string("cash"),"openingCents":.int(opening),"openingDate":.int(1)])}
    private func subscription(_ account:Item)->Item {Item.make(["name":.string("会员"),"accountId":.string(account.id),"cents":.int(1000),"cycle":.string("monthly"),"firstDue":.string(Clock.day()),"active":.bool(true)])}
    func testSubscriptionInsufficientFundsDoesNotChangeCycleOrCreateReceipt() throws {
        var d=Document();let a=account(999),s=subscription(a);d.accounts=[a];d.upsertWealth(s,in:"subscriptions")
        let due=WealthOperations.subscriptionDue(s,in:d)
        XCTAssertThrowsError(try WealthOperations.paySubscription(s,in:d,expectedDue:due))
        XCTAssertTrue(d.records.isEmpty);XCTAssertEqual(WealthOperations.subscriptionDue(s,in:d),due)
    }
    func testSubscriptionConfirmationIsIdempotentForDisplayedCycleAndRejectsStaleEdit() throws {
        var d=Document();let a=account(3000),s=subscription(a);d.accounts=[a];d.upsertWealth(s,in:"subscriptions")
        let due=WealthOperations.subscriptionDue(s,in:d)
        d=try WealthOperations.paySubscription(s,in:d,expectedDue:due)
        let once=d;d=try WealthOperations.paySubscription(s,in:d,expectedDue:due)
        XCTAssertEqual(d,once);XCTAssertEqual(Finance.balance(a,in:d),2000)
        let next=WealthOperations.subscriptionDue(s,in:d);var edited=s;edited.set("cents",2000);d.upsertWealth(edited,in:"subscriptions")
        XCTAssertThrowsError(try WealthOperations.paySubscription(s,in:d,expectedDue:next))
    }
    func testInvestmentBuyChecksFeesAndCashBeforeUpdatingPosition() throws {
        var d=Document();let a=account(1000),asset=Item.make(["name":.string("基金"),"currency":.string("CNY"),"cents":.int(0)])
        d.accounts=[a];d.upsertWallet(asset,in:"assets");d.upsertWealth(Item(["assetId":.string(asset.id),"price":.string("10")]),in:"positions")
        var buy=Item.make(["assetId":.string(asset.id),"accountId":.string(a.id),"side":.string("buy"),"quantity":.string("1"),"grossCents":.int(1000),"feeCents":.int(1),"date":.int(Clock.milliseconds)])
        XCTAssertThrowsError(try WealthOperations.trade(buy,in:d));XCTAssertTrue(d.wealth.items("trades").isEmpty)
        buy.set("feeCents",Int64(0));d=try WealthOperations.trade(buy,in:d)
        XCTAssertEqual(Finance.balance(a,in:d),0);XCTAssertEqual(d.wallet.items("assets").first?.int("cents"),1000)
        var sell=buy;sell.set("id",UUID().uuidString);sell.set("side","sell");sell.set("grossCents",1200)
        d=try WealthOperations.trade(sell,in:d);XCTAssertEqual(Finance.balance(a,in:d),1200)
    }
    func testAAAdvanceAndSettlementCannotSpendAbsentCash() throws {
        var d=Document();let a=account(),g=Item.make(["name":.string("聚餐"),"members":.array([.string("我"),.string("朋友")]),"me":.string("我"),"currency":.string("CNY")])
        d.accounts=[a];d.upsertWealth(g,in:"groups")
        var split=Item.make(["groupId":.string(g.id),"title":.string("晚餐"),"cents":.int(2000),"payer":.string("我"),"shares":.array([.object(["member":.string("我"),"cents":.int(1000)]),.object(["member":.string("朋友"),"cents":.int(1000)])]),"accountId":.string(a.id),"date":.int(Clock.milliseconds)])
        XCTAssertThrowsError(try WealthOperations.addSplit(split,group:g,in:d))
        split.set("payer","朋友");d=try WealthOperations.addSplit(split,group:g,in:d);XCTAssertEqual(Finance.balance(a,in:d),0)
        let settle=Item.make(["groupId":.string(g.id),"from":.string("我"),"to":.string("朋友"),"cents":.int(1000),"accountId":.string(a.id),"date":.int(Clock.milliseconds)])
        XCTAssertThrowsError(try WealthOperations.settle(settle,group:g,in:d))
    }
}

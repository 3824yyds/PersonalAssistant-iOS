import XCTest
@testable import AssistantCore

final class CashValidationTests:XCTestCase {
    private func account(_ name:String="现金",opening:Int64=0,type:String="cash")->Item {
        Item.make(["name":.string(name),"currency":.string("CNY"),"type":.string(type),"openingCents":.int(opening),"openingDate":.int(1)])
    }
    private func record(_ kind:String,cents:Int64,account:String="现金",date:Int64=Clock.milliseconds)->Item {
        Item.make(["title":.string("现金校验"),"kind":.string(kind),"cents":.int(cents),"currency":.string("CNY"),"account":.string(account),"date":.int(date)])
    }
    func testManualExpenseAndEditingUseSameCashRule() throws {
        var d=Document();let a=account(opening:1000);d.accounts=[a]
        XCTAssertThrowsError(try Finance.saveRecord(record("expense",cents:1001),in:d))
        var e=record("expense",cents:800);d=try Finance.saveRecord(e,in:d)
        e.set("cents",1001);XCTAssertThrowsError(try Finance.saveRecord(e,in:d))
        e.set("cents",600);d=try Finance.saveRecord(e,in:d);XCTAssertEqual(Finance.balance(a,in:d),400)
    }
    func testIncomeCannotBeReducedDeletedOrMovedToAnotherAccountAfterSpending() throws {
        var d=Document();let a=account(),b=account("银行卡");d.accounts=[a,b]
        var income=record("income",cents:1000);d=try Finance.saveRecord(income,in:d)
        d=try Finance.saveRecord(record("expense",cents:700),in:d)
        XCTAssertThrowsError(try Finance.deleteRecord(income.id,in:d))
        income.set("cents",699);XCTAssertThrowsError(try Finance.saveRecord(income,in:d))
        income.set("cents",1000);income.set("account","银行卡");XCTAssertThrowsError(try Finance.saveRecord(income,in:d))
        XCTAssertEqual(Finance.balance(a,in:d),300);XCTAssertEqual(d.records.count,2)
    }
    func testDeletingRefundAlreadySpentCannotCreateCashDebt() throws {
        var d=Document();let a=account(opening:1000);d.accounts=[a]
        let e=record("expense",cents:1000);d=try Finance.saveRecord(e,in:d)
        var refund=record("refund",cents:500);refund.set("linkId",e.id);d=try Finance.saveRecord(refund,in:d)
        d=try Finance.saveRecord(record("expense",cents:500),in:d)
        XCTAssertThrowsError(try Finance.deleteRecord(refund.id,in:d))
        d=try Finance.deleteRecord(e.id,in:d);XCTAssertEqual(Finance.balance(a,in:d),500)
    }
    func testMovingOldIncomeLaterCannotHideAnEarlierCashShortfall() throws {
        var d=Document();let a=account();d.accounts=[a]
        let yesterday=Calendar.current.date(byAdding:.day,value:-1,to:Date())!
        let before=Calendar.current.date(byAdding:.day,value:-1,to:yesterday)!
        var income=record("income",cents:1000,date:Int64(before.timeIntervalSince1970*1000))
        d=try Finance.saveRecord(income,in:d)
        d=try Finance.saveRecord(record("expense",cents:500,date:Int64(yesterday.timeIntervalSince1970*1000)),in:d)
        income.set("date",Clock.milliseconds);XCTAssertThrowsError(try Finance.saveRecord(income,in:d))
    }
    func testLegacyShortfallCanBeRepairedButCannotWorsen() throws {
        var d=Document();var a=account(opening:-500);d.accounts=[a]
        d=try Finance.saveRecord(record("income",cents:200),in:d);XCTAssertEqual(Finance.balance(a,in:d),-300)
        XCTAssertThrowsError(try Finance.saveRecord(record("expense",cents:1),in:d))
        a.set("openingCents",0);d=try Finance.saveAccount(a,card:nil,in:d)
        XCTAssertEqual(Finance.balance(a,in:d),200)
    }
    func testNewCashOpeningDebtRejectedWhileCreditAccountRemainsExplicit() throws {
        let d=Document();XCTAssertThrowsError(try Finance.saveAccount(account(opening:-1),card:nil,in:d))
        let credit=account("信用卡",opening:-1000,type:"credit")
        var next=try Finance.saveAccount(credit,card:nil,in:d)
        next=try Finance.saveRecord(record("expense",cents:200,account:"信用卡"),in:next)
        XCTAssertEqual(Finance.balance(credit,in:next),-1200)
    }
    func testManualFutureTransactionRequiresReminderButExistingImportCanBeCorrected() throws {
        var d=Document();let a=account(opening:1000);d.accounts=[a]
        let tomorrow=Clock.milliseconds+86_400_000;var future=record("income",cents:100,date:tomorrow)
        XCTAssertThrowsError(try Finance.saveRecord(future,in:d))
        d.records=[future];future.set("title","修正导入的未来流水标题")
        d=try Finance.saveRecord(future,in:d);XCTAssertEqual(d.records.first?.int("date"),tomorrow)
    }
    func testExpenseCannotMoveToUnfundedAccountOrArchivedAccount() throws {
        var d=Document();let a=account(opening:1000);var b=account("银行卡");d.accounts=[a,b]
        var e=record("expense",cents:500);d=try Finance.saveRecord(e,in:d)
        e.set("account","银行卡");XCTAssertThrowsError(try Finance.saveRecord(e,in:d))
        b.set("archived",true);d.accounts=[a,b];e.set("kind","income");XCTAssertThrowsError(try Finance.saveRecord(e,in:d))
    }
}

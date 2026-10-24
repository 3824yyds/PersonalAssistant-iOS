import XCTest
@testable import AssistantCore

final class DebtTests:XCTestCase {
    func account(_ name:String="支付宝",balance:Int64=0,currency:String="CNY",type:String="wallet")->Item {
        Item.make(["name":.string(name),"currency":.string(currency),"type":.string(type),"openingDate":.int(1),"openingCents":.int(balance)])
    }
    func loan(_ account:Item,receipt:Bool=true)->Item {
        Item.make(["name":.string("测试消费贷"),"accountId":.string(account.id),"principalCents":.int(200000),"receivedCents":.int(200000),"recordReceipt":.bool(receipt),"months":.int(12),"annualBps":.int(2400),"monthlyFeeCents":.int(0),"method":.string("annuity"),"baseDate":.string("2026-01-01"),"firstDue":.string("2026-02-01")])
    }
    func setup(balance:Int64=0,receipt:Bool=true)throws ->(Document,Item,Item) {
        var d=Document();let a=account(balance:balance);d.accounts=[a];let l=loan(a,receipt:receipt);d=try Loans.save(l,in:d);return(d,a,l)
    }
    func payment(_ l:Item,_ a:Item,principal:Int64=10000,interest:Int64=4000,fee:Int64=0,period:Int=1,id:String=UUID().uuidString.lowercased())->LoanPayment {
        LoanPayment(id:id,period:period,accountID:a.id,date:Clock.date("2026-02-01")!,principal:principal,interest:interest,fee:fee)
    }
    func testBorrowingIncreasesCashAndDebtWithoutIncome() throws {
        let(d,a,l)=try setup();XCTAssertEqual(Finance.balance(a,in:d),200000);XCTAssertEqual(Loans.outstanding(l,in:d),200000)
        XCTAssertEqual(Totals(d.records).income,0);XCTAssertEqual(BalanceSheet(d,currency:"CNY").netWorth,0)
    }
    func testWithheldFeeUsesActualCashAndIsExpense() throws {
        var(d,a,l)=try setup();l.set("receivedCents",Int64(195000));d=try Loans.save(l,in:d)
        XCTAssertEqual(Finance.balance(a,in:d),195000);XCTAssertEqual(Totals(d.records).expense,5000);XCTAssertEqual(Loans.outstanding(l,in:d),200000)
    }
    func testExistingDebtDoesNotCreateCashOrIncome() throws {
        let(d,a,l)=try setup(receipt:false);XCTAssertEqual(Finance.balance(a,in:d),0);XCTAssertEqual(Loans.outstanding(l,in:d),200000);XCTAssertTrue(d.records.isEmpty)
    }
    func testOpeningPaidPeriodsReduceDebtWithoutReplayingCash() throws {
        var(d,a,l)=try setup(receipt:false);l.set("openingPaidPeriods",Int64(2));d=try Loans.save(l,in:d)
        let rows=try Loans.schedule(l);XCTAssertEqual(Loans.outstanding(l,in:d),200000-rows.prefix(2).reduce(0,{$0+$1.principal}));XCTAssertEqual(Loans.due(rows[0],loan:l,in:d).total,0);XCTAssertEqual(Finance.balance(a,in:d),0)
    }
    func testRepaymentSplitsPrincipalAndCosts() throws {
        var(d,a,l)=try setup();d=try Loans.savePayment(payment(l,a,fee:100),loanID:l.id,in:d)
        XCTAssertEqual(Finance.balance(a,in:d),185900);XCTAssertEqual(Loans.outstanding(l,in:d),190000);XCTAssertEqual(Totals(d.records).expense,4100)
    }
    func testInsufficientBalanceRejectsEntirePaymentIncludingFees() throws {
        let(d,a,l)=try setup(balance:14000,receipt:false);let original=d
        XCTAssertThrowsError(try Loans.savePayment(payment(l,a,fee:1),loanID:l.id,in:d));XCTAssertEqual(d,original)
    }
    func testZeroBalanceCannotBecomeNegative() throws {
        let(d,a,l)=try setup(receipt:false);XCTAssertThrowsError(try Loans.savePayment(payment(l,a),loanID:l.id,in:d));XCTAssertEqual(Finance.balance(a,in:d),0)
    }
    func testLaterIncomeCannotFundBackdatedRepayment() throws {
        var(d,a,l)=try setup(receipt:false)
        d.records=[Item.make(["kind":.string("income"),"title":.string("后来的工资"),"cents":.int(50000),"currency":.string("CNY"),"account":.string(a.text("name")),"date":.int(Int64(Clock.date("2026-03-01")!.timeIntervalSince1970*1000))])]
        XCTAssertThrowsError(try Loans.savePayment(payment(l,a),loanID:l.id,in:d))
    }
    func testPartialAndMultiplePaymentsOnlyCompleteWhenAllComponentsPaid() throws {
        var(d,a,l)=try setup();let row=try XCTUnwrap(Loans.schedule(l).first)
        d=try Loans.savePayment(payment(l,a,principal:10000,interest:0),loanID:l.id,in:d)
        XCTAssertGreaterThan(Loans.due(row,loan:l,in:d).total,0)
        d=try Loans.savePayment(payment(l,a,principal:row.principal-10000,interest:row.interest),loanID:l.id,in:d)
        XCTAssertEqual(Loans.due(row,loan:l,in:d).total,0);XCTAssertEqual(Loans.payments(l,in:d).count,2)
        XCTAssertThrowsError(try Loans.savePayment(payment(l,a,principal:1),loanID:l.id,in:d))
    }
    func testEditingPaymentReplacesGroupWithoutDoubleDebit() throws {
        var(d,a,l)=try setup();let id=UUID().uuidString.lowercased();d=try Loans.savePayment(payment(l,a,id:id),loanID:l.id,in:d)
        d=try Loans.savePayment(payment(l,a,principal:5000,interest:2000,id:id),loanID:l.id,in:d)
        XCTAssertEqual(Loans.payments(l,in:d).count,1);XCTAssertEqual(Finance.balance(a,in:d),193000);XCTAssertEqual(Loans.outstanding(l,in:d),195000)
    }
    func testPaymentCannotUseArchivedCreditOrWrongCurrencyAccount() throws {
        let(d,_,l)=try setup()
        for (currency,type,archived) in [("HKD","bank",false),("CNY","credit",false),("CNY","bank",true)] {
            var next=d;var a=account("另一个账户",balance:500000,currency:currency,type:type);a.set("archived",archived);next.accounts.append(a)
            XCTAssertThrowsError(try Loans.savePayment(payment(l,a),loanID:l.id,in:next))
        }
    }
    func testUndoPaymentRestoresCashDebtAndCosts() throws {
        var(d,a,l)=try setup();let p=payment(l,a);let before=d;d=try Loans.savePayment(p,loanID:l.id,in:d);d=try Loans.deletePayment(p.id,loanID:l.id,in:d)
        XCTAssertEqual(Finance.balance(a,in:d),Finance.balance(a,in:before));XCTAssertEqual(Loans.outstanding(l,in:d),200000);XCTAssertEqual(Totals(d.records).expense,0)
    }
    func testEditingLoanKeepsIdentityAndCannotReducePrincipalBelowRepaid() throws {
        var(d,a,l)=try setup();d=try Loans.savePayment(payment(l,a),loanID:l.id,in:d);l.set("name","更正后的名称");d=try Loans.save(l,in:d)
        XCTAssertEqual(d.wallet.items("loans").count,1);XCTAssertEqual(Loans.payments(l,in:d).count,1)
        l.set("principalCents",Int64(5000));l.set("receivedCents",Int64(5000));XCTAssertThrowsError(try Loans.save(l,in:d))
    }
    func testDeleteLoanRollsBackItsLinkedFlows() throws {
        var(d,a,l)=try setup();d=try Loans.savePayment(payment(l,a),loanID:l.id,in:d);d=try Loans.delete(l.id,in:d)
        XCTAssertTrue(d.wallet.items("loans").isEmpty);XCTAssertTrue(d.records.isEmpty);XCTAssertEqual(Finance.balance(a,in:d),0)
    }
    func testCannotDeleteSpentLoanAndLeaveUnfundedCash() throws {
        var(d,a,l)=try setup();d.records.append(Item.make(["kind":.string("expense"),"title":.string("已消费"),"cents":.int(10000),"currency":.string("CNY"),"account":.string(a.text("name")),"date":.int(Int64(Clock.date("2026-02-01")!.timeIntervalSince1970*1000))]))
        XCTAssertThrowsError(try Loans.delete(l.id,in:d))
    }
    func testTransferCannotOverdrawCashButCreditCanBorrow() throws {
        var d=Document();let a=account(),b=account("银行卡");d.accounts=[a,b];XCTAssertThrowsError(try Finance.transfer(d,from:a.id,to:b.id,cents:1))
        let credit=account("信用卡",type:"credit");d.accounts.append(credit);d=try Finance.transfer(d,from:credit.id,to:b.id,cents:100);XCTAssertEqual(Finance.balance(credit,in:d),-100)
    }
    func testBalanceSheetIncludesLoansManualDebtsAndCreditSeparately() throws {
        var(d,_,_)=try setup();d.accounts.append(account("信用卡",balance:-5000,type:"credit"));d.upsertWallet(Item.make(["name":.string("其他应付款"),"kind":.string("debt"),"currency":.string("CNY"),"cents":.int(3000)]),in:"assets")
        let sheet=BalanceSheet(d,currency:"CNY");XCTAssertEqual(sheet.assets,200000);XCTAssertEqual(sheet.liabilities,208000);XCTAssertEqual(sheet.netWorth,-8000);XCTAssertEqual(BalanceSheet(d,currency:"HKD").liabilities,0)
    }
    func testEarlyPaymentRequiresReviewAndCannotOverpayPrincipal() throws {
        var(d,a,l)=try setup();d=try Loans.savePayment(payment(l,a,principal:100000,interest:0,period:-1),loanID:l.id,in:d)
        let changed=try XCTUnwrap(d.wallet.items("loans").first);XCTAssertEqual(Loans.outstanding(l,in:d),100000);XCTAssertTrue(Loans.needsPlanReview(changed,in:d))
        XCTAssertThrowsError(try Loans.savePayment(payment(l,a,principal:100001,interest:0,period:-1),loanID:l.id,in:d))
    }
    func testContractPlanSupportsExactDatesAndCostsAndMustReconcilePrincipal() throws {
        var(d,_,l)=try setup();let original=try Loans.schedule(l)
        var rows=original;let first=rows[0];rows[0]=Installment(id:1,date:first.date,principal:first.principal,interest:1234,fee:99)
        d=try Loans.savePlan(rows,loanID:l.id,in:d);let loan=try XCTUnwrap(d.wallet.items("loans").first)
        XCTAssertEqual(try Loans.schedule(loan).first?.interest,1234)
        rows.removeLast();XCTAssertThrowsError(try Loans.savePlan(rows,loanID:l.id,in:d))
    }
    func testLumpSumAndRateChanges() throws {
        let(_,_,original)=try setup();var l=original;l.set("method","lump");l.set("months",Int64(3));l.set("annualBps",Int64(1200))
        let plan=try Loans.schedule(l);XCTAssertEqual(plan.map(\.principal),[0,0,200000]);XCTAssertEqual(plan.map(\.interest),[0,0,6000])
        l.set("method","bullet");l.set("rateChanges",items:[Item(["from":.string("2026-03-01"),"annualBps":.int(600)])]);XCTAssertEqual(try Loans.schedule(l).map(\.interest),[2000,1000,1000])
    }
    func testExtremeValidAnnuityRemainsFiniteAndPaysExactPrincipal() throws {
        let(_,_,original)=try setup();var l=original;l.set("principalCents",Money.maximum);l.set("annualBps",Int64(20000));l.set("months",Int64(480))
        let plan=try Loans.schedule(l);XCTAssertEqual(plan.reduce(Int64(0),{$0+$1.principal}),Money.maximum);XCTAssertTrue(plan.allSatisfy {$0.principal>=0 && $0.interest>=0})
    }
    func testRemindersAutomaticallyReflectPartialPaymentUndoAndDeletion() throws {
        var(d,a,l)=try setup();d=Loans.refreshReminders(d)
        let first=try XCTUnwrap(d.records.first {$0.bool("loanReminder") && $0.int("linkedLoanPeriod")==1});XCTAssertEqual(d.records.filter {$0.bool("loanReminder")}.count,12)
        XCTAssertEqual(Loans.refreshReminders(d).records.filter {$0.id==first.id}.count,1)
        let row=try XCTUnwrap(Loans.schedule(l).first),p=payment(l,a,principal:row.principal,interest:row.interest)
        d=Loans.refreshReminders(try Loans.savePayment(p,loanID:l.id,in:d));XCTAssertFalse(d.records.contains {$0.id==first.id})
        d=Loans.refreshReminders(try Loans.deletePayment(p.id,loanID:l.id,in:d));XCTAssertEqual(d.records.filter {$0.bool("loanReminder")}.count,12)
        d=Loans.refreshReminders(try Loans.delete(l.id,in:d));XCTAssertFalse(d.records.contains {$0.bool("loanReminder")})
    }
    func testRemindersHaveLeadAndDueAlertsAndNeverAffectMoney() throws {
        let(d,a,l)=try setup();let next=Loans.refreshReminders(d),reminder=try XCTUnwrap(next.records.first {$0.bool("loanReminder")})
        XCTAssertLessThan(reminder.int("leadAt"),reminder.int("due"));XCTAssertEqual(reminder.int("alertAt"),reminder.int("due"));XCTAssertEqual(Finance.balance(a,in:next),200000);XCTAssertEqual(Loans.payments(l,in:next).count,0);_=try next.validated()
    }
    func testExistingNegativeBalanceCanBeRepairedButNotWorsened() throws {
        var(d,a,l)=try setup(balance:0,receipt:false)
        let p=payment(l,a);for(kind,category,amount) in [("loan_principal","贷款本金",p.principal),("expense","贷款利息",p.interest)] {d.records.append(Item.make(["kind":.string(kind),"title":.string("旧版本还款"),"cents":.int(amount),"category":.string(category),"currency":.string("CNY"),"account":.string(a.text("name")),"date":.int(Int64(p.date.timeIntervalSince1970*1000)),"loanId":.string(l.id),"loanPeriod":.int(1),"loanGroupId":.string(p.id)]))}
        XCTAssertThrowsError(try Loans.savePayment(payment(l,a,period:2),loanID:l.id,in:d))
        d=try Loans.deletePayment(p.id,loanID:l.id,in:d);XCTAssertEqual(Finance.balance(a,in:d),0)
    }
    func testMetadataEditsPreserveReceiptIdentityAndFeeRefund() throws {
        var(d,a,l)=try setup();l.set("receivedCents",Int64(195000));d=try Loans.save(l,in:d)
        let fee=try XCTUnwrap(d.records.first {$0.text("kind")=="expense"})
        let receiptID=try XCTUnwrap(d.records.first {$0.text("kind")=="loan_in"}).id
        d.records.append(Item.make(["title":.string("费用退回"),"kind":.string("refund"),"linkId":.string(fee.id),"cents":.int(1000),"currency":.string("CNY"),"account":.string(a.text("name")),"date":.int(Clock.milliseconds)]))
        l.set("name","更正名称");d=try Loans.save(l,in:d)
        XCTAssertTrue(d.records.contains {$0.id==receiptID});XCTAssertTrue(d.records.contains {$0.text("linkId")==fee.id});XCTAssertEqual(Finance.balance(a,in:d),196000)
    }
}

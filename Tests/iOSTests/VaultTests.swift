import XCTest
import CryptoKit
@testable import PersonalAssistant

final class VaultTests:XCTestCase {
    @MainActor func testCancellingReplyInvalidatesOnlyPendingOutput() {
        let store=AppStore();store.messages=[ChatMessage(role:"user",content:"你好"),ChatMessage(role:"assistant",content:"")];store.activeReplyID="old";store.assistantBusy=true
        store.cancelReply();XCTAssertNil(store.activeReplyID);XCTAssertFalse(store.assistantBusy);XCTAssertEqual(store.messages.count,1)
    }
    @MainActor func testCancellingReplyPreservesAlreadyDisplayedText() {
        let store=AppStore();store.messages=[ChatMessage(role:"user",content:"你好"),ChatMessage(role:"assistant",content:"你好！")];store.activeReplyID="old";store.assistantBusy=true
        store.cancelReply();XCTAssertEqual(store.messages.last?.content,"你好！");XCTAssertFalse(store.assistantBusy)
    }
    func testEnvelopeRoundTripAndAuthentication() throws {
        let salt=try VaultCrypto.random(32),key=try VaultCrypto.derive(password:"test-password-351",salt:salt),plain=Data("测试笔记与财务资料".utf8)
        let encrypted=try VaultCrypto.encrypt(plain,key:key,salt:salt)
        XCTAssertEqual(try VaultCrypto.decrypt(encrypted,key:key),plain)
        XCTAssertEqual(try VaultCrypto.salt(encrypted),salt)
        var changed=encrypted;changed[60]^=1
        XCTAssertThrowsError(try VaultCrypto.decrypt(changed,key:key))
        var header=encrypted;header[12]^=1
        XCTAssertThrowsError(try VaultCrypto.decrypt(header,key:key))
    }
    func testWrongPasswordRejected() throws {
        let salt=try VaultCrypto.random(32),key=try VaultCrypto.derive(password:"test-password-351",salt:salt)
        let encrypted=try VaultCrypto.encrypt(Data("private".utf8),key:key,salt:salt)
        let other=try VaultCrypto.derive(password:"wrong-password-351",salt:salt)
        XCTAssertThrowsError(try VaultCrypto.decrypt(encrypted,key:other))
    }
    func testRandomNonces() throws {
        let salt=try VaultCrypto.random(32),key=try VaultCrypto.random(32),plain=Data("private".utf8)
        XCTAssertNotEqual(try VaultCrypto.encrypt(plain,key:key,salt:salt),try VaultCrypto.encrypt(plain,key:key,salt:salt))
    }
    func testStableWealthIDsMatchAndroidJavaUUID() {
        XCTAssertEqual(WealthOperations.stableID("subscription","test"),"ec0b7364-1678-388a-ab83-2e0192ede0f4")
    }
    func testAndroidEnvelopeFixture() throws {
        let envelope=Data(base64Encoded:"UEFWQVVMVAEACSfAAAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8AAQIDBAUGBwgJCgvEnfSZgbNGobnAvmCRmtsw1OTjBvXQZ0A3AZyGb1mhIg78N/e5QNt+bbGeftkdd/qVCse6fADYEAew/jnZI41y/dsugnnRBN+si0UYqW76Q1cZStysYc6uF+3YoADtOn35ejMxeJgc7yMrQS4vOwADRB3V0EPeWiVSpIGAQ1/9j2/VNCoVDA64LHBtgbHWYuxdklxhN9llLa5v6l4m/t2vLISzEHEQyxBfqOQ0q3teibJXNyD1R+3E")!
        let key=try VaultCrypto.derive(password:"fixture-password-351",salt:VaultCrypto.salt(envelope))
        let d=try JSONDecoder().decode(Document.self,from:VaultCrypto.decrypt(envelope,key:key)).validated()
        XCTAssertEqual(d.records.first?.int("cents"),120000)
        XCTAssertEqual(d.records.first?.text("currency"),"HKD")
        XCTAssertEqual(d.records.first?.text("kind"),"expense")
    }
    func testAAExpenseOnlyCountsOwnShare() throws {
        var d=Document();let a=Item.make(["name":.string("现金"),"currency":.string("CNY"),"openingCents":.int(100000),"openingDate":.int(1)])
        d.accounts=[a]
        let g=Item.make(["name":.string("合租"),"members":.array([.string("我"),.string("朋友")]),"me":.string("我"),"currency":.string("CNY")])
        d.upsertWealth(g,in:"groups")
        let e=Item.make(["groupId":.string(g.id),"title":.string("晚餐"),"payer":.string("我"),"cents":.int(10000),"accountId":.string(a.id),"date":.int(Clock.milliseconds),"shares":.array([.object(["member":.string("我"),"cents":.int(5000)]),.object(["member":.string("朋友"),"cents":.int(5000)])])])
        d=try WealthOperations.addSplit(e,group:g,in:d)
        XCTAssertEqual(Totals(d.records).expense,5000);XCTAssertEqual(Finance.balance(a,in:d),90000)
        XCTAssertEqual(WealthOperations.splitBalances(g,in:d)["我"],5000)
    }
    func testInvestmentCashAndProfitSeparation() throws {
        var d=Document();let account=Item.make(["name":.string("现金"),"currency":.string("CNY"),"openingCents":.int(100000),"openingDate":.int(1)])
        let asset=Item.make(["name":.string("基金"),"currency":.string("CNY"),"kind":.string("fund"),"cents":.int(0)])
        d.accounts=[account];d.upsertWallet(asset,in:"assets");var w=d.wealth;w.set("positions",items:[Item(["assetId":.string(asset.id),"price":.string("10"),"quotedAt":.int(Clock.milliseconds)])]);d.wealth=w
        let t=Item.make(["assetId":.string(asset.id),"side":.string("buy"),"quantity":.string("10"),"grossCents":.int(10000),"feeCents":.int(100),"accountId":.string(account.id),"date":.int(Clock.milliseconds)])
        d=try WealthOperations.trade(t,in:d)
        XCTAssertEqual(Totals(d.records).expense,0);XCTAssertEqual(Finance.balance(account,in:d),89900);XCTAssertEqual(d.wallet.items("assets").first?.int("cents"),10000)
    }
    func testSubscriptionPaymentIdempotence() {
        var d=Document();let a=Item.make(["name":.string("现金"),"currency":.string("CNY")]);d.accounts=[a]
        let s=Item.make(["name":.string("会员"),"accountId":.string(a.id),"cents":.int(1000),"cycle":.string("monthly"),"firstDue":.string(Clock.day()),"active":.bool(true)])
        d.upsertWealth(s,in:"subscriptions");d=WealthOperations.paySubscription(s,in:d)
        XCTAssertEqual(d.records.filter {$0.text("kind")=="expense"}.count,1)
        XCTAssertEqual(d.records.filter {$0.text("kind")=="reminder"}.count,1)
    }
}

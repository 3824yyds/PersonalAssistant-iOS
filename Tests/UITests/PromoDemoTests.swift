import XCTest

/// Records actual input, saves and navigation on a fresh simulator with fictional data.
/// Voice is an explicitly identified UI demonstration, without simulated speech or API calls.
final class PromoDemoTests:XCTestCase {
    private var events:[[String:Any]]=[]
    private var screen:CGRect = .zero
    private func mark(_ name:String,_ extra:[String:Any]=[:]) {
        var event=extra;event["name"]=name;event["epoch"]=Date().timeIntervalSince1970
        events.append(event)
    }
    private func hold(_ seconds:Double=0.65) {Thread.sleep(forTimeInterval:seconds)}
    private func tap(_ element:XCUIElement,_ name:String) {
        XCTAssertTrue(element.waitForExistence(timeout:6))
        let frame=element.frame
        mark(name+".begin",["kind":"tap","x":frame.midX/screen.width,"y":frame.midY/screen.height])
        element.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        mark(name+".end")
    }
    private func type(_ element:XCUIElement,_ value:String,_ name:String) {
        tap(element,name+".focus")
        mark(name+".begin",["kind":"type"])
        element.typeText(value)
        mark(name+".end")
    }
    private func scene(_ name:String) {mark("scene."+name);hold()}
    override func tearDown() {
        if let data=try? JSONSerialization.data(withJSONObject:events,options:[.prettyPrinted,.sortedKeys]) {
            let attachment=XCTAttachment(data:data,uniformTypeIdentifier:"public.json")
            attachment.name="ProductDemoEvents";attachment.lifetime = .keepAlways;add(attachment)
        }
        super.tearDown()
    }
    func testRecordProductWalkthrough() {
        let app=launchProduct(["--promo-capture"])
        screen=app.frame
        scene("notes")
        tap(app.buttons["展开快捷操作"],"notes.quick")
        tap(app.buttons["新建笔记"],"notes.new")
        let title=app.descendants(matching:.any).matching(identifier:"note.title").firstMatch
        type(title,"周末小计划","notes.title")
        type(app.textViews["note.body"],"去公园散步，和朋友吃饭。","notes.body")
        hold(0.5)
        tap(app.buttons["note.done"],"notes.save")
        XCTAssertTrue(app.staticTexts["周末小计划"].waitForExistence(timeout:8))
        mark("notes.saved");hold(1.1);recordScreen(app,"DemoNoteSaved")

        scene("ledger")
        tap(app.buttons["账本"].firstMatch,"ledger.tab")
        tap(app.buttons["展开快捷操作"],"ledger.quick")
        tap(app.buttons["记一笔"],"ledger.new")
        type(app.textFields["0.00"],"28","ledger.amount")
        type(app.textFields["这笔钱用在哪里"],"下午的咖啡","ledger.title")
        tap(app.buttons["保存"],"ledger.save")
        XCTAssertTrue(app.staticTexts["下午的咖啡"].waitForExistence(timeout:8))
        mark("ledger.saved");hold(1.1);recordScreen(app,"DemoExpenseSaved")

        scene("statistics")
        tap(app.buttons["统计"].firstMatch,"statistics.open")
        XCTAssertTrue(app.staticTexts["支出分类"].waitForExistence(timeout:5))
        hold(1.4);recordScreen(app,"DemoExpenseStatistics")
        tap(app.buttons["日历"].firstMatch,"statistics.calendar")
        hold(1.1)

        scene("wallet")
        tap(app.buttons["卡包与资产"],"wallet.open")
        XCTAssertTrue(app.navigationBars["卡包与资产"].waitForExistence(timeout:5))
        hold(0.9)
        tap(app.buttons["查看全部"],"wallet.expand")
        hold(0.8)
        tap(app.buttons["wallet.card.00000000-0000-0000-0000-000000000001"],"wallet.card")
        XCTAssertTrue(app.staticTexts["账户余额"].waitForExistence(timeout:5))
        hold(1.1);recordScreen(app,"DemoWalletDetails")
        tap(app.buttons["完成"].firstMatch,"wallet.close")

        scene("models")
        tap(app.buttons["助理"].firstMatch,"models.assistant")
        tap(app.textViews["chat.input"],"models.input")
        tap(app.buttons["chat.model"],"models.open")
        let flash=app.buttons["chat.model.option.deepseek-flash"]
        let pro=app.buttons["chat.model.option.deepseek-v4-pro"]
        XCTAssertTrue(pro.waitForExistence(timeout:5))
        mark("models.toPro.begin",["kind":"swipe","x":flash.frame.midX/screen.width,"y":flash.frame.midY/screen.height,"toX":pro.frame.midX/screen.width,"toY":pro.frame.midY/screen.height])
        flash.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)).press(forDuration:0.12,thenDragTo:pro.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)))
        mark("models.toPro.end");hold(0.9)
        XCTAssertEqual(pro.value as? String,"已选择")
        mark("models.toFlash.begin",["kind":"swipe","x":pro.frame.midX/screen.width,"y":pro.frame.midY/screen.height,"toX":flash.frame.midX/screen.width,"toY":flash.frame.midY/screen.height])
        pro.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)).press(forDuration:0.12,thenDragTo:flash.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)))
        mark("models.toFlash.end");hold(0.7)
        XCTAssertEqual(flash.value as? String,"已选择")
        tap(app.buttons["chat.model.close"],"models.close")

        scene("chat")
        let input=app.textViews["chat.input"]
        type(input,"你好","chat.greeting")
        tap(app.buttons["发送"],"chat.send")
        XCTAssertTrue(app.buttons["chat.saveNote"].waitForExistence(timeout:12))
        mark("chat.replied");hold(1.1);recordScreen(app,"DemoActualLocalReply")

        scene("voice")
        tap(app.buttons["chat.voiceCall"],"voice.open")
        XCTAssertTrue(app.staticTexts["voice.call.title"].waitForExistence(timeout:6))
        let status=app.staticTexts["voice.call.status"]
        XCTAssertEqual(status.label,"正在听");hold(1.3)
        tap(app.buttons["voice.call.mute"],"voice.mute")
        XCTAssertEqual(status.label,"已静音");hold(0.7)
        tap(app.buttons["voice.call.mute"],"voice.unmute")
        XCTAssertEqual(status.label,"正在听");hold(0.8)
        tap(app.buttons["voice.call.end"],"voice.end")

        scene("privacy")
        tap(app.buttons["个人详情"],"privacy.profile")
        for _ in 0..<4 {if app.buttons["锁定资料库"].isHittable {break};app.swipeUp()}
        mark("privacy.lockVisible")
        tap(app.buttons["锁定资料库"],"privacy.lock")
        XCTAssertTrue(app.buttons["解锁"].waitForExistence(timeout:8))
        mark("privacy.locked");hold(1.8);recordScreen(app,"DemoVaultLocked")
        mark("finished")
    }
}

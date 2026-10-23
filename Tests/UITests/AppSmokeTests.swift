import XCTest
import UIKit

final class AppSmokeTests:XCTestCase {
    func testSharedAIVisualStates() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","--ui-layout-fixture","--ui-motion-fixture"];app.launch()
        if app.buttons["创建资料库"].waitForExistence(timeout:5) {
            app.secureTextFields.element(boundBy:0).tap();app.secureTextFields.element(boundBy:0).typeText("test-password-351")
            app.secureTextFields.element(boundBy:1).tap();app.secureTextFields.element(boundBy:1).typeText("test-password-351");app.buttons["创建资料库"].tap()
        } else {app.secureTextFields.firstMatch.tap();app.secureTextFields.firstMatch.typeText("test-password-351");app.buttons["解锁"].tap()}
        XCTAssertTrue(app.buttons["助理"].firstMatch.waitForExistence(timeout:20));app.buttons["助理"].firstMatch.tap()
        XCTAssertTrue(app.buttons["停止回复"].waitForExistence(timeout:5));attach(app,"AIFlowChat");app.buttons["停止回复"].tap()
        app.buttons["返回"].firstMatch.tap();app.buttons["展开快捷操作"].tap();app.buttons["新建笔记"].tap()
        XCTAssertTrue(app.staticTexts["正在整理笔记"].waitForExistence(timeout:5));attach(app,"AIFlowNote")
        let skeleton=app.descendants(matching:.any).matching(identifier:"note.body.skeleton").firstMatch
        XCTAssertTrue(skeleton.waitForExistence(timeout:5))
        let counted=expectation(for:NSPredicate(format:"label == %@","正在处理，共 3 行"),evaluatedWith:skeleton);wait(for:[counted],timeout:4)
        app.buttons["取消"].tap();XCTAssertFalse(app.staticTexts["正在整理笔记"].exists)
        XCTAssertEqual(app.descendants(matching:.any).matching(identifier:"note.body").firstMatch.value as? String,"想去公园走走。\n和朋友吃顿饭。\n也留一点时间休息。")
        app.buttons["关闭"].tap()
    }
    func testCreateVaultAndNavigateMainScreens() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","--ui-layout-fixture"]
        app.launch()
        attach(app,"UnlockFullScreen")
        if app.buttons["创建资料库"].waitForExistence(timeout:10) {
            let fields=app.secureTextFields
            XCTAssertGreaterThanOrEqual(fields.count,2)
            fields.element(boundBy:0).tap();fields.element(boundBy:0).typeText("test-password-351")
            fields.element(boundBy:1).tap();fields.element(boundBy:1).typeText("test-password-351")
            app.buttons["创建资料库"].tap()
        } else if app.buttons["解锁"].exists {
            app.secureTextFields.firstMatch.tap();app.secureTextFields.firstMatch.typeText("test-password-351");app.buttons["解锁"].tap()
        }
        XCTAssertTrue(app.buttons["展开快捷操作"].waitForExistence(timeout:20))
        attach(app,"Notes")
        app.buttons["账本"].firstMatch.tap();XCTAssertTrue(app.staticTexts["本月结余"].waitForExistence(timeout:5));attach(app,"Ledger")
        let initialPlus=app.buttons["展开快捷操作"].frame
        let initialFooter=luminance(app,point:CGPoint(x:2,y:initialPlus.midY))
        app.buttons["展开快捷操作"].tap();XCTAssertTrue(app.buttons["新建笔记"].exists);XCTAssertTrue(app.buttons["记一笔"].exists);XCTAssertTrue(app.buttons["新建提醒"].exists)
        let plus=app.buttons["收起快捷操作"].frame
        XCTAssertEqual(plus.midY,initialPlus.midY,accuracy:1)
        let dimmedFooter=luminance(app,point:CGPoint(x:2,y:plus.midY))
        XCTAssertLessThan(dimmedFooter,initialFooter-0.08)
        XCTAssertEqual(dimmedFooter,luminance(app,point:CGPoint(x:2,y:app.frame.height*0.5)),accuracy:0.04,"No opaque rectangular footer behind the floating navigation")
        for name in ["新建笔记","记一笔","新建提醒"] {let frame=app.buttons[name].frame;XCTAssertEqual(frame.midX,plus.midX,accuracy:2)}
        attach(app,"QuickActionsAligned")
        app.buttons["新建笔记"].tap();XCTAssertTrue(app.buttons["关闭"].waitForExistence(timeout:5));app.buttons["关闭"].tap()
        app.buttons["展开快捷操作"].tap();app.buttons["记一笔"].tap();XCTAssertTrue(app.navigationBars["记一笔"].waitForExistence(timeout:5));app.buttons["取消"].tap()
        app.buttons["展开快捷操作"].tap();app.buttons["新建提醒"].tap();XCTAssertTrue(app.navigationBars["新建提醒"].waitForExistence(timeout:5));app.buttons["取消"].tap()
        app.buttons["展开快捷操作"].tap()
        app.buttons["收起快捷操作"].tap()
        app.buttons["卡包与资产"].tap();XCTAssertTrue(app.navigationBars["卡包与资产"].waitForExistence(timeout:5));attach(app,"Wallet")
        let cards=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'wallet.card.'"))
        XCTAssertEqual(cards.count,4)
        app.buttons["查看全部"].tap()
        let firstCard=app.buttons["wallet.card.00000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(firstCard.isHittable);firstCard.tap()
        XCTAssertTrue(app.staticTexts["账户余额"].waitForExistence(timeout:5));attach(app,"WalletAttachedDetails")
        firstCard.tap()
        let lastCard=app.buttons["wallet.card.00000000-0000-0000-0000-000000000004"]
        for _ in 0..<5 {if lastCard.isHittable {break};app.swipeUp()}
        XCTAssertTrue(lastCard.isHittable);attach(app,"WalletFourthCard")
        app.buttons["完成"].firstMatch.tap()
        app.buttons["提醒"].firstMatch.tap();attach(app,"Reminders")
        app.buttons["助理"].firstMatch.tap();XCTAssertTrue(app.staticTexts["今天心情怎么样？"].waitForExistence(timeout:5));attach(app,"Assistant")
        XCTAssertTrue(app.buttons["返回"].exists)
        let orb=app.descendants(matching:.any).matching(identifier:"assistant.orb").firstMatch
        XCTAssertTrue(orb.exists);let firstOrb=orb.screenshot().pngRepresentation
        Thread.sleep(forTimeInterval:0.4);XCTAssertNotEqual(firstOrb,orb.screenshot().pngRepresentation)
        XCTAssertEqual(app.buttons.matching(identifier:"chat.mode.chat").count,1);XCTAssertEqual(app.buttons.matching(identifier:"chat.mode.finance").count,1)
        XCTAssertFalse(app.segmentedControls["对话模式"].exists);XCTAssertFalse(app.buttons["展开快捷操作"].exists)
        app.buttons["聊天功能"].tap();XCTAssertTrue(app.buttons["chat.menu.new"].waitForExistence(timeout:5));attach(app,"AssistantPlusMenu");app.buttons["chat.menu.new"].tap()
        let input=app.descendants(matching:.any).matching(identifier:"chat.input").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout:5));XCTAssertTrue(input.isHittable);input.tap();input.typeText("1200")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5));XCTAssertTrue(input.isHittable);XCTAssertTrue(app.buttons["发送"].isHittable)
        XCTAssertLessThanOrEqual(input.frame.maxY,app.keyboards.firstMatch.frame.minY+2)
        attach(app,"AssistantKeyboardVisibleInput")
        app.buttons["聊天功能"].tap();app.buttons["chat.menu.history"].tap();XCTAssertTrue(app.navigationBars["历史对话"].waitForExistence(timeout:5));app.buttons["完成"].firstMatch.tap()
        app.buttons["个人详情"].tap()
        app.buttons.containing(.staticText,identifier:"个人头像").firstMatch.tap()
        XCTAssertTrue(app.buttons["使用小熊头像"].waitForExistence(timeout:5));app.buttons["使用小熊头像"].tap();attach(app,"ProfileAvatarPicker")
        app.navigationBars["个人头像"].buttons.firstMatch.tap()
        app.buttons["外观与图标"].tap()
        app.buttons["appearance.mode"].tap();app.buttons["纯黑深色"].tap()
        let dark=expectation(for:NSPredicate {_,_ in self.luminance(app,point:CGPoint(x:app.frame.midX,y:app.frame.height*0.82))<0.08},evaluatedWith:nil)
        wait(for:[dark],timeout:4);attach(app,"AppearanceDarkImmediate")
        app.buttons["appearance.mode"].tap();app.buttons["浅色"].tap()
        let light=expectation(for:NSPredicate {_,_ in self.luminance(app,point:CGPoint(x:app.frame.midX,y:app.frame.height*0.82))>0.9},evaluatedWith:nil)
        wait(for:[light],timeout:4);attach(app,"AppearanceLightImmediate")
        app.navigationBars["外观与图标"].buttons.firstMatch.tap()
        app.buttons["完成"].firstMatch.tap()
        XCTAssertGreaterThan(luminance(app,point:CGPoint(x:2,y:app.frame.height*0.6)),0.9)
        app.buttons["个人详情"].tap()
        for _ in 0..<4 {if app.buttons["锁定资料库"].isHittable {break};app.swipeUp()}
        app.buttons["锁定资料库"].tap();XCTAssertTrue(app.buttons["Face ID 解锁"].waitForExistence(timeout:5));attach(app,"UnlockFaceIDEntry")
        XCTAssertLessThan(app.buttons["Face ID 解锁"].frame.maxY,app.frame.height*0.82)
        XCTAssertGreaterThan(app.secureTextFields.firstMatch.frame.midY,app.frame.height*0.3)
    }
    func luminance(_ app:XCUIApplication,point:CGPoint)->Double {
        guard let image=UIImage(data:app.screenshot().pngRepresentation)?.cgImage else {XCTFail("Missing screenshot");return -1}
        let x=point.x/app.frame.width*CGFloat(image.width),y=point.y/app.frame.height*CGFloat(image.height)
        guard let pixel=image.cropping(to:CGRect(x:x,y:y,width:1,height:1)) else {XCTFail("Sample outside screen");return -1}
        var bytes=[UInt8](repeating:0,count:4)
        let context=CGContext(data:&bytes,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(pixel,in:CGRect(x:0,y:0,width:1,height:1))
        return (Double(bytes[0])*0.2126+Double(bytes[1])*0.7152+Double(bytes[2])*0.0722)/255
    }
    func attach(_ app:XCUIApplication,_ name:String) {let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)}
}

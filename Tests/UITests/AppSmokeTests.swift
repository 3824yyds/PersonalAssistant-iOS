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
    func testScrolledChromeAndInlineProposals() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","--ui-layout-fixture","--ui-scroll-fixture","--ui-proposal-fixture"];app.launch()
        if app.buttons["创建资料库"].waitForExistence(timeout:5) {
            app.secureTextFields.element(boundBy:0).tap();app.secureTextFields.element(boundBy:0).typeText("test-password-351")
            app.secureTextFields.element(boundBy:1).tap();app.secureTextFields.element(boundBy:1).typeText("test-password-351");app.buttons["创建资料库"].tap()
        } else {app.secureTextFields.firstMatch.tap();app.secureTextFields.firstMatch.typeText("test-password-351");app.buttons["解锁"].tap()}
        XCTAssertTrue(app.buttons["展开快捷操作"].waitForExistence(timeout:20))
        for page in ["笔记","提醒","账本"] {
            app.buttons[page].firstMatch.tap()
            app.swipeUp();app.swipeUp()
            let navigation=app.descendants(matching:.any).matching(identifier:"main.navigation").firstMatch
            let header=app.buttons["卡包与资产"].frame.midY
            let middle=luminance(app,point:CGPoint(x:2,y:app.frame.height*0.5))
            XCTAssertEqual(luminance(app,point:CGPoint(x:2,y:header)),middle,accuracy:0.015,"No rectangular header after scrolling \(page)")
            // Native glass casts a soft shadow outside the capsule; it must not brighten into an opaque strip.
            XCTAssertLessThanOrEqual(luminance(app,point:CGPoint(x:2,y:navigation.frame.midY)),middle+0.01,"No opaque light footer after scrolling \(page)")
            XCTAssertEqual(luminance(app,point:CGPoint(x:2,y:app.frame.height-4)),middle,accuracy:0.015,"Page background continues through the bottom safe area")
            attach(app,page+"ScrolledClearChrome")
        }
        app.buttons["助理"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["今天心情怎么样？"].waitForExistence(timeout:5))
        let back=app.buttons["返回"],model=app.buttons["chat.model"]
        XCTAssertTrue(model.exists);XCTAssertGreaterThan(model.frame.minX-back.frame.maxX,4)
        let orb=app.descendants(matching:.any).matching(identifier:"assistant.orb").firstMatch
        XCTAssertEqual(orb.frame.width,88,accuracy:1);XCTAssertEqual(orb.frame.height,88,accuracy:1)
        XCTAssertEqual(luminance(app,point:CGPoint(x:2,y:back.frame.midY)),luminance(app,point:CGPoint(x:2,y:back.frame.maxY+24)),accuracy:0.015)
        attach(app,"AssistantSeparatedHeaderCloudSphere")
        back.tap();app.buttons["展开快捷操作"].tap();app.buttons["新建笔记"].tap()
        let body=app.descendants(matching:.any).matching(identifier:"note.body").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout:5))
        let original=body.value as? String
        for mode in ["润色","摘要","要点","会议纪要","行动清单"] {
            app.buttons["AI 工具"].tap()
            let tool=app.buttons[mode]
            if !tool.isHittable {app.scrollViews["note.ai.tools"].swipeLeft()}
            tool.tap()
            let adopt=app.buttons["note.proposal.adopt"],cancel=app.buttons["note.proposal.cancel"]
            XCTAssertTrue(adopt.waitForExistence(timeout:5));XCTAssertEqual(app.navigationBars.count,1,"Result stays in the original editor")
            XCTAssertFalse(app.navigationBars["润色预览"].exists);XCTAssertFalse(app.navigationBars["整理预览"].exists)
            attach(app,"Inline"+mode+"Result")
            cancel.tap();XCTAssertEqual(body.value as? String,original)
            app.buttons["AI 工具"].tap()
            if !tool.isHittable {app.scrollViews["note.ai.tools"].swipeLeft()}
            tool.tap();XCTAssertTrue(adopt.waitForExistence(timeout:5));adopt.tap()
            let adopted=body.value as? String
            if mode=="润色" {XCTAssertEqual(adopted,"去公园散步，与朋友聚餐，也给自己留出休息的时间。")}
            else {XCTAssertTrue(adopted?.hasPrefix((original ?? "")+"\n\n")==true);XCTAssertTrue(adopted?.contains("## "+mode)==true)}
            app.buttons["撤销采用"].tap();XCTAssertEqual(body.value as? String,original)
        }
        app.buttons["AI 工具"].tap();app.buttons["润色"].tap()
        XCTAssertTrue(app.buttons["note.proposal.adopt"].waitForExistence(timeout:5))
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.buttons["展开快捷操作"].waitForExistence(timeout:5),"Closing an unadopted proposal returns to the original page")
    }
    func testWebAnswersHaveCompactExpandableSources() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN","--ui-layout-fixture","--ui-search-fixture"];app.launch()
        if app.buttons["创建资料库"].waitForExistence(timeout:5) {
            app.secureTextFields.element(boundBy:0).tap();app.secureTextFields.element(boundBy:0).typeText("test-password-351")
            app.secureTextFields.element(boundBy:1).tap();app.secureTextFields.element(boundBy:1).typeText("test-password-351");app.buttons["创建资料库"].tap()
        } else {app.secureTextFields.firstMatch.tap();app.secureTextFields.firstMatch.typeText("test-password-351");app.buttons["解锁"].tap()}
        XCTAssertTrue(app.buttons["助理"].firstMatch.waitForExistence(timeout:20));app.buttons["助理"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["联网搜索 · 2 个来源"].waitForExistence(timeout:5));attach(app,"WebAnswerCompact")
        app.buttons.containing(.staticText,identifier:"来源 · 2").firstMatch.tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"chat.source.1").firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["api-docs.deepseek.com · 2026-10-17"].exists)
        attach(app,"WebAnswerSourcesExpanded")
        app.buttons["聊天功能"].tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"chat.webSearch").firstMatch.waitForExistence(timeout:5));attach(app,"WebSearchMenu")
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

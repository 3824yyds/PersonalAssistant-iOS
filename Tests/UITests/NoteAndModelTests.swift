import XCTest

final class NoteAndModelTests:XCTestCase {
    func testFullscreenEditorDiscardsExistingChangesAndSavesOnlyOnDone() {
        let app=launchProduct()
        let row=app.buttons["note.row.00000000-0000-0000-0000-000000000100"]
        row.tap()
        let title=app.descendants(matching:.any).matching(identifier:"note.title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout:5))
        let original=title.value as? String
        // A standalone page starts at the status bar, without the sheet's top gap.
        XCTAssertLessThan(app.buttons["note.back"].frame.minY,100)
        XCTAssertFalse(app.buttons["main.navigation"].isHittable)
        title.tap();title.typeText("应该被放弃的标题")
        app.buttons["note.back"].tap()
        XCTAssertTrue(row.waitForExistence(timeout:5));row.tap()
        XCTAssertTrue(title.waitForExistence(timeout:5));XCTAssertEqual(title.value as? String,original)
        XCTAssertFalse(app.staticTexts["找到未保存的笔记草稿"].exists)
        title.tap();title.typeText("单独页面保存检查")
        let edited=title.value as? String
        XCTAssertTrue(edited?.contains("单独页面保存检查") == true)
        app.buttons["note.done"].tap()
        XCTAssertTrue(row.waitForExistence(timeout:8));row.tap()
        XCTAssertTrue(title.waitForExistence(timeout:5));XCTAssertEqual(title.value as? String,edited)
        recordScreen(app,"StandaloneNoteEditor")
    }
    func testQuickNoteBackDiscardsNewNoteAndItsDraft() {
        let app=launchProduct()
        func open() {app.buttons["展开快捷操作"].tap();app.buttons["新建笔记"].tap()}
        open();let title=app.descendants(matching:.any).matching(identifier:"note.title").firstMatch
        fill(title,"不要保存的新笔记")
        // Allow the recovery draft to reach disk before explicitly abandoning it.
        let body=app.textViews["note.body"];body.tap();body.typeText("放弃后不应恢复这段正文")
        recordScreen(app,"NewFullscreenNote")
        app.buttons["note.back"].tap()
        XCTAssertTrue(app.buttons["展开快捷操作"].waitForExistence(timeout:8))
        XCTAssertFalse(app.staticTexts["不要保存的新笔记"].exists)
        open();XCTAssertTrue(title.waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["找到未保存的笔记草稿"].exists)
        XCTAssertTrue(["","标题"].contains(title.value as? String ?? ""))
    }
    func testModelSliderSwipesBothWaysAndPersistsSelection() {
        let app=launchProduct();tapProductTab("助理",in:app)
        let input=app.textViews["chat.input"]
        input.tap();input.typeText("模型切换草稿")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
        let keyboardTop=app.keyboards.firstMatch.frame.minY
        recordScreen(app,"ComposerModelEntry")
        app.buttons["chat.model"].tap()
        let flash=app.buttons["chat.model.option.deepseek-flash"]
        let pro=app.buttons["chat.model.option.deepseek-v4-pro"]
        XCTAssertTrue(flash.waitForExistence(timeout:5))
        XCTAssertEqual(flash.label,"Flash");XCTAssertEqual(pro.label,"Pro")
        XCTAssertEqual(app.popovers.count,0)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertLessThanOrEqual(pro.frame.maxY,keyboardTop+1)
        XCTAssertGreaterThan(flash.frame.minY,app.buttons["返回"].frame.maxY+50)
        flash.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)).press(forDuration:0.1,thenDragTo:pro.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)))
        let selected=NSPredicate(format:"value == '已选择'")
        expectation(for:selected,evaluatedWith:pro);waitForExpectations(timeout:8)
        recordScreen(app,"ModelSliderPro")
        app.buttons["chat.model.close"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertEqual(input.value as? String,"模型切换草稿")
        app.buttons["chat.model"].tap();XCTAssertEqual(pro.value as? String,"已选择")
        pro.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)).press(forDuration:0.1,thenDragTo:flash.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4)))
        expectation(for:selected,evaluatedWith:flash);waitForExpectations(timeout:8)
        recordScreen(app,"ModelSliderFlash")
        app.buttons["chat.model.close"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertEqual(input.value as? String,"模型切换草稿")
    }
}

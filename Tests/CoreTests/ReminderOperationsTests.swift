import XCTest
@testable import AssistantCore

final class ReminderOperationsTests:XCTestCase {
    private func time(_ value:String)->Int64 {Int64(ISO8601DateFormatter().date(from:value)!.timeIntervalSince1970*1000)}
    private func reminder(_ due:String,period:String="monthly",day:Int64?=nil,month:Int64?=nil,zone:String="Asia/Shanghai",lead:Int64=0)->Item {
        var r=Item.make(["kind":.string("reminder"),"title":.string("月底缴费"),"currency":.string("CNY"),"date":.int(1),"due":.int(time(due)),"alertAt":.int(time(due)-lead),"period":.string(period),"zone":.string(zone)])
        if let day {r.set("anchorDay",day)};if let month {r.set("anchorMonth",month)}
        return r
    }
    func testMonthly31stRestoresAfterFebruaryWithoutExistingAnchor()throws {
        var r=reminder("2027-01-31T09:00:00+08:00")
        r=try ReminderOperations.toggleCompletion(r)
        XCTAssertEqual(r.int("due"),time("2027-02-28T09:00:00+08:00"));XCTAssertEqual(r.int("anchorDay"),31)
        r=try ReminderOperations.toggleCompletion(r)
        XCTAssertEqual(r.int("due"),time("2027-03-31T09:00:00+08:00"));XCTAssertEqual(r.raw["completedPeriods"]?.array.count,2)
        r=try ReminderOperations.toggleCompletion(r)
        XCTAssertEqual(r.int("due"),time("2027-04-30T09:00:00+08:00"))
        r=try ReminderOperations.toggleCompletion(r)
        XCTAssertEqual(r.int("due"),time("2027-05-31T09:00:00+08:00"))
    }
    func testAlreadyClampedMonthUsesStoredAnchorAndKeepsLeadTime()throws {
        let lead:Int64=3_600_000
        let r=try ReminderOperations.toggleCompletion(reminder("2027-02-28T09:15:32+08:00",day:31,lead:lead))
        XCTAssertEqual(r.int("due"),time("2027-03-31T09:15:32+08:00"));XCTAssertEqual(r.int("alertAt"),r.int("due")-lead)
    }
    func testYearlyLeapDayReturnsInNextLeapYear()throws {
        var r=reminder("2024-02-29T09:00:00+08:00",period:"yearly")
        for year in 2025...2028 {
            r=try ReminderOperations.toggleCompletion(r)
            XCTAssertEqual(r.int("due"),time("\(year)-02-\(year==2028 ? "29":"28")T09:00:00+08:00"))
            XCTAssertEqual(r.int("anchorDay"),29);XCTAssertEqual(r.int("anchorMonth"),2)
        }
    }
    func testDecemberMonthlyAndYearlyAnchorsCrossYear()throws {
        let monthly=try ReminderOperations.toggleCompletion(reminder("2026-12-31T23:30:00+08:00",day:31))
        XCTAssertEqual(monthly.int("due"),time("2027-01-31T23:30:00+08:00"))
        let yearly=try ReminderOperations.toggleCompletion(reminder("2026-12-31T23:30:00+08:00",period:"yearly",day:31,month:12))
        XCTAssertEqual(yearly.int("due"),time("2027-12-31T23:30:00+08:00"))
    }
    func testDailyAndWeeklyKeepLocalTimeAcrossDaylightSaving()throws {
        let daily=try ReminderOperations.toggleCompletion(reminder("2027-03-13T09:00:00-05:00",period:"daily",zone:"America/New_York"))
        XCTAssertEqual(daily.int("due"),time("2027-03-14T09:00:00-04:00"))
        let weekly=try ReminderOperations.toggleCompletion(reminder("2027-03-07T09:00:00-05:00",period:"weekly",zone:"America/New_York"))
        XCTAssertEqual(weekly.int("due"),time("2027-03-14T09:00:00-04:00"))
    }
    func testOneOffCanReopenWithoutChangingIdentityOrDue()throws {
        let original=reminder("2027-01-31T09:00:00+08:00",period:"none")
        let completed=try ReminderOperations.toggleCompletion(original,now:123)
        XCTAssertTrue(completed.bool("completed"));XCTAssertEqual(completed.int("completedAt"),123)
        let reopened=try ReminderOperations.toggleCompletion(completed)
        XCTAssertFalse(reopened.bool("completed"));XCTAssertNil(reopened.raw["completedAt"])
        XCTAssertEqual(reopened.id,original.id);XCTAssertEqual(reopened.int("due"),original.int("due"));XCTAssertEqual(reopened.text("currency"),"CNY")
    }
    func testRecurringUndoReopensOnlyLatestPeriodAndRecompletionDoesNotDuplicate()throws {
        let original=reminder("2027-01-31T09:00:00+08:00",day:31,lead:600_000)
        let february=try ReminderOperations.toggleCompletion(original)
        let march=try ReminderOperations.toggleCompletion(february)
        let undo=try ReminderOperations.undoLastCompletion(march)
        XCTAssertEqual(undo.int("due"),february.int("due"));XCTAssertEqual(undo.int("alertAt"),february.int("alertAt"))
        XCTAssertEqual(undo.raw["completedPeriods"],february.raw["completedPeriods"])
        XCTAssertEqual(try ReminderOperations.toggleCompletion(undo),march)
        let allUndone=try ReminderOperations.undoLastCompletion(undo)
        XCTAssertEqual(allUndone.int("due"),original.int("due"));XCTAssertFalse(ReminderOperations.canUndoLastCompletion(allUndone))
        XCTAssertThrowsError(try ReminderOperations.undoLastCompletion(allUndone))
    }
    func testLoanGeneratedRemindersCannotBeCompletedOrReopenedHere()throws {
        var r=reminder("2027-01-31T09:00:00+08:00");r.set("loanReminder",true)
        XCTAssertThrowsError(try ReminderOperations.toggleCompletion(r));XCTAssertThrowsError(try ReminderOperations.undoLastCompletion(r))
        XCTAssertFalse(ReminderOperations.canUndoLastCompletion(r))
    }
}

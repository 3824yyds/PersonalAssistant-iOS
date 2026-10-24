import Foundation

/// Ordinary reminders retain their original calendar anchor when a shorter month
/// clamps the visible due date. Loan reminders are managed by the repayment plan.
public enum ReminderOperations {
    public static func calendar(for reminder:Item, fallback:TimeZone = .current)->Calendar {
        var calendar=Calendar(identifier:.gregorian)
        calendar.timeZone=TimeZone(identifier:reminder.text("zone")) ?? fallback
        return calendar
    }

    public static func toggleCompletion(_ reminder:Item,now:Int64 = Clock.milliseconds)throws ->Item {
        try requireOrdinary(reminder)
        var changed=reminder
        if reminder.text("period",fallback:"none")=="none" || reminder.bool("completed") {
            let completed = !reminder.bool("completed")
            changed.set("completed",completed)
            if completed {changed.set("completedAt",now)} else {changed.raw.removeValue(forKey:"completedAt")}
            return changed
        }
        let calendar=calendar(for:reminder)
        let due=Date(timeIntervalSince1970:Double(reminder.int("due"))/1000)
        let day=calendar.component(.day,from:due),month=calendar.component(.month,from:due)
        let anchorDay=(1...31).contains(reminder.int("anchorDay")) ? Int(reminder.int("anchorDay")):day
        let anchorMonth=(1...12).contains(reminder.int("anchorMonth")) ? Int(reminder.int("anchorMonth")):month
        changed.set("anchorDay",Int64(anchorDay));changed.set("anchorMonth",Int64(anchorMonth))
        changed.set("zone",calendar.timeZone.identifier)
        let next:Date?
        switch reminder.text("period") {
        case "daily":next=calendar.date(byAdding:.day,value:1,to:due)
        case "weekly":next=calendar.date(byAdding:.weekOfYear,value:1,to:due)
        case "monthly":
            var components=calendar.dateComponents([.year,.month,.hour,.minute,.second,.nanosecond],from:due)
            // Add to the first day, so January 31 cannot skip February.
            components.day=1
            guard let first=calendar.date(from:components),let target=calendar.date(byAdding:.month,value:1,to:first) else {throw AppError.message("无法计算下一期提醒时间")}
            components=calendar.dateComponents([.year,.month,.hour,.minute,.second,.nanosecond],from:target)
            components.day=min(anchorDay,calendar.range(of:.day,in:.month,for:target)?.count ?? anchorDay)
            next=calendar.date(from:components)
        case "yearly":
            var components=calendar.dateComponents([.year,.hour,.minute,.second,.nanosecond],from:due)
            components.year=(components.year ?? 0)+1;components.month=anchorMonth;components.day=1
            guard let target=calendar.date(from:components) else {throw AppError.message("无法计算下一期提醒时间")}
            components.day=min(anchorDay,calendar.range(of:.day,in:.month,for:target)?.count ?? anchorDay)
            next=calendar.date(from:components)
        default:throw AppError.message("提醒重复周期无效")
        }
        guard let next,next>due else {throw AppError.message("无法计算下一期提醒时间")}
        let nextTime=Int64((next.timeIntervalSince1970*1000).rounded())
        let lead=max(0,reminder.int("due")-reminder.int("alertAt",fallback:reminder.int("due")))
        changed.set("due",nextTime);changed.set("alertAt",max(1,nextTime-lead))
        var periods=reminder.raw["completedPeriods"]?.array ?? []
        periods.append(.int(reminder.int("due")));changed.raw["completedPeriods"] = .array(periods)
        return changed
    }

    public static func canUndoLastCompletion(_ reminder:Item)->Bool {
        !reminder.bool("loanReminder") && reminder.text("period",fallback:"none") != "none" &&
        reminder.raw["completedPeriods"]?.array.last.map({$0.number>0 && $0.number<reminder.int("due")}) == true
    }

    /// Reopens only the last completed occurrence, without duplicating the series.
    public static func undoLastCompletion(_ reminder:Item)throws ->Item {
        try requireOrdinary(reminder)
        guard canUndoLastCompletion(reminder) else {throw AppError.message("没有可撤销的完成记录")}
        var changed=reminder,periods=reminder.raw["completedPeriods"]?.array ?? []
        let prior=periods.removeLast().number
        let lead=max(0,reminder.int("due")-reminder.int("alertAt",fallback:reminder.int("due")))
        changed.set("completed",false);changed.set("due",prior);changed.set("alertAt",max(1,prior-lead))
        changed.raw["completedPeriods"] = .array(periods)
        return changed
    }

    private static func requireOrdinary(_ reminder:Item)throws {
        guard reminder.text("kind")=="reminder",!reminder.bool("loanReminder"),reminder.int("due")>0 else {throw AppError.message("贷款提醒请在还款计划中处理")}
    }
}

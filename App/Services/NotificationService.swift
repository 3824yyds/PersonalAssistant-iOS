import UserNotifications
import Foundation

enum NotificationService {
    static func request() async -> Bool { (try? await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge])) ?? false }
    @MainActor private static var generation=UUID()
    @MainActor static func sync(_ records: [Item]) {
        let token=UUID();generation=token
        let center = UNUserNotificationCenter.current()
        Task {
            let existing=await center.pendingNotificationRequests()
            guard generation==token else {return}
            center.removePendingNotificationRequests(withIdentifiers:existing.filter { $0.identifier.hasPrefix("assistant.") }.map(\.identifier))
            let events=records.filter { $0.text("kind")=="reminder" && !$0.bool("completed") && !$0.bool("paused") }.flatMap { r -> [(Item,Int64,String)] in
                var rows=[(r,r.int("alertAt"),"assistant."+r.id)]
                if r.bool("loanReminder"),r.int("leadAt")<r.int("alertAt") { rows.append((r,r.int("leadAt"),"assistant."+r.id+".lead")) }
                return rows
            }.filter {$0.1>Clock.milliseconds}.sorted {$0.1<$1.1}
            for (r,time,id) in events.prefix(60) {
                let content = UNMutableNotificationContent(); content.title = "个人助理"; content.body = "有一项提醒待处理，请打开应用查看"; content.sound = .default
                if r.bool("loanReminder") {content.body="有一笔贷款需要还款，请打开应用查看"}
                let date = Date(timeIntervalSince1970:Double(time)/1000)
                let components = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute],from:date)
                center.add(UNNotificationRequest(identifier:id,content:content,trigger:UNCalendarNotificationTrigger(dateMatching:components,repeats:false)),withCompletionHandler:nil)
            }
        }
    }
}

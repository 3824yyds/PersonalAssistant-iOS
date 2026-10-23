import UserNotifications
import Foundation

enum NotificationService {
    static func request() async -> Bool { (try? await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge])) ?? false }
    static func sync(_ records: [Item]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { existing in
            center.removePendingNotificationRequests(withIdentifiers:existing.filter { $0.identifier.hasPrefix("assistant.") }.map(\.identifier))
            for r in records.filter({ $0.text("kind") == "reminder" && !$0.bool("completed") && !$0.bool("paused") && $0.int("alertAt") > Clock.milliseconds }).sorted(by:{$0.int("alertAt") < $1.int("alertAt")}).prefix(60) {
                let content = UNMutableNotificationContent(); content.title = "个人助理"; content.body = "有一项提醒待处理，请打开应用查看"; content.sound = .default
                let date = Date(timeIntervalSince1970:Double(r.int("alertAt"))/1000)
                let components = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute],from:date)
                center.add(UNNotificationRequest(identifier:"assistant."+r.id,content:content,trigger:UNCalendarNotificationTrigger(dateMatching:components,repeats:false)))
            }
        }
    }
}

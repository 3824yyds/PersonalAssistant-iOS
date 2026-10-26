import Foundation

enum CompanionClock {
    static func formatted(_ now:Date,timeZone:TimeZone,pattern:String)->String {
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"zh_CN");formatter.calendar=Calendar(identifier:.gregorian);formatter.timeZone=timeZone;formatter.dateFormat=pattern
        return formatter.string(from:now)
    }
    static func context(now:Date=Date(),timeZone:TimeZone = .current)->String {
        "设备当地时间："+formatted(now,timeZone:timeZone,pattern:"yyyy年M月d日 EEEE HH:mm:ss")+"；设备时区："+timeZone.identifier+"。用户问现在几点或今天日期时，按设备当地时间直接回答，不根据聊天里提过的城市猜所在地；只有明确询问其它时区时才换算。"
    }
    static func reply(_ question:String,now:Date=Date(),timeZone:TimeZone = .current)->String? {
        let q=question.trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"？?。！!"))
        if ["现在几点了","现在几点","几点了","现在是什么时间","现在时间","现在的时间","我这里现在几点","你知道现在几点吗"].contains(q) {return "现在是"+formatted(now,timeZone:timeZone,pattern:"M月d日 HH:mm")+"。"}
        if ["今天几号","今天是几号","今天什么日期","今天的日期"].contains(q) {return "今天是"+formatted(now,timeZone:timeZone,pattern:"yyyy年M月d日 EEEE")+"。"}
        if ["今天星期几","今天周几","今天是星期几"].contains(q) {return "今天是"+formatted(now,timeZone:timeZone,pattern:"EEEE")+"。"}
        return nil
    }
}

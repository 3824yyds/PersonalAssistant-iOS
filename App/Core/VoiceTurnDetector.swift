import Foundation

/// Ends a recognized turn after a pause, with a text-stability deadline that ambient noise cannot reset.
public struct VoiceTurnDetector {
    private var signature=""
    private var lastTextChange:TimeInterval?
    private var quietSince:TimeInterval?
    public init() {}
    public mutating func observe(text:String,at time:TimeInterval) {
        let content=String(String.UnicodeScalarView(text.unicodeScalars.filter {CharacterSet.alphanumerics.contains($0)}))
        guard !content.isEmpty,content != signature else{return}
        signature=content;lastTextChange=time
    }
    public mutating func observe(level:Double,at time:TimeInterval) {
        if level.isFinite,level<=0.16 {if quietSince==nil {quietSince=time}}
        else {quietSince=nil}
    }
    public func shouldFinish(at time:TimeInterval)->Bool {
        guard let changed=lastTextChange else{return false}
        let stable=time-changed
        if stable>=2.2 {return true}
        return stable>=0.5 && quietSince.map {time-$0>=1.0} == true
    }
}

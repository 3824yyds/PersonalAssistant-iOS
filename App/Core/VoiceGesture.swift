import Foundation

public enum VoiceReleaseAction:String,Sendable {case send,cancel,text}
public enum VoiceGesture {
    public static func action(horizontal:Double,vertical:Double)->VoiceReleaseAction {
        if vertical < -55 {return horizontal>35 ? .text:.cancel}
        if horizontal < -70 {return .cancel}
        if horizontal > 70 {return .text}
        return .send
    }
}

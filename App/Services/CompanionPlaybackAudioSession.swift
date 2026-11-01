import AVFoundation

/// An idle companion never deactivates audio owned by another screen or app.
@MainActor final class CompanionPlaybackAudioSession {
    private(set) var active=false
    private let activate:()throws->Void
    private let deactivate:()throws->Void
    init(activate:@escaping ()throws->Void = {
        let session=AVAudioSession.sharedInstance()
        try session.setCategory(.playback,mode:.spokenAudio)
        try session.setActive(true)
    },deactivate:@escaping ()throws->Void = {
        try AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }) {self.activate=activate;self.deactivate=deactivate}
    func begin() throws {
        guard !active else {return}
        try activate();active=true
    }
    func end() {
        guard active else {return}
        active=false
        try? deactivate()
    }
}

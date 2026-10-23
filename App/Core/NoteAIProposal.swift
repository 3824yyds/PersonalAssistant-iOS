import Foundation

struct NoteTextVersion:Equatable,Sendable {
    var title:String
    var body:String
}

/// Pending AI output is separate from the saved/draft source until the user adopts it.
struct NoteAIProposal:Equatable,Sendable {
    var mode:String
    var source:NoteTextVersion
    var result:NoteTextVersion
    var evidence:[String]=[]
    var replacesSource:Bool {mode=="润色"}
    var displayed:NoteTextVersion {
        replacesSource ? result:NoteTextVersion(title:source.title,body:source.body+"\n\n"+result.body)
    }
    func adopting(over current:NoteTextVersion)->NoteTextVersion? {
        guard current==source else {return nil}
        return displayed
    }
}

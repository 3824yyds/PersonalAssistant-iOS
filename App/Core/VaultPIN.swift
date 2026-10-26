import Foundation

enum VaultPIN {
    static func valid(_ value:String)->Bool {value.utf8.count==4 && value.utf8.allSatisfy {(48...57).contains($0)}}
}

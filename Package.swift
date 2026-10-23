// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "AssistantCore", platforms: [.macOS(.v13), .iOS(.v17)], products: [.library(name:"AssistantCore",targets:["AssistantCore"])], targets: [.target(name:"AssistantCore",path:"App/Core"), .testTarget(name:"CoreTests",dependencies:["AssistantCore"],path:"Tests/CoreTests")])

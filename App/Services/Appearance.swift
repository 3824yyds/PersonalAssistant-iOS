import SwiftUI
import UIKit

enum AppAppearance:String,CaseIterable {
    case system,light,dark
    var style:UIUserInterfaceStyle {
        switch self {case .system:return .unspecified;case .light:return .light;case .dark:return .dark}
    }
}

/// Apply at the window so a presented sheet and its presenting page change together.
struct AppearanceWindow: UIViewRepresentable {
    var appearance:AppAppearance
    func makeUIView(context:Context)->AppearanceAnchor {AppearanceAnchor()}
    func updateUIView(_ view:AppearanceAnchor,context:Context) {view.style=appearance.style;view.apply()}
}
final class AppearanceAnchor:UIView {
    var style:UIUserInterfaceStyle = .unspecified
    override func didMoveToWindow() {super.didMoveToWindow();apply()}
    func apply() {if window?.overrideUserInterfaceStyle != style {window?.overrideUserInterfaceStyle=style}}
}

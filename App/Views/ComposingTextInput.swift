import SwiftUI
import UIKit

/// Keep UIKit's live IME buffer independent of streaming ObservableObject updates.
struct ComposingTextInput:UIViewRepresentable {
    @Binding var text:String
    @Binding var isFocused:Bool
    var placeholder:String
    var concealed=false
    var accessibilityID="chat.input"
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeUIView(context:Context)->ComposerTextView {
        let view=ComposerTextView(frame:.zero,textContainer:nil);view.delegate=context.coordinator;view.backgroundColor = .clear
        view.font = .systemFont(ofSize:15);view.textColor = .label;view.tintColor=UIColor(Theme.accent)
        view.textContainerInset=UIEdgeInsets(top:11,left:0,bottom:11,right:0);view.textContainer.lineFragmentPadding=0
        view.setContentCompressionResistancePriority(.defaultLow,for:.horizontal);view.accessibilityIdentifier=accessibilityID
        return view
    }
    func updateUIView(_ view:ComposerTextView,context:Context) {
        context.coordinator.parent=self;synchronize(view)
        view.accessibilityIdentifier=accessibilityID
        view.accessibilityLabel=placeholder
        view.textColor=concealed ? .clear:.label;view.tintColor=concealed ? .clear:UIColor(Theme.accent)
        view.placeholder.text=placeholder;view.placeholder.isHidden = concealed || !view.text.isEmpty
        if isFocused != view.isFirstResponder {
            let focused=isFocused
            let coordinator=context.coordinator
            DispatchQueue.main.async {[weak view] in
                guard let view,view.window != nil,coordinator.parent.isFocused==focused else{return}
                if focused {view.becomeFirstResponder()}else{view.resignFirstResponder()}
            }
        }
    }
    func synchronize(_ view:UITextView) {if view.markedTextRange==nil,view.text != text {view.text=text}}
    func sizeThatFits(_ proposal:ProposedViewSize,uiView:ComposerTextView,context:Context)->CGSize? {
        let width=proposal.width ?? 240
        let needed=uiView.sizeThatFits(CGSize(width:width,height:.greatestFiniteMagnitude)).height
        let maximum=(uiView.font?.lineHeight ?? 18)*6+22
        uiView.isScrollEnabled=needed>maximum
        return CGSize(width:width,height:min(maximum,max(42,needed)))
    }
    final class Coordinator:NSObject,UITextViewDelegate {
        var parent:ComposingTextInput
        init(_ parent:ComposingTextInput) {self.parent=parent}
        func textViewDidChange(_ view:UITextView) {
            view.invalidateIntrinsicContentSize()
            (view as? ComposerTextView)?.placeholder.isHidden = !view.text.isEmpty
            guard view.markedTextRange==nil else{return}
            if parent.text != view.text {parent.text=view.text}
        }
        func textViewDidBeginEditing(_ view:UITextView) {parent.isFocused=true}
        func textViewDidEndEditing(_ view:UITextView) {textViewDidChange(view);parent.isFocused=false}
    }
}
final class ComposerTextView:UITextView {
    let placeholder=UILabel()
    override init(frame:CGRect,textContainer:NSTextContainer?) {
        super.init(frame:frame,textContainer:textContainer)
        placeholder.font = .systemFont(ofSize:15);placeholder.textColor = .placeholderText;placeholder.isUserInteractionEnabled=false;placeholder.isAccessibilityElement=false
        addSubview(placeholder);isScrollEnabled=false
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    override func layoutSubviews() {super.layoutSubviews();placeholder.frame=CGRect(x:0,y:11,width:bounds.width,height:20)}
}

import SwiftUI
import UIKit
import PencilKit
import QuickLook

enum NoteFormat:String,CaseIterable {case body="正文",heading="标题",subheading="小标题",bold="粗体",italic="斜体",underline="下划线",strike="删除线",bullet="项目符号",numbered="编号列表",quote="引用",undo="撤销",redo="重做"}
struct NoteFormatCommand:Equatable {var id=UUID();var action:NoteFormat}

struct NoteRichText:UIViewRepresentable {
    @Binding var text:String
    @Binding var richText:String
    var command:NoteFormatCommand?
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeUIView(context:Context)->UITextView {
        let view=UITextView();view.backgroundColor = .clear;view.isScrollEnabled=false;view.font = .preferredFont(forTextStyle:.body);view.adjustsFontForContentSizeCategory=true;view.textContainerInset = .zero;view.textContainer.lineFragmentPadding=0;view.delegate=context.coordinator;view.accessibilityIdentifier="note.body"
        view.setContentCompressionResistancePriority(.defaultLow,for:.horizontal);return view
    }
    func updateUIView(_ view:UITextView,context:Context) {
        context.coordinator.parent=self
        if view.text != text {
            if let bytes=Data(base64Encoded:richText),let value=try? NSAttributedString(data:bytes,options:[.documentType:NSAttributedString.DocumentType.rtf],documentAttributes:nil),value.string==text {view.attributedText=value}
            else {view.attributedText=NSAttributedString(string:text,attributes:[.font:UIFont.preferredFont(forTextStyle:.body),.foregroundColor:UIColor.label])}
            view.textColor = .label
        }
        if let command,context.coordinator.lastCommand != command.id {
            context.coordinator.lastCommand=command.id
            let coordinator=context.coordinator
            DispatchQueue.main.async {[weak view] in if let view,view.window != nil {coordinator.apply(command.action,to:view)}}
        }
    }
    func sizeThatFits(_ proposal:ProposedViewSize,uiView:UITextView,context:Context)->CGSize? {
        let width=proposal.width ?? 320
        return CGSize(width:width,height:max(320,uiView.sizeThatFits(CGSize(width:width,height:.greatestFiniteMagnitude)).height))
    }
    final class Coordinator:NSObject,UITextViewDelegate {
        var parent:NoteRichText
        var lastCommand:UUID?
        init(_ parent:NoteRichText) {self.parent=parent}
        func textViewDidChange(_ view:UITextView) {
            parent.text=view.text
            if let data=try? view.attributedText.data(from:NSRange(location:0,length:view.attributedText.length),documentAttributes:[.documentType:NSAttributedString.DocumentType.rtf]) {parent.richText=data.base64EncodedString()}
        }
        func apply(_ action:NoteFormat,to view:UITextView) {
            if action == .undo {view.undoManager?.undo();textViewDidChange(view);return}
            if action == .redo {view.undoManager?.redo();textViewDidChange(view);return}
            view.becomeFirstResponder()
            if [.bullet,.numbered,.quote].contains(action) {view.insertText(action == .bullet ? "\n• ":action == .numbered ? "\n1. ":"\n› ");return}
            let range=view.selectedRange
            var attributes=view.typingAttributes
            let font=attributes[.font] as? UIFont ?? .preferredFont(forTextStyle:.body)
            switch action {
            case .heading:attributes[.font]=UIFont.preferredFont(forTextStyle:.title2)
            case .subheading:attributes[.font]=UIFont.preferredFont(forTextStyle:.headline)
            case .body:attributes[.font]=UIFont.preferredFont(forTextStyle:.body)
            case .bold,.italic:
                let trait:UIFontDescriptor.SymbolicTraits=action == .bold ? .traitBold:.traitItalic
                var traits=font.fontDescriptor.symbolicTraits
                if traits.contains(trait) {traits.remove(trait)}else{traits.insert(trait)}
                if let descriptor=font.fontDescriptor.withSymbolicTraits(traits) {attributes[.font]=UIFont(descriptor:descriptor,size:font.pointSize)}
            case .underline:attributes[.underlineStyle]=(attributes[.underlineStyle] as? Int ?? 0)==0 ? NSUnderlineStyle.single.rawValue:0
            case .strike:attributes[.strikethroughStyle]=(attributes[.strikethroughStyle] as? Int ?? 0)==0 ? NSUnderlineStyle.single.rawValue:0
            default:break
            }
            if range.length>0 {
                let value=NSMutableAttributedString(attributedString:view.attributedText)
                for key in [NSAttributedString.Key.font,.underlineStyle,.strikethroughStyle] {if let attribute=attributes[key] {value.addAttribute(key,value:attribute,range:range)}}
                view.attributedText=value;view.selectedRange=range;textViewDidChange(view)
            }
            view.typingAttributes=attributes
        }
    }
}

struct NoteTableEditor:View {
    @Environment(\.dismiss) private var dismiss
    let original:Item
    var onSave:(Item)->Void
    @State private var cells:[[String]]=[]
    var body:some View {
        ScrollView([.horizontal,.vertical]) {
            Grid(horizontalSpacing:0,verticalSpacing:0) {
                ForEach(cells.indices,id:\.self) {row in GridRow {ForEach(cells[row].indices,id:\.self) {column in TextField("",text:Binding(get:{cells[row][column]},set:{cells[row][column]=$0}),axis:.vertical).accessibilityIdentifier("note.table.\(row).\(column)").frame(width:130).frame(minHeight:42).padding(8).background(.primary.opacity(0.025)).border(.secondary.opacity(0.25),width:0.5)}}}
            }.padding(20)
        }.navigationTitle("表格").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}}
                ToolbarItem(placement:.confirmationAction) {Button("完成") {var value=original;NoteContent.setCells(cells,in:&value);onSave(value);dismiss()}}
                ToolbarItemGroup(placement:.bottomBar) {
                    Button("加行",systemImage:"plus") {cells.append(Array(repeating:"",count:cells.first?.count ?? 2))}.disabled(cells.count>=20)
                    Button("加列",systemImage:"plus") {for row in cells.indices {cells[row].append("")}}.disabled((cells.first?.count ?? 0)>=10)
                    Menu("删除") {Button("删除末行",role:.destructive) {cells.removeLast()}.disabled(cells.count<=1);Button("删除末列",role:.destructive) {for row in cells.indices {cells[row].removeLast()}}.disabled((cells.first?.count ?? 0)<=1)}
                }
            }.onAppear {cells=NoteContent.cells(original)}
    }
}

struct NoteDrawingEditor:View {
    @Environment(\.dismiss) private var dismiss
    var initial:Data?
    var onSave:(Data,Data)->Void
    @State private var canvas=PKCanvasView()
    var body:some View {
        DrawingCanvas(canvas:canvas,initial:initial).ignoresSafeArea(edges:.bottom).navigationTitle("手绘").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}};ToolbarItem(placement:.confirmationAction) {Button("完成") {
                let drawing=canvas.drawing
                guard !drawing.strokes.isEmpty else {dismiss();return}
                let bounds=drawing.bounds.insetBy(dx:-20,dy:-20)
                let scale=min(2,1600/max(bounds.width,bounds.height))
                let image=drawing.image(from:bounds,scale:scale)
                if let preview=image.pngData() {onSave(drawing.dataRepresentation(),preview)}
                dismiss()
            }}}
    }
}
private struct DrawingCanvas:UIViewRepresentable {
    let canvas:PKCanvasView
    let initial:Data?
    func makeCoordinator()->Coordinator {Coordinator()}
    func makeUIView(context:Context)->PKCanvasView {
        canvas.drawingPolicy = .anyInput;canvas.backgroundColor = .systemBackground
        canvas.accessibilityIdentifier="note.drawing.canvas"
        if let initial,let drawing=try? PKDrawing(data:initial) {canvas.drawing=drawing}
        let picker=PKToolPicker();context.coordinator.picker=picker;picker.addObserver(canvas);picker.setVisible(true,forFirstResponder:canvas)
        DispatchQueue.main.async {canvas.becomeFirstResponder()};return canvas
    }
    func updateUIView(_ uiView:PKCanvasView,context:Context) {}
    final class Coordinator {var picker:PKToolPicker?}
}

struct NoteAttachmentPreview:UIViewControllerRepresentable {
    let attachment:Item
    func makeCoordinator()->Coordinator {Coordinator(attachment)}
    func makeUIViewController(context:Context)->QLPreviewController {let view=QLPreviewController();view.dataSource=context.coordinator;return view}
    func updateUIViewController(_ view:QLPreviewController,context:Context) {}
    static func dismantleUIViewController(_ controller:QLPreviewController,coordinator:Coordinator) {try? FileManager.default.removeItem(at:coordinator.folder)}
    final class Coordinator:NSObject,QLPreviewControllerDataSource {
        let folder:URL
        var file:URL?
        init(_ attachment:Item) {
            folder=FileManager.default.temporaryDirectory.appendingPathComponent("note-preview-"+UUID().uuidString,isDirectory:true)
            super.init()
            do {
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.complete])
                let name=URL(fileURLWithPath:attachment.text("name")).lastPathComponent
                let url=folder.appendingPathComponent(name.isEmpty ? "附件":name)
                let data=Data(base64Encoded:attachment.text("data")) ?? Data()
                try data.write(to:url,options:[.atomic,.completeFileProtection]);file=url
            } catch {file=nil}
        }
        func numberOfPreviewItems(in controller:QLPreviewController)->Int {file==nil ? 0:1}
        func previewController(_ controller:QLPreviewController,previewItemAt index:Int)->QLPreviewItem {file! as NSURL}
    }
}

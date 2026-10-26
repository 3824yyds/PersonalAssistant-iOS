import SwiftUI
import UIKit

struct CompanionCompressionView:View {
    @ObservedObject var session:CompanionSession
    @Environment(\.dismiss) private var dismiss
    @State private var text=""
    @State private var preview:CompanionCompressionPreview?
    @State private var saving=false
    @State private var error:String?
    var body:some View {
        Form {
            Section {
                Text("核对重要事实、时间和你的纠正，再确认带入新窗口。可以直接修改下面的内容。")
                    .font(.footnote).foregroundStyle(.secondary)
                TextEditor(text:$text).frame(minHeight:260).accessibilityIdentifier("companion.compression.text")
            } header:{Text("交接要点")} footer:{Text("\(text.count)/5,000字符。精简会损失部分细节；旧窗口原文保留在历史窗口，名字和长期记忆另行保留。确认前不会切换窗口。")}
            if let error {Section {Text(error).foregroundStyle(.red)}}
        }.navigationTitle("精简预览").navigationBarTitleDisplayMode(.inline)
            .onAppear {if preview==nil {preview=session.compression;text=preview?.text ?? ""}}
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {Button("取消") {session.compression=nil;dismiss()}.disabled(saving)}
                ToolbarItem(placement:.confirmationAction) {Button("确认并新开") {save()}.disabled(saving || session.busy).accessibilityIdentifier("companion.compression.confirm")}
            }.interactiveDismissDisabled(saving)
    }
    private func save() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
        DispatchQueue.main.async {commit()}
    }
    private func commit() {
        guard var next=preview else {error="精简结果已过期，请重新整理";return}
        next.text=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !next.text.isEmpty,next.text.count<=CompanionContext.summaryLimit else {error="请填写1到5,000字符的交接要点";return}
        saving=true
        Task {
            let saved=await session.applyCompression(next);saving=false
            if saved {dismiss()}else{error=session.error ?? "窗口未能保存，原聊天保留，请重试"}
        }
    }
}

struct CompanionWindowHistoryView:View {
    let data:CompanionData
    @Environment(\.dismiss) private var dismiss
    private var windows:[CompanionWindow] {data.windows ?? []}
    private func messages(_ index:Int)->[CompanionMessage] {
        let start=index==0 ? 0:windows[index-1].startIndex
        let end=windows[index].startIndex
        return Array(data.messages[start..<end])
    }
    var body:some View {
        List {
            if windows.isEmpty {Text("精简并开启新窗口后，旧聊天会保存在这里。").foregroundStyle(.secondary)}
            ForEach(Array(windows.indices),id:\.self) {index in
                NavigationLink {
                    List {
                        if index>0 {Section("当时带入的要点") {Text(windows[index-1].summary).textSelection(.enabled)}}
                        ForEach(messages(index)) {message in
                            VStack(alignment:.leading,spacing:5) {
                                Text(message.role=="user" ? "你":"伙伴").font(.caption).foregroundStyle(.secondary)
                                Text(message.content).textSelection(.enabled)
                            }.padding(.vertical,5)
                        }
                    }.navigationTitle("窗口 \(index+1)").navigationBarTitleDisplayMode(.inline)
                } label:{
                    VStack(alignment:.leading,spacing:5) {
                        Text("窗口 \(index+1)")
                        Text(windows[index].date.formatted(date:.abbreviated,time:.shortened)+" · \(messages(index).count)条消息").font(.caption).foregroundStyle(.secondary)
                        if let first=messages(index).first(where:{$0.role=="user"}) {Text(first.content).font(.footnote).lineLimit(2).foregroundStyle(.secondary)}
                    }
                }.accessibilityIdentifier("companion.window.\(index)")
            }
        }.navigationTitle("历史窗口").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.topBarTrailing) {Button("完成") {dismiss()}}}
    }
}

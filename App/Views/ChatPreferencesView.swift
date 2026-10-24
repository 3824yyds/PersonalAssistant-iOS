import SwiftUI

struct ChatPreferencesView:View {
    @EnvironmentObject var store:AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var values=Item()
    @State private var loaded=false
    private func selection(_ key:String)->Binding<String> {Binding(get:{values.text(key,fallback:"default")},set:{values.set(key,$0)})}
    var body:some View {
        Form {
            Section {
                Picker("基本风格和语调",selection:selection("style")) {ForEach(ChatPreferences.styles,id:\.self) {Text(ChatPreferences.styleLabels[$0] ?? $0).tag($0)}}
                level("亲切程度",key:"warmth")
                level("热情程度",key:"enthusiasm")
                level("表情符号",key:"emoji")
                level("可视化回答",key:"visuals")
            } footer:{Text("用于后续聊天回复。可视化回答会按内容使用简洁表格或清单；财务计算与事实依据不受语气偏好影响。")}
        }.appErrorScope().navigationTitle("回复风格").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {Button("取消") {dismiss()}}
                ToolbarItem(placement:.confirmationAction) {
                    Button("保存") {
                        Task {
                            if await store.commit({document in
                                var settings=document.settings
                                settings.raw["chatPreferences"] = .object(values.raw)
                                document.settings=settings
                            }) {dismiss()}
                        }
                    }.disabled(store.busy)
                }
            }
            .onAppear {guard !loaded else{return};loaded=true;values=Item(store.current.settings.raw["chatPreferences"]?.object ?? [:])}
    }
    private func level(_ title:String,key:String)->some View {Picker(title,selection:selection(key)) {ForEach(ChatPreferences.levels,id:\.self) {Text(ChatPreferences.levelLabels[$0] ?? $0).tag($0)}}}
}

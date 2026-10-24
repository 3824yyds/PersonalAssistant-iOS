import SwiftUI

/// Present errors from the frontmost app screen, preserving all forms beneath its alert.
private struct AppErrorScope:ViewModifier {
    @EnvironmentObject var store:AppStore
    @State private var id=UUID()
    func body(content:Content)->some View {
        content
            .onAppear {store.errorScopes.removeAll {$0==id};store.errorScopes.append(id)}
            .onDisappear {store.errorScopes.removeAll {$0==id}}
            .alert("提示",isPresented:Binding(get:{store.error != nil && store.errorScopes.last==id},set:{if !$0 && store.errorScopes.last==id {store.error=nil}})) {
                Button("知道了",role:.cancel) {store.error=nil}
            } message:{Text(store.error ?? "")}
    }
}
extension View {func appErrorScope()->some View {modifier(AppErrorScope())}}

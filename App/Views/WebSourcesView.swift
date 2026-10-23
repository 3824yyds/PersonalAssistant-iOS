import SwiftUI

/// A compact provenance row keeps the answer readable; details are one tap away.
struct WebSourcesView:View {
    var sources:[WebSource]
    @State private var expanded=false
    var body:some View {
        DisclosureGroup(isExpanded:$expanded) {
            VStack(alignment:.leading,spacing:12) {
                ForEach(Array(sources.enumerated()),id:\.element.id) {index,source in
                    if let url=source.link {
                        Link(destination:url) {
                            HStack(alignment:.top,spacing:8) {
                                Text("\(index+1)").font(.system(size:10,weight:.medium)).monospacedDigit()
                                    .frame(width:18,height:18).background(.primary.opacity(0.055),in:Circle())
                                VStack(alignment:.leading,spacing:4) {
                                    Text(source.title).font(.system(size:12,weight:.medium)).lineLimit(2)
                                    Text(source.host+(source.date.map {" · "+String($0.prefix(10))} ?? ""))
                                        .font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
                                }.frame(maxWidth:.infinity,alignment:.leading)
                                Image(systemName:"arrow.up.right").font(.system(size:9)).foregroundStyle(.tertiary)
                            }.contentShape(Rectangle())
                        }.accessibilityIdentifier("chat.source.\(index+1)")
                    }
                }
            }.padding(.top,10)
        } label:{
            Label("来源 · \(sources.count)",systemImage:"globe").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
        }.tint(.secondary).accessibilityIdentifier("chat.sources")
    }
}

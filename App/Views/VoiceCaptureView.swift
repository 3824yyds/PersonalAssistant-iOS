import SwiftUI

private struct VoiceBubbleShape:Shape {
    func path(in rect:CGRect)->Path {
        var path=Path(roundedRect:CGRect(x:0,y:0,width:rect.width,height:rect.height-12),cornerRadius:30)
        path.move(to:CGPoint(x:rect.midX-14,y:rect.maxY-13));path.addLine(to:CGPoint(x:rect.midX,y:rect.maxY));path.addLine(to:CGPoint(x:rect.midX+14,y:rect.maxY-13));path.closeSubpath()
        return path
    }
}

struct SpeechWaveform:View {
    @ObservedObject var meter:SpeechMeter
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/24,paused:reduced)) {timeline in
            Canvas {context,size in
                let time=reduced ? 0:timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<28 {
                    let wave=abs(sin(Double(i)*0.6+time*4))*0.65+0.35
                    let h:CGFloat=5+CGFloat(meter.level*wave)*(size.height-5)
                    let width=size.width/28
                    let rect=CGRect(x:CGFloat(i)*width,y:(size.height-h)/2,width:max(2,width-3),height:h)
                    context.fill(Path(roundedRect:rect,cornerRadius:2),with:.color(.white.opacity(0.95)))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct VoiceCaptureOverlay:View {
    @ObservedObject var speech:SpeechService
    var state:VoiceCaptureState
    var body:some View {
        ZStack {
            Color.black.opacity(0.68).ignoresSafeArea()
            VStack(spacing:20) {
                Spacer(minLength:48)
                Group {
                    if state.finishing {HStack(spacing:12) {AIOrb(active:true).frame(width:32,height:32);Text("正在识别…").foregroundStyle(.white).font(.headline)}}
                    else {SpeechWaveform(meter:speech.meter).frame(width:154,height:40)}
                }.frame(width:244,height:128).appGlass(VoiceBubbleShape(),tinted:true)
                Text(state.finishing ? (state.action == .text ? "识别后核对文字":"识别后发送文字"):state.action == .cancel ? "松开取消":state.action == .text ? "松开转文字":"松开发送文字").font(.headline).foregroundStyle(.white)
                Text(speech.text.isEmpty ? "靠近麦克风，正常说话":speech.text).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(4).frame(maxWidth:300,minHeight:70)
                Spacer()
                HStack(spacing:36) {
                    target("取消","xmark",selected:state.action == .cancel)
                    target("转文字","text.bubble",selected:state.action == .text)
                }.padding(.horizontal,28).opacity(state.finishing ? 0.4:1)
                Text("左滑取消 · 右滑转文字核对").font(.caption).foregroundStyle(.white.opacity(0.65)).padding(.bottom,24)
                RoundedRectangle(cornerRadius:80,style:.continuous).fill(.white.opacity(0.14)).frame(height:125).overlay {Image(systemName:"mic.fill").font(.system(size:30)).foregroundStyle(.white.opacity(0.75))}.padding(.horizontal,-28).padding(.bottom,-46)
            }.padding(.horizontal,20).padding(.bottom,24)
        }.accessibilityHidden(true)
    }
    func target(_ text:String,_ icon:String,selected:Bool)->some View {
        Label(text,systemImage:icon).font(.headline).foregroundStyle(.white).frame(maxWidth:.infinity).padding(.vertical,22).background(selected ? Theme.accent:.white.opacity(0.18),in:Capsule()).scaleEffect(selected ? 1.05:1).animation(Theme.fast,value:selected)
    }
}

import SwiftUI

/// The main window's title-bar control: a white "开始听" pill while idle, an ink pill that breathes,
/// shows the sound level and the time while listening, and counts down when the meeting is about to end.
struct ListenPill: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: SessionStore

    var body: some View {
        Group {
            if model.running, let p = model.ending {
                ending(p)
            } else if model.running {
                listening
            } else {
                idle
            }
        }
        .animation(.spring(duration: 0.35), value: model.running)
        .animation(.spring(duration: 0.35), value: model.ending)
    }

    private var idle: some View {
        Button { model.setRunning(true) } label: {
            HStack(spacing: 9) {
                ZStack {
                    Circle().strokeBorder(Palette.accent, lineWidth: 1.5).frame(width: 18, height: 18)
                    Circle().fill(Palette.accent).frame(width: 8, height: 8)
                }
                Text(model.autoEnded ? L("会议已自动结束") : L("开始听"))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                Text("⌘R").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Palette.line, lineWidth: 1))
            }
            .padding(.leading, 10).padding(.trailing, 14).frame(height: 34)
            .background(Capsule().fill(Color.white).shadow(color: Palette.ink.opacity(0.06), radius: 1, y: 1))
            .overlay(Capsule().stroke(Color(red: 0.85, green: 0.863, blue: 0.882), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("开始听"))
    }

    private var listening: some View {
        HStack(spacing: 11) {
            BreathingDot(size: 8)
            Text("正在听").font(.system(size: 13, weight: .semibold))
            LevelMeter(model: model, bars: 9, height: 16, color: Palette.accent)
            if let start = store.session(store.liveID)?.startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(TranscriptExport.clock(max(0, ctx.date.timeIntervalSince(start))))
                        .font(.system(size: 13).monospacedDigit())
                }
            }
            Text(model.summary).font(.system(size: 12)).foregroundStyle(Color(white: 0.79))
                .lineLimit(1).frame(maxWidth: 240, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Button { model.requestStop() } label: {
                Text("结束").font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).frame(height: 26)
                    .background(Capsule().fill(Color(red: 0.184, green: 0.196, blue: 0.227)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("结束会议"))
        }
        .foregroundStyle(.white)
        .padding(.leading, 16).padding(.trailing, 4).frame(height: 34)
        .background(Capsule().fill(Palette.ink).shadow(color: Palette.ink.opacity(0.2), radius: 8, y: 4))
    }

    private func ending(_ p: MeetingEndWatch.Pending) -> some View {
        HStack(spacing: 11) {
            Text(model.endingTitle(p)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(L("\(max(0, Int(p.deadline.timeIntervalSince(ctx.date).rounded()))) 秒后结束"))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Color(red: 0.957, green: 0.647, blue: 0.549))
            }
            Button { model.keepRecording() } label: {
                Text("继续记录").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 12).frame(height: 26)
                    .background(Capsule().fill(Color.white))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.leading, 16).padding(.trailing, 4).frame(height: 34)
        .background(Capsule().fill(Palette.ink).shadow(color: Palette.ink.opacity(0.2), radius: 8, y: 4))
    }
}

/// An accent dot with a ring that keeps swelling out of it: "live", without blinking.
struct BreathingDot: View {
    var size: CGFloat = 8
    @State private var out = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle().fill(Palette.accent).frame(width: size, height: size)
            .background {
                if !reduceMotion {
                    Circle().fill(Palette.accent)
                        .scaleEffect(out ? 2.6 : 1).opacity(out ? 0 : 0.6)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) { out = true }
            }
            .accessibilityHidden(true)
    }
}

/// Bars that follow the loudness of what Cicada hears, newest on the right.
struct LevelMeter: View {
    @ObservedObject var model: AppModel
    var bars = 9
    var height: CGFloat = 16
    var color: Color = Palette.accent
    @State private var levels: [CGFloat] = []
    private let tick = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<bars, id: \.self) { i in
                let v = i < levels.count ? levels[i] : 0
                Capsule().fill(color).frame(width: 2.5, height: max(3, v * height))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.08), value: levels)
        .onReceive(tick) { _ in
            guard model.running else { return }
            // Map −40…0 dBFS onto the bar height: quiet speech sits low, a loud voice near the top.
            let rms = model.listen.router.takeLevel()
            let db = 20 * log10(max(Double(rms), 1e-6))
            let v = CGFloat(min(1, max(0, (db + 40) / 40)))
            levels = Array((levels + [v]).suffix(bars))
        }
        .accessibilityHidden(true)
    }
}

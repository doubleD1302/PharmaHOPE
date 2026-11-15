import SwiftUI
import SwiftData

/// Nền động theo từng cảnh âm thanh. Chuyển động tính theo thời gian, dừng hẳn khi bật Giảm chuyển động.
struct AmbientBackdrop: View {
    let scene: AmbientScene
    let isPlaying: Bool
    var paused: Bool

    private var colors: [Color] {
        switch scene {
        case .rain: return [Color.healing(0x14283A), Color.healing(0x2C4A5C)]
        case .leaves: return [Color.healing(0x16342A), Color.healing(0x3F6B4B)]
        case .stream: return [Color.healing(0x12363A), Color.healing(0x2E6A68)]
        case .cafe: return [Color.healing(0x2E2018), Color.healing(0x6B4630)]
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    switch scene {
                    case .rain: drawRain(&context, size, t)
                    case .leaves: drawLeaves(&context, size, t)
                    case .stream: drawStream(&context, size, t)
                    case .cafe: drawCafe(&context, size, t)
                    }
                }
                .opacity(isPlaying ? 1 : 0.55)
                .animation(.easeInOut(duration: 1.2), value: isPlaying)
            }
        }
        .animation(.easeInOut(duration: 1.0), value: scene)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func drawRain(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        for i in 0..<70 {
            let h = Double(i)
            let speed = 0.55 + healingHash(h * 2.7) * 0.5
            let p = healingFrac(healingHash(h * 5.1) + t * speed)
            let x = healingHash(h * 1.9) * (size.width + 60) - 30 + p * 18
            let y = p * (size.height + 40) - 20
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - 3, y: y + 16 + healingHash(h * 8.3) * 10))
            context.stroke(path, with: .color(Color.white.opacity(0.10 + 0.22 * healingHash(h * 3.3))), lineWidth: 1.1)
        }
        // Vòng gợn nhỏ ở mặt nước phía dưới.
        for i in 0..<9 {
            let h = Double(i) + 40
            let p = healingFrac(healingHash(h * 4.4) + t * 0.5)
            let x = healingHash(h * 1.3) * size.width
            let y = size.height * (0.80 + 0.16 * healingHash(h * 6.7))
            let w = 8 + p * 46
            let rect = CGRect(x: x - w / 2, y: y - w * 0.18, width: w, height: w * 0.36)
            context.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity((1 - p) * 0.22)), lineWidth: 1)
        }
    }

    private func drawLeaves(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let greens: [UInt32] = [0x8DBB84, 0xA8D8B5, 0x6FA06E, 0xC5DDA0]
        for i in 0..<16 {
            let h = Double(i)
            let speed = 0.025 + healingHash(h * 3.9) * 0.03
            let p = healingFrac(healingHash(h * 6.1) + t * speed)
            let x = healingHash(h * 2.3) * size.width + sin(t * 0.6 + h * 1.9) * 38 + p * 60
            let y = p * (size.height + 60) - 30
            let angle = sin(t * 0.7 + h) * 1.1 + p * 3
            let length = 14 + healingHash(h * 7.7) * 14
            var leaf = Path()
            leaf.addEllipse(in: CGRect(x: -length / 2, y: -length * 0.2, width: length, height: length * 0.4))
            let transform = CGAffineTransform(translationX: x, y: y).rotated(by: angle)
            let alpha = sin(p * .pi) * 0.55
            context.fill(leaf.applying(transform), with: .color(Color.healing(greens[i % greens.count], opacity: alpha)))
        }
    }

    private func drawStream(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        for layer in 0..<6 {
            let l = Double(layer)
            var path = Path()
            let baseY = size.height * (0.45 + 0.09 * l)
            path.move(to: CGPoint(x: 0, y: baseY))
            var x: CGFloat = 0
            while x <= size.width + 8 {
                let y = baseY + sin(Double(x) / 46 + t * (0.5 + l * 0.12) + l * 1.7) * (7 + l * 1.8)
                path.addLine(to: CGPoint(x: x, y: y))
                x += 8
            }
            context.stroke(path, with: .color(Color.white.opacity(0.07 + 0.03 * l)), lineWidth: 1.6)
        }
        for i in 0..<10 {
            let h = Double(i) + 70
            let p = healingFrac(healingHash(h * 3.1) + t * 0.08)
            let x = p * (size.width + 40) - 20
            let y = size.height * (0.5 + 0.4 * healingHash(h * 5.3))
            let r = 1.5 + healingHash(h * 9.1) * 2.5
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(Color.white.opacity(0.16)))
        }
    }

    private func drawCafe(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        for i in 0..<9 {
            let h = Double(i)
            let x = size.width * (0.1 + 0.8 * healingHash(h * 2.9))
            let y = size.height * (0.12 + 0.55 * healingHash(h * 4.7))
            let r = 22 + healingHash(h * 6.3) * 40
            let pulse = 0.5 + 0.5 * sin(t * (0.25 + healingHash(h * 1.7) * 0.3) + h * 2)
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(Color.healing(0xFFC878, opacity: 0.06 + 0.10 * pulse)))
        }
        for i in 0..<7 {
            let h = Double(i) + 20
            let p = healingFrac(healingHash(h * 3.7) + t * 0.07)
            let x = size.width * (0.35 + 0.3 * healingHash(h * 1.1)) + sin(t * 0.8 + h) * 14 * p
            let y = size.height * (0.92 - 0.55 * p)
            let r = 10 + p * 26
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(Color.white.opacity(sin(p * .pi) * 0.07)))
        }
    }
}

@MainActor
struct AmbientSoundView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let engine = AmbientSoundEngine.shared
    @State private var timerMinutes: Int?
    @State private var recorded = false
    private let ink = Color.healing(0xF6F5E9)

    var body: some View {
        ZStack {
            AmbientBackdrop(scene: engine.scene, isPlaying: engine.isPlaying, paused: reduceMotion)
            VStack(spacing: 22) {
                header
                Spacer(minLength: 0)
                playButton
                VStack(spacing: 6) {
                    Text(engine.scene.title).font(.title.weight(.semibold)).foregroundStyle(ink)
                        .id(engine.scene).transition(.opacity)
                    Text(engine.scene.detail).font(.subheadline).foregroundStyle(ink.opacity(0.78))
                        .id(engine.scene.detail).transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.6), value: engine.scene)
                .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                scenePicker
                volumeRow
                timerRow
            }
            .padding(.horizontal, 22).padding(.vertical, 16)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Text("Nghe một khoảng yên").font(.headline).foregroundStyle(ink)
            Spacer()
            Button { dismiss() } label: {
                Text("Xong").font(.subheadline.weight(.medium)).foregroundStyle(ink)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(SoftPressStyle())
        }
    }

    private var playButton: some View {
        Button {
            HealingHaptics.soft()
            if !engine.isPlaying && !recorded {
                recorded = true
                try? HealingStore.recordVisit(.listen, context: context)
            }
            engine.toggle()
        } label: {
            ZStack {
                if engine.isPlaying && !reduceMotion { PulseRings() }
                Circle().fill(Color.white.opacity(0.16)).frame(width: 108, height: 108)
                Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.2).frame(width: 108, height: 108)
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 36, weight: .regular)).foregroundStyle(ink)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 190, height: 190)
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel(engine.isPlaying ? "Tạm dừng âm thanh" : "Phát \(engine.scene.title)")
    }

    private var scenePicker: some View {
        HStack(spacing: 10) {
            ForEach(AmbientScene.allCases) { scene in
                let selected = scene == engine.scene
                Button {
                    HealingHaptics.soft()
                    engine.select(scene)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: scene.symbol).font(.title3)
                        Text(scene.title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 70)
                    .foregroundStyle(ink.opacity(selected ? 1 : 0.7))
                    .background(Color.white.opacity(selected ? 0.20 : 0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(selected ? 0.4 : 0.1)))
                    .animation(.easeInOut(duration: 0.4), value: selected)
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityLabel(scene.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill").foregroundStyle(ink.opacity(0.7))
            Slider(value: Binding(get: { engine.volume }, set: { engine.setVolume($0) }), in: 0...1)
                .tint(Color.healing(0xA8D8B5))
                .accessibilityLabel("Âm lượng")
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(ink.opacity(0.7))
        }
    }

    private var timerRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach([nil, 15, 30, 60] as [Int?], id: \.self) { minutes in
                    let selected = (engine.timerEndsAt != nil ? timerMinutes : nil) == minutes
                    Button {
                        HealingHaptics.soft()
                        timerMinutes = minutes
                        engine.setTimer(minutes: minutes)
                    } label: {
                        Text(minutes.map { "\($0) phút" } ?? "Không hẹn giờ")
                            .font(.footnote.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(ink.opacity(selected ? 1 : 0.7))
                            .background(Color.white.opacity(selected ? 0.20 : 0.08), in: Capsule())
                    }
                    .buttonStyle(SoftPressStyle())
                }
            }
            if let end = engine.timerEndsAt, end > Date() {
                Text("Tự tắt sau ").font(.footnote).foregroundStyle(ink.opacity(0.75))
                + Text(timerInterval: Date()...end, countsDown: true).font(.footnote.monospacedDigit()).foregroundStyle(ink.opacity(0.75))
            } else {
                Text("Âm thanh được tạo ngay trên máy, nghe được cả khi không có mạng.")
                    .font(.footnote).foregroundStyle(ink.opacity(0.6)).multilineTextAlignment(.center)
            }
        }
    }
}

/// Vòng tròn lan chậm quanh nút phát khi đang nghe.
private struct PulseRings: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let p = healingFrac(t / 4.5 + Double(i) / 3)
                    Circle()
                        .strokeBorder(Color.white.opacity((1 - p) * 0.28), lineWidth: 1.2)
                        .frame(width: 108 + p * 84, height: 108 + p * 84)
                }
            }
        }
    }
}

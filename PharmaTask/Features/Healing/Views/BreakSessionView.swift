import SwiftUI
import SwiftData
import UIKit

/// Quả cầu thở. Mọi thứ tính trực tiếp từ thời gian đã trôi qua nên chuyển động liên tục, không bước nhảy.
/// Hiệu ứng: quả cầu phình và thu theo nhịp, đổi màu theo từng pha (hít vào xanh bạc hà, giữ vàng nhạt, thở ra xanh trời),
/// vòng sóng lan ra khi thở ra và thu vào khi hít vào, bụi sáng trôi về phía quả cầu rồi toả ra,
/// vòng tiến độ quanh quả cầu và số giây còn lại của pha.
struct BreathingOrb: View {
    let startDate: Date
    var reduceMotion: Bool

    enum Phase: Equatable { case inhale, hold, exhale }
    struct PhaseState: Equatable {
        let phase: Phase
        let secondsLeft: Int
        let cycle: Double      // tiến độ trong cả vòng 10 giây, 0 đến 1
        let phaseTime: Double  // đã trôi qua bao lâu trong pha hiện tại
    }

    /// 0 = thở ra hết, 1 = hít vào đầy. Hít vào nhẹ nhàng, giữ ngắn, thở ra dài hơn.
    static func breath(at elapsed: Double) -> Double {
        let cycle = HealingContent.breathCycle
        let total = cycle.inhale + cycle.hold + cycle.exhale
        let x = max(elapsed, 0).truncatingRemainder(dividingBy: total)
        if x < cycle.inhale { return healingEase(x / cycle.inhale) }
        if x < cycle.inhale + cycle.hold { return 1 }
        return 1 - healingEase((x - cycle.inhale - cycle.hold) / cycle.exhale)
    }

    static func state(at elapsed: Double) -> PhaseState {
        let cycle = HealingContent.breathCycle
        let total = cycle.inhale + cycle.hold + cycle.exhale
        let x = max(elapsed, 0).truncatingRemainder(dividingBy: total)
        if x < cycle.inhale {
            return PhaseState(phase: .inhale, secondsLeft: Int((cycle.inhale - x).rounded(.up)), cycle: x / total, phaseTime: x)
        }
        if x < cycle.inhale + cycle.hold {
            return PhaseState(phase: .hold, secondsLeft: Int((cycle.inhale + cycle.hold - x).rounded(.up)), cycle: x / total, phaseTime: x - cycle.inhale)
        }
        return PhaseState(phase: .exhale, secondsLeft: Int((total - x).rounded(.up)), cycle: x / total, phaseTime: x - cycle.inhale - cycle.hold)
    }

    typealias RGB = (r: Double, g: Double, b: Double)

    static func rgb(_ phase: Phase) -> RGB {
        switch phase {
        case .inhale: return (0.66, 0.85, 0.71)   // xanh bạc hà
        case .hold: return (0.93, 0.78, 0.60)     // vàng nhạt
        case .exhale: return (0.61, 0.78, 0.88)   // xanh trời
        }
    }

    /// Màu của pha hiện tại, đổi mượt từ màu pha trước trong 0,6 giây đầu.
    static func tint(at elapsed: Double) -> RGB {
        let now = state(at: elapsed)
        let previous = state(at: max(0, elapsed - now.phaseTime - 0.01)).phase
        let from = rgb(previous), to = rgb(now.phase)
        let f = elapsed < 0.6 ? 1 : min(1, now.phaseTime / 0.6)
        return (from.r + (to.r - from.r) * f, from.g + (to.g - from.g) * f, from.b + (to.b - from.b) * f)
    }

    /// Các vòng sóng đang lan: loại (-1 thu vào khi hít vào, 0 nhịp khi giữ, 1 lan ra khi thở ra) và tiến độ 0 đến 1 trong 3 giây.
    static func ripples(at elapsed: Double) -> [(kind: Int, progress: Double)] {
        let cycle = HealingContent.breathCycle
        let total = cycle.inhale + cycle.hold + cycle.exhale
        let starts: [(Double, Int)] = [(0, -1), (cycle.inhale, 0), (cycle.inhale + cycle.hold, 1)]
        let firstCycle = Int(floor(max(0, elapsed - 3) / total))
        let lastCycle = Int(floor(max(0, elapsed) / total))
        var result: [(kind: Int, progress: Double)] = []
        for k in firstCycle...lastCycle {
            for (offset, kind) in starts {
                let start = Double(k) * total + offset
                let age = elapsed - start
                if age >= 0 && age < 3 { result.append((kind: kind, progress: age / 3)) }
            }
        }
        return result
    }

    private static func color(_ value: RGB, opacity: Double = 1) -> Color {
        Color(.sRGB, red: value.r, green: value.g, blue: value.b, opacity: opacity)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let elapsed = reduceMotion ? 0 : timeline.date.timeIntervalSince(startDate)
            let b = reduceMotion ? 0.5 : Self.breath(at: elapsed)
            let state = Self.state(at: elapsed)
            let tint = Self.tint(at: elapsed)
            ZStack {
                if !reduceMotion {
                    Canvas { context, size in draw(&context, size: size, elapsed: elapsed, b: b, state: state, tint: tint) }
                        .frame(width: 400, height: 400)
                }
                orb(b, tint: tint)
                Text("\(state.secondsLeft)")
                    .font(.system(size: 40, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.healing(0x0F3A31).opacity(reduceMotion ? 0 : 0.9))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.25), value: state.secondsLeft)
            }
        }
        .frame(width: 280, height: 280)
        .accessibilityElement()
        .accessibilityLabel("Quả cầu nhịp thở")
        .accessibilityHint("Phình ra khi hít vào, thu lại khi thở ra")
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, elapsed: Double, b: Double, state: PhaseState, tint: RGB) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = 90.0
        let orbRadius = radius * (0.58 + 0.42 * b)
        // Bụi sáng: trôi vào gần quả cầu khi hít vào, toả ra xa khi thở ra.
        for index in 0..<56 {
            let h1 = healingHash(Double(index)), h2 = healingHash(Double(index) + 100)
            let h3 = healingHash(Double(index) + 200), h4 = healingHash(Double(index) + 300)
            let angle = h1 * 2 * .pi + elapsed * (h2 - 0.5) * 0.22
            let distance = (radius * 1.25 + h3 * radius * 0.8) * (1.1 - 0.4 * b)
            let twinkle = max(0, 0.3 + 0.4 * sin(elapsed * 1.6 + h4 * 6.28))
            let sz = 1 + h2 * 2.4
            let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance * 0.9)
            context.fill(Path(ellipseIn: CGRect(x: point.x - sz, y: point.y - sz, width: sz * 2, height: sz * 2)),
                         with: .color(Self.color(tint, opacity: twinkle)))
        }
        // Vòng sóng.
        for ripple in Self.ripples(at: elapsed) {
            let u = ripple.progress
            let ring: (rad: Double, alpha: Double)
            switch ripple.kind {
            case 1: ring = (orbRadius * (1 + 1.3 * u), 0.5 * (1 - u))
            case -1: ring = (orbRadius * (2.4 - 1.3 * u), 0.5 * sin(.pi * u))
            default: ring = (orbRadius * (1 + 0.3 * u), 0.55 * (1 - u))
            }
            let rad = ring.rad, alpha = ring.alpha
            context.stroke(Path(ellipseIn: CGRect(x: center.x - rad, y: center.y - rad, width: rad * 2, height: rad * 2)),
                           with: .color(Self.color(tint, opacity: alpha)), lineWidth: 2)
        }
        // Vòng tiến độ của cả chu kỳ thở.
        let arcRadius = radius * 1.12 + 6
        var arcContext = context
        arcContext.translateBy(x: center.x, y: center.y)
        arcContext.rotate(by: .degrees(-90))
        let circle = Path(ellipseIn: CGRect(x: -arcRadius, y: -arcRadius, width: arcRadius * 2, height: arcRadius * 2))
        arcContext.stroke(circle, with: .color(Color.white.opacity(0.14)), lineWidth: 3)
        arcContext.stroke(circle.trimmedPath(from: 0, to: max(0.001, state.cycle)), with: .color(Self.color(tint, opacity: 0.95)),
                          style: StrokeStyle(lineWidth: 3, lineCap: .round))
        let endAngle = -Double.pi / 2 + 2 * .pi * state.cycle
        let dot = CGPoint(x: center.x + cos(endAngle) * arcRadius, y: center.y + sin(endAngle) * arcRadius)
        context.fill(Path(ellipseIn: CGRect(x: dot.x - 4.5, y: dot.y - 4.5, width: 9, height: 9)), with: .color(.white))
    }

    private func orb(_ b: Double, tint: RGB) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Self.color(tint, opacity: 0.42), .clear],
                                     center: .center, startRadius: 20, endRadius: 150))
                .frame(width: 280, height: 280)
                .scaleEffect(0.78 + 0.24 * b)
            Circle()
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1.2)
                .frame(width: 250, height: 250)
                .scaleEffect(0.74 + 0.30 * b)
            Circle()
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1.5)
                .frame(width: 210, height: 210)
                .scaleEffect(0.66 + 0.28 * b)
            Circle()
                .fill(RadialGradient(colors: [Color.healing(0xEAF7E5, opacity: 0.96),
                                              Self.color(tint, opacity: 0.88),
                                              Self.color((tint.r * 0.45, tint.g * 0.65, tint.b * 0.6), opacity: 0.84)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 4, endRadius: 130))
                .frame(width: 180, height: 180)
                .scaleEffect(0.58 + 0.42 * b)
                .shadow(color: Self.color(tint, opacity: 0.55), radius: 12 + 28 * b)
        }
    }
}

@MainActor
struct BreakSessionView: View {
    let initialMinutes: Int?
    let mood: HopeMood?
    let stage: GardenStage

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase { case choose, running, done }
    @State private var phase: Phase = .choose
    @State private var minutes = 2
    @State private var startDate = Date()
    @State private var breathLabel = "Hít vào"
    @State private var cues = HealingContent.restCues
    @State private var cueIndex = 0
    @State private var soundOn = false
    @State private var startedSound = false
    @State private var doneShown = false
    @State private var tasks: [Task<Void, Never>] = []

    private var endDate: Date { startDate.addingTimeInterval(Double(minutes) * 60) }
    private let ink = Color.healing(0xF6F5E9)

    var body: some View {
        ZStack {
            background
            switch phase {
            case .choose: chooser.transition(.opacity)
            case .running: running.transition(.opacity)
            case .done: finished.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.9), value: phase)
        .preferredColorScheme(.dark)
        .statusBarHidden(phase == .running)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { tearDown() }
        .task {
            if let preset = initialMinutes {
                minutes = preset
                try? await Task.sleep(nanoseconds: 600_000_000)
                if phase == .choose { start() }
            }
            let loaded = await HealingAI.restCues(mood: mood)
            if loaded.count >= 4 { cues = loaded }
        }
    }

    // MARK: - Nền

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color.healing(0x0D2F2A), Color.healing(0x1A5547)], startPoint: .top, endPoint: .bottom)
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    ZStack {
                        blob(Color.healing(0xA8D8B5, opacity: 0.30), size: 320)
                            .offset(x: geo.size.width * 0.25 * sin(t / 9), y: geo.size.height * 0.18 * cos(t / 11) - 120)
                        blob(Color.healing(0xEDC69A, opacity: 0.20), size: 280)
                            .offset(x: geo.size.width * 0.28 * cos(t / 13), y: geo.size.height * 0.22 * sin(t / 10) + 140)
                        blob(Color.healing(0x9CC8E0, opacity: 0.20), size: 300)
                            .offset(x: geo.size.width * 0.22 * sin(t / 15 + 2), y: geo.size.height * 0.2 * cos(t / 12 + 1))
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            StarField(level: 0.55, count: 18, paused: reduceMotion)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle().fill(color).frame(width: size, height: size).blur(radius: 70)
    }

    // MARK: - Chọn thời lượng

    private var chooser: some View {
        VStack(spacing: 28) {
            HStack {
                Spacer()
                closeButton(label: "Đóng")
            }
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Text("Nghỉ một chút").font(.largeTitle.weight(.semibold)).foregroundStyle(ink)
                Text("Chọn một khoảng vừa với lúc này. Bạn có thể dừng bất cứ lúc nào.")
                    .font(.body).foregroundStyle(ink.opacity(0.78)).multilineTextAlignment(.center)
            }
            .softAppear()
            VStack(spacing: 12) {
                ForEach(Array([1, 2, 3].enumerated()), id: \.element) { index, value in
                    Button { minutes = value; start() } label: {
                        HStack {
                            Text("\(value) phút").font(.title3.weight(.semibold))
                            Spacer()
                            Text(value == 1 ? "Một hơi thở sâu" : (value == 2 ? "Dừng lại, thở, rồi quay về" : "Thả lỏng thật sự"))
                                .font(.footnote).opacity(0.8)
                        }
                        .padding(.horizontal, 22).frame(minHeight: 64)
                        .foregroundStyle(ink)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.16)))
                    }
                    .buttonStyle(SoftPressStyle())
                    .softAppear(delay: 0.15 + Double(index) * 0.1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    // MARK: - Đang nghỉ

    private var running: some View {
        VStack(spacing: 0) {
            HStack {
                closeButton(label: "Kết thúc")
                Spacer()
                Button { toggleSound() } label: {
                    Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.body.weight(.medium)).foregroundStyle(ink)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityLabel(soundOn ? "Tắt tiếng mưa nhẹ" : "Bật tiếng mưa nhẹ")
            }
            Spacer(minLength: 12)
            BreathingOrb(startDate: startDate, reduceMotion: reduceMotion)
            Spacer(minLength: 12)
            ZStack {
                Text(breathLabel)
                    .font(.title.weight(.medium)).foregroundStyle(ink)
                    .id(breathLabel).transition(.opacity)
            }
            .frame(height: 44)
            .animation(.easeInOut(duration: 0.8), value: breathLabel)
            ZStack {
                Text(cues.isEmpty ? "" : cues[cueIndex % cues.count])
                    .font(.body).foregroundStyle(ink.opacity(0.82)).multilineTextAlignment(.center)
                    .id(cueIndex).transition(.opacity)
            }
            .frame(minHeight: 64, alignment: .top)
            .padding(.horizontal, 12)
            .animation(.easeInOut(duration: 1.2), value: cueIndex)
            Spacer(minLength: 12)
            VStack(spacing: 8) {
                ProgressView(timerInterval: startDate...endDate, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(Color.healing(0xA8D8B5))
                Text(timerInterval: startDate...endDate, countsDown: true)
                    .font(.footnote.monospacedDigit()).foregroundStyle(ink.opacity(0.7))
                    .accessibilityLabel("Thời gian còn lại")
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private func closeButton(label: String) -> some View {
        Button { finishEarly() } label: {
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(ink)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(Color.white.opacity(0.10), in: Capsule())
        }
        .buttonStyle(SoftPressStyle())
    }

    // MARK: - Xong

    private var finished: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.healing(0xA8D8B5, opacity: 0.45), .clear],
                                         center: .center, startRadius: 4, endRadius: 150))
                    .frame(width: 300, height: 300)
                    .scaleEffect(doneShown ? 1 : 0.6).opacity(doneShown ? 1 : 0)
                Image(stage.imageName).resizable().scaledToFit().frame(width: 190)
                    .scaleEffect(doneShown ? 1 : 0.86, anchor: .bottom).opacity(doneShown ? 1 : 0)
            }
            VStack(spacing: 10) {
                Text("Cảm ơn bạn đã dừng lại.").font(.title.weight(.semibold)).foregroundStyle(ink)
                Text("Khu vườn có thêm một lần bạn ghé nghỉ. Không cần làm gì thêm.")
                    .font(.body).foregroundStyle(ink.opacity(0.8)).multilineTextAlignment(.center)
            }
            .softAppear(delay: 0.5)
            Spacer()
            Button("Về vườn") { dismiss() }
                .buttonStyle(HopePrimaryButtonStyle())
                .softAppear(delay: 0.9)
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 1.4, dampingFraction: 0.82)) { doneShown = true }
        }
    }

    // MARK: - Điều khiển

    private func start() {
        guard phase == .choose else { return }
        startDate = Date()
        breathLabel = "Hít vào"
        cueIndex = 0
        HealingHaptics.soft()
        withAnimation(.easeInOut(duration: 0.9)) { phase = .running }

        let cycle = HealingContent.breathCycle
        let breathTask = Task { @MainActor in
            while !Task.isCancelled {
                breathLabel = "Hít vào"; HealingHaptics.soft()
                try? await Task.sleep(nanoseconds: UInt64(cycle.inhale * 1_000_000_000))
                guard !Task.isCancelled else { return }
                breathLabel = "Giữ nhẹ"
                try? await Task.sleep(nanoseconds: UInt64(cycle.hold * 1_000_000_000))
                guard !Task.isCancelled else { return }
                breathLabel = "Thở ra"; HealingHaptics.soft()
                try? await Task.sleep(nanoseconds: UInt64(cycle.exhale * 1_000_000_000))
            }
        }
        let cueTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 14_000_000_000)
                guard !Task.isCancelled else { return }
                cueIndex += 1
            }
        }
        let total = Double(minutes) * 60
        let finishTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(total * 1_000_000_000))
            guard !Task.isCancelled else { return }
            complete(elapsed: total)
        }
        tasks = [breathTask, cueTask, finishTask]
    }

    private func toggleSound() {
        let engine = AmbientSoundEngine.shared
        if soundOn {
            if startedSound { engine.stop(); startedSound = false }
            soundOn = false
        } else {
            if !engine.isPlaying { engine.setVolume(0.45); engine.play(.rain); startedSound = true }
            soundOn = true
        }
    }

    private func finishEarly() {
        switch phase {
        case .running:
            let elapsed = Date().timeIntervalSince(startDate)
            complete(elapsed: elapsed, early: true)
        default:
            dismiss()
        }
    }

    private func complete(elapsed: Double, early: Bool = false) {
        guard phase == .running else { return }
        cancelTasks()
        let recorded = elapsed >= 20
        if recorded {
            try? HealingStore.recordVisit(.rest, minutes: max(1, Int((elapsed / 60).rounded())), context: context)
        }
        if early && !recorded { dismiss(); return }
        HealingHaptics.settle()
        if startedSound { AmbientSoundEngine.shared.stop(); startedSound = false; soundOn = false }
        withAnimation(.easeInOut(duration: 0.9)) { phase = .done }
    }

    private func cancelTasks() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    private func tearDown() {
        cancelTasks()
        UIApplication.shared.isIdleTimerDisabled = false
        if startedSound { AmbientSoundEngine.shared.stop(); startedSound = false }
    }
}

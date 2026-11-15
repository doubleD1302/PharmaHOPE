import SwiftUI
import SwiftData
import UIKit

/// Quả cầu thở. Kích thước tính trực tiếp từ thời gian đã trôi qua nên chuyển động liên tục, không bước nhảy.
struct BreathingOrb: View {
    let startDate: Date
    var reduceMotion: Bool

    /// 0 = thở ra hết, 1 = hít vào đầy. Hít vào nhẹ nhàng, giữ ngắn, thở ra dài hơn.
    static func breath(at elapsed: Double) -> Double {
        let cycle = HealingContent.breathCycle
        let total = cycle.inhale + cycle.hold + cycle.exhale
        let x = max(elapsed, 0).truncatingRemainder(dividingBy: total)
        if x < cycle.inhale { return healingEase(x / cycle.inhale) }
        if x < cycle.inhale + cycle.hold { return 1 }
        return 1 - healingEase((x - cycle.inhale - cycle.hold) / cycle.exhale)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let b = reduceMotion ? 0.5 : Self.breath(at: timeline.date.timeIntervalSince(startDate))
            orb(b)
        }
        .frame(width: 280, height: 280)
        .accessibilityElement()
        .accessibilityLabel("Quả cầu nhịp thở")
        .accessibilityHint("Phình ra khi hít vào, thu lại khi thở ra")
    }

    private func orb(_ b: Double) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.healing(0xA8D8B5, opacity: 0.42), .clear],
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
                                              Color.healing(0xA8D8B5, opacity: 0.88),
                                              Color.healing(0x4F9C84, opacity: 0.82)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 4, endRadius: 130))
                .frame(width: 180, height: 180)
                .scaleEffect(0.58 + 0.42 * b)
                .shadow(color: Color.healing(0xA8D8B5, opacity: 0.55), radius: 12 + 28 * b)
            Image(systemName: "leaf.fill")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.85))
                .scaleEffect(0.75 + 0.35 * b)
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

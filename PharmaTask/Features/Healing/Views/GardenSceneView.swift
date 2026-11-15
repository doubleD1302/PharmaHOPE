import SwiftUI

/// Khung cảnh khu vườn. Mọi chuyển động đều tính theo thời gian (không dùng vòng lặp animation),
/// nên mượt, dừng được hoàn toàn khi bật Giảm chuyển động và không bị giật khi chuyển tab.
@MainActor
struct GardenSceneView: View {
    let stage: GardenStage
    let mood: HopeMood?
    var isActive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("healing.sceneNight") private var storedNight = false
    @AppStorage("healing.hintSeen") private var hintSeen = false

    private enum CanPhase { case away, hovering, pouring }
    @State private var canPhase: CanPhase = .away
    @State private var wateringStart: Date?
    @State private var sparkleStart: Date?
    @State private var wateringTask: Task<Void, Never>?

    @State private var nightFrom = 0.0
    @State private var nightTo = 0.0
    @State private var nightChanged = Date.distantPast

    @State private var mascotWaving = false
    @State private var mascotLine: HealingNote?
    @State private var mascotTouches = 0
    @State private var mascotTask: Task<Void, Never>?
    @State private var wateredMessage = false

    private var paused: Bool { reduceMotion || !isActive }
    private let plantWidth: CGFloat = 176
    private var plantHeight: CGFloat { plantWidth * 1312 / 1199 }
    private let mascotWidth: CGFloat = 118
    private var mascotHeight: CGFloat { mascotWidth * 1312 / 1199 }
    private let lanternWidth: CGFloat = 92
    private var lanternHeight: CGFloat { lanternWidth * 1312 / 1199 }
    private let canWidth: CGFloat = 132
    private var canHeight: CGFloat { canWidth * 1024 / 1536 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { timeline in
            let date = timeline.date
            let night = nightLevel(at: date)
            GeometryReader { geo in
                sceneContent(size: geo.size, date: date, night: night)
            }
        }
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(HopeTheme.border.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
        .onAppear {
            nightFrom = storedNight ? 1 : 0
            nightTo = nightFrom
            nightChanged = .distantPast
        }
        .onDisappear {
            wateringTask?.cancel(); wateringTask = nil
            mascotTask?.cancel(); mascotTask = nil
            canPhase = .away; wateringStart = nil; sparkleStart = nil; mascotLine = nil; mascotWaving = false
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Bố cục

    private struct SceneLayout {
        let size: CGSize
        var plantCenterX: CGFloat { size.width * 0.52 }
        var plantBottom: CGFloat { size.height - 30 }
    }

    @ViewBuilder
    private func sceneContent(size: CGSize, date: Date, night: Double) -> some View {
        let t = date.timeIntervalSinceReferenceDate
        let layout = SceneLayout(size: size)
        let soilY = layout.plantBottom - plantHeight * 0.36
        let bounce = plantBounce(at: date)
        ZStack {
            backdrop(size: size, t: t)
            lightRays(size: size, t: t, night: night)
            nightTint(night: night)
            StarField(level: night, paused: paused)
                .frame(height: size.height * 0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Group {
                lantern(layout: layout, t: t, night: night)
                mascot(layout: layout, t: t)
                plant(layout: layout, t: t, bounce: bounce)
                wateringCan(layout: layout, soilY: soilY)
            }
            Canvas { context, canvasSize in
                drawAmbient(&context, size: canvasSize, t: t, night: night)
                drawWater(&context, date: date, layout: layout, soilY: soilY)
                drawSparkles(&context, date: date, layout: layout, soilY: soilY)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            speechBubble(layout: layout)
            overlayControls(night: night)
        }
        .frame(width: size.width, height: size.height)
    }

    private func backdrop(size: CGSize, t: Double) -> some View {
        Image("GardenBackdrop")
            .resizable().scaledToFill()
            .frame(width: size.width, height: size.height)
            .scaleEffect(1.07 + 0.015 * sin(t * 0.12))
            .offset(x: 5 * sin(t * 0.09))
            .clipped()
            .accessibilityHidden(true)
    }

    private func lightRays(size: CGSize, t: Double, night: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { k in
                let phase = Double(k)
                Rectangle()
                    .fill(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 70 + phase * 26, height: size.height * 1.3)
                    .rotationEffect(.degrees(-20))
                    .blur(radius: 14)
                    .offset(x: -size.width * 0.25 + phase * size.width * 0.26, y: -40)
                    .opacity((1 - night) * (0.2 + 0.1 * sin(t * 0.4 + phase * 1.7)))
                    .blendMode(.plusLighter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func nightTint(night: Double) -> some View {
        LinearGradient(colors: [Color.healing(0x07142A, opacity: 0.82), Color.healing(0x0F2A2A, opacity: 0.55)],
                       startPoint: .top, endPoint: .bottom)
            .opacity(night)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func lantern(layout: SceneLayout, t: Double, night: Double) -> some View {
        let cx = layout.size.width * 0.84
        let bottom = layout.plantBottom + 4
        let flicker = 0.72 + 0.12 * sin(t * 2.1) + 0.06 * sin(t * 5.3)
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.healing(0xFFD58A, opacity: 0.85), .clear],
                                     center: .center, startRadius: 2, endRadius: 95))
                .frame(width: 190, height: 190)
                .opacity(night * flicker)
                .blendMode(.screen)
                .position(x: cx, y: bottom - lanternHeight * 0.52)
            Image("GardenLantern")
                .resizable().scaledToFit()
                .frame(width: lanternWidth, height: lanternHeight)
                .position(x: cx, y: bottom - lanternHeight / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func mascot(layout: SceneLayout, t: Double) -> some View {
        let cx = layout.size.width * 0.19
        let bottom = layout.plantBottom + 2
        let breath = sin(t * 1.25)
        let wave = mascotWaving ? 2.2 * sin(t * 7) : 0
        return Button(action: greet) {
            ZStack {
                Image("GardenMascot").resizable().scaledToFit().opacity(mascotWaving ? 0 : 1)
                Image("GardenMascotWave").resizable().scaledToFit().opacity(mascotWaving ? 1 : 0)
            }
            .frame(width: mascotWidth, height: mascotHeight)
            .scaleEffect(x: 1 - 0.006 * breath, y: 1 + 0.014 * breath, anchor: .bottom)
            .rotationEffect(.degrees(wave), anchor: .bottom)
        }
        .buttonStyle(.plain)
        .position(x: cx, y: bottom - mascotHeight / 2)
        .accessibilityLabel("Hope")
        .accessibilityHint("Chạm để nghe Hope nói")
    }

    private func plant(layout: SceneLayout, t: Double, bounce: Double) -> some View {
        let sway = 1.6 * sin(t * 0.8) + 0.6 * sin(t * 1.9)
        return Button(action: startWatering) {
            ZStack {
                Image(stage.imageName)
                    .resizable().scaledToFit()
                    .id(stage)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.3), value: stage)
            .frame(width: plantWidth, height: plantHeight)
            .scaleEffect(x: 1 - 0.018 * bounce, y: 1 + 0.035 * bounce, anchor: .bottom)
            .rotationEffect(.degrees(reduceMotion ? 0 : sway), anchor: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: layout.plantCenterX, y: layout.plantBottom - plantHeight / 2)
        .accessibilityLabel("Cây của bạn, giai đoạn \(stage.title)")
        .accessibilityHint("Chạm hai lần để tưới nước")
    }

    private func canCenter(layout: SceneLayout, soilY: CGFloat) -> CGPoint {
        CGPoint(x: layout.plantCenterX + 66, y: soilY - 78)
    }

    private func wateringCan(layout: SceneLayout, soilY: CGFloat) -> some View {
        let center = canCenter(layout: layout, soilY: soilY)
        return Image("GardenWateringCan")
            .resizable().scaledToFit()
            .frame(width: canWidth, height: canHeight)
            .rotationEffect(.degrees(canPhase == .pouring ? -22 : 0))
            .offset(x: canPhase == .away ? 190 : 0, y: canPhase == .away ? -24 : 0)
            .opacity(canPhase == .away ? 0 : 1)
            .position(x: center.x, y: center.y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func speechBubble(layout: SceneLayout) -> some View {
        if let line = mascotLine {
            let x = min(max(layout.size.width * 0.19 + 64, 110), layout.size.width - 110)
            Text(line.text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.healing(0x173C32))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: 210)
                .background(Color.healing(0xFFFBF0, opacity: 0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                .position(x: x, y: layout.plantBottom - mascotHeight - 22)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .accessibilityLabel("Hope nói: \(line.text)")
        }
    }

    private func overlayControls(night: Double) -> some View {
        VStack {
            HStack(alignment: .top) {
                Label(stage.title, systemImage: "leaf.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(night > 0.5 ? Color.white : Color.healing(0x173C32))
                Spacer()
                Button(action: toggleNight) {
                    Image(systemName: storedNight ? "moon.stars.fill" : "sun.max.fill")
                        .font(.body.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .foregroundStyle(night > 0.5 ? Color.white : Color.healing(0x173C32))
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityLabel(storedNight ? "Chuyển sang cảnh ban ngày" : "Chuyển sang cảnh ban đêm")
            }
            Spacer()
            Group {
                if wateredMessage {
                    pill("Cây đã được tưới", systemImage: "drop.fill")
                } else if !hintSeen {
                    pill("Chạm vào cây để tưới nước", systemImage: "hand.tap")
                }
            }
            .transition(.opacity)
        }
        .padding(14)
        .animation(.easeInOut(duration: 0.6), value: wateredMessage)
        .animation(.easeInOut(duration: 0.6), value: hintSeen)
    }

    private func pill(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(Color.healing(0x173C32))
    }

    // MARK: - Thời gian và chuyển động

    private func nightLevel(at date: Date) -> Double {
        if reduceMotion { return nightTo }
        let progress = healingEase(date.timeIntervalSince(nightChanged) / 1.8)
        return nightFrom + (nightTo - nightFrom) * progress
    }

    /// Cây rung nhẹ như thạch sau khi được tưới, tắt dần trong khoảng hai giây.
    private func plantBounce(at date: Date) -> Double {
        guard !reduceMotion, let start = sparkleStart else { return 0 }
        let tau = date.timeIntervalSince(start)
        guard tau >= 0, tau < 2.4 else { return 0 }
        return sin(tau * 9) * exp(-tau * 3.2)
    }

    private func toggleNight() {
        let now = Date()
        let current = nightLevel(at: now)
        storedNight.toggle()
        nightFrom = current
        nightTo = storedNight ? 1 : 0
        nightChanged = now
        HealingHaptics.soft()
    }

    private func greet() {
        mascotTouches += 1
        let touch = mascotTouches
        HealingHaptics.soft()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { mascotWaving = true }
        mascotTask?.cancel()
        mascotTask = Task { @MainActor in
            let line = await HealingAI.mascotLine(stage: stage, mood: mood, variant: touch)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) { mascotLine = line }
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.8)) { mascotLine = nil; mascotWaving = false }
        }
    }

    private func startWatering() {
        guard wateringTask == nil else { return }
        hintSeen = true
        HealingHaptics.soft()
        if reduceMotion {
            wateredMessage = true
            wateringTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                wateredMessage = false
                wateringTask = nil
            }
            return
        }
        wateringTask = Task { @MainActor in
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { canPhase = .hovering }
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.7)) { canPhase = .pouring }
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            wateringStart = Date()
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) { canPhase = .hovering }
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            sparkleStart = Date()
            HealingHaptics.settle()
            withAnimation(.spring(response: 1.0, dampingFraction: 0.85)) { canPhase = .away }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            wateringStart = nil; sparkleStart = nil; wateringTask = nil
        }
    }

    // MARK: - Hạt

    private func drawAmbient(_ context: inout GraphicsContext, size: CGSize, t: Double, night: Double) {
        let day = 1 - night
        if day > 0.02 {
            for i in 0..<20 {
                let h = Double(i)
                let speed = 0.012 + healingHash(h * 3.3) * 0.018
                let progress = healingFrac(healingHash(h * 7.1) + t * speed)
                let x = (healingHash(h * 1.3) + 0.12 * sin(t * 0.35 + h)) * size.width + progress * 30
                let y = size.height * (1 - progress)
                let r = 1.3 + healingHash(h * 5.7) * 2.2
                let alpha = sin(progress * .pi) * 0.55 * day
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color.healing(0xFFF4D6, opacity: alpha)))
            }
        }
        if night > 0.02 {
            for i in 0..<14 {
                let h = Double(i) + 100
                let x = size.width * (0.08 + 0.84 * healingHash(h * 1.9)) + 20 * sin(t * 0.27 + h * 1.3)
                let y = size.height * (0.35 + 0.5 * healingHash(h * 4.1)) + 14 * cos(t * 0.21 + h * 2.1)
                let pulse = 0.5 + 0.5 * sin(t * (0.7 + healingHash(h * 6.1)) + h * 3)
                let glow = pulse * pulse
                let r = 1.8 + healingHash(h * 8.3) * 1.6
                let halo = CGRect(x: x - r * 4, y: y - r * 4, width: r * 8, height: r * 8)
                let core = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: halo), with: .color(Color.healing(0xFFE9A0, opacity: 0.18 * glow * night)))
                context.fill(Path(ellipseIn: core), with: .color(Color.healing(0xFFF3C2, opacity: 0.9 * glow * night)))
            }
        }
    }

    private func drawWater(_ context: inout GraphicsContext, date: Date, layout: SceneLayout, soilY: CGFloat) {
        guard let start = wateringStart else { return }
        let elapsed = date.timeIntervalSince(start)
        let center = canCenter(layout: layout, soilY: soilY)
        // Miệng vòi ở bên trái, phía trên của bình khi đã nghiêng.
        let spout = CGPoint(x: center.x - 59, y: center.y + 13)
        for i in 0..<22 {
            let index = Double(i)
            let tau = elapsed - index * 0.065
            guard tau > 0, tau < 0.62 else { continue }
            let x = spout.x - 4 * healingHash(index * 2.3) - 10 * tau - 6 * healingHash(index * 9.1)
            let y = spout.y + 40 * tau + 260 * tau * tau
            guard y < soilY + 4 else { continue }
            let alpha = min(1, tau * 8) * 0.9
            let rect = CGRect(x: x - 1.6, y: y - 5, width: 3.2, height: 9)
            context.fill(Path(roundedRect: rect, cornerRadius: 1.6), with: .color(Color.healing(0xD6EEFF, opacity: alpha)))
        }
    }

    private func drawSparkles(_ context: inout GraphicsContext, date: Date, layout: SceneLayout, soilY: CGFloat) {
        guard let start = sparkleStart else { return }
        let elapsed = date.timeIntervalSince(start)
        for j in 0..<9 {
            let h = Double(j)
            let p = (elapsed - h * 0.09) / 1.7
            guard p > 0, p < 1 else { continue }
            let x = layout.plantCenterX + (healingHash(h * 3.7) - 0.5) * 90 + sin(p * 6 + h) * 8
            let y = soilY - p * 110 - healingHash(h * 5.9) * 20
            let alpha = sin(p * .pi) * 0.9
            let r = 2.0 + healingHash(h * 8.1) * 2.4
            let halo = CGRect(x: x - r * 2.6, y: y - r * 2.6, width: r * 5.2, height: r * 5.2)
            let core = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: halo), with: .color(Color.healing(0xCFF5D8, opacity: alpha * 0.28)))
            context.fill(Path(ellipseIn: core), with: .color(Color.healing(0xFFFFFF, opacity: alpha)))
        }
    }
}

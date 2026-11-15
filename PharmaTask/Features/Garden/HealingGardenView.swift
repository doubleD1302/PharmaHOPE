import SwiftUI
import SpriteKit

@MainActor
struct HealingGardenView: View {
    var isActive = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var scene = GardenCreatureScene(size: CGSize(width: 360, height: 320))
    @AppStorage("hope.garden.companion") private var companionID = "046"
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var quoteIndex = 0
    @State private var greeting = "Chạm vào một người bạn để chào."
    @State private var loading = true
    @State private var loadFailed = false
    @State private var stageVisible = false
    @State private var stageFrame = CGRect.zero
    @State private var viewportFrame = CGRect.zero
    @State private var resting = false
#if DEBUG
    @State private var showPerformance = false
#endif

    private let quotes = [
        "Bạn có thể chậm lại một chút. Khu vườn vẫn ở đây.",
        "Một khoảng nghỉ nhỏ cũng là cách chăm sóc bản thân.",
        "Hôm nay, bạn không cần làm mọi thứ cùng một lúc.",
        "Hãy cho mình một nhịp thở thật nhẹ.",
        "Mỗi ngày đều có chỗ cho một điều dịu dàng."
    ]
    private var companion: GardenCreature {
        GardenCreature.animals.first(where: { $0.id == companionID }) ?? GardenCreature.animals[0]
    }
    private var running: Bool { isActive && stageVisible && scenePhase == .active }
    private var frameRate: Int { reduceMotion || voiceOver ? 1 : (lowPower ? 30 : 60) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Một góc bình yên cho bạn.")
                        .font(.title2.weight(.semibold)).foregroundStyle(HopeTheme.ink)
                    stage
                    Text(greeting).font(.subheadline).foregroundStyle(HopeTheme.secondary)
                        .accessibilityAddTraits(.updatesFrequently)
                    HStack {
                        Button("Chào Hope") { scene.greet(id: GardenCreature.mascot.id) }
                        Spacer()
                        Button("Chào \(companion.name)") { scene.greet(id: companion.id) }
                    }
                    .buttonStyle(.bordered).disabled(loading || loadFailed)
                    Toggle("Nghỉ ngơi", isOn: $resting)
#if DEBUG
                    Toggle("Hiện FPS và số node", isOn: $showPerformance)
#endif
                    Text("Bạn ghé thăm").font(.headline).foregroundStyle(HopeTheme.ink)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 10) {
                        ForEach(GardenCreature.animals) { animal in
                            Button { companionID = animal.id } label: {
                                HStack {
                                    Text(animal.name).frame(maxWidth: .infinity, alignment: .leading)
                                    if companion.id == animal.id { Image(systemName: "checkmark") }
                                }
                                .font(.subheadline).padding(12).frame(minHeight: 44)
                                .background(companion.id == animal.id ? HopeTheme.surfaceMuted : HopeTheme.surface,
                                            in: RoundedRectangle(cornerRadius: 14))
                            }
                            .accessibilityAddTraits(companion.id == animal.id ? .isSelected : [])
                        }
                    }
                }
                .padding(20)
            }
            .background(GeometryReader { geometry in
                Color.clear.preference(key: GardenViewportFrameKey.self,
                                       value: geometry.frame(in: .global))
            })
            .onPreferenceChange(GardenViewportFrameKey.self) { frame in
                viewportFrame = frame
                updateVisibility()
            }
            .onPreferenceChange(GardenStageFrameKey.self) { frame in
                stageFrame = frame
                updateVisibility()
            }
            .background(HopeTheme.background)
            .navigationTitle("Hope")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                Button(action: nextQuote) {
                    Text(quotes[quoteIndex]).font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
                .foregroundStyle(HopeTheme.ink).background(HopeTheme.surfaceMuted)
                .accessibilityHint("Chạm hai lần để đọc lời nhắn khác")
            }
        }
        .task(id: companion.id) { await loadCompanion() }
        .onChange(of: running) { _, _ in updatePlayback() }
        .onChange(of: reduceMotion) { _, _ in updatePlayback() }
        .onChange(of: voiceOver) { _, _ in updatePlayback() }
        .onChange(of: resting) { _, value in scene.resting = value }
        .onChange(of: isActive) { _, active in if active { nextQuote() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onDisappear { scene.configure(reduced: reduceMotion || voiceOver, paused: true) }
    }

    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(LinearGradient(colors: [HopeTheme.surfaceMuted, HopeTheme.mint.opacity(0.4)],
                                     startPoint: .top, endPoint: .bottom))
            SpriteView(scene: scene, isPaused: !running || reduceMotion || voiceOver,
                       preferredFramesPerSecond: frameRate, options: [.allowsTransparency],
                       debugOptions: performanceOptions)
                .accessibilityHidden(true)
                .opacity(loading || loadFailed ? 0 : 1)
                .allowsHitTesting(!loading && !loadFailed)
            if loading { ProgressView("Đang đón bạn ghé thăm…") }
            if loadFailed {
                VStack(spacing: 12) {
                    Text("Chưa tải được hình người bạn này.")
                    Button("Thử lại") { Task { await loadCompanion() } }
                }.padding()
            }
        }
        .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 28))
        .background(GeometryReader { geometry in
            Color.clear.preference(key: GardenStageFrameKey.self,
                                   value: geometry.frame(in: .global))
        })
        .onAppear { updateVisibility() }
        .onDisappear { stageVisible = false; updatePlayback() }
    }

    private func nextQuote() { quoteIndex = (quoteIndex + 1) % quotes.count }

    private var performanceOptions: SpriteView.DebugOptions {
#if DEBUG
        showPerformance ? [.showsFPS, .showsNodeCount, .showsDrawCount] : []
#else
        []
#endif
    }

    private func updateVisibility() {
        stageVisible = !stageFrame.isEmpty && !viewportFrame.isEmpty && stageFrame.intersects(viewportFrame)
    }

    private func updatePlayback() {
        scene.configure(reduced: reduceMotion || voiceOver,
                        paused: !running || reduceMotion || voiceOver)
    }

    private func loadCompanion() async {
        let selected = companion
        loading = true
        loadFailed = false
        guard !Task.isCancelled, selected.id == companion.id else { return }
        scene.install(selected)
        scene.resting = resting
        scene.onGreeting = { name in greeting = "\(name) đang ở đây cùng bạn." }
        loadFailed = scene.unavailable
        loading = false
        greeting = "Chạm vào một người bạn để chào."
        updatePlayback()
    }
}

private struct GardenStageFrameKey: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct GardenViewportFrameKey: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

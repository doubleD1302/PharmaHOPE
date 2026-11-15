import SwiftUI
import SwiftData
import SpriteKit

private struct PagerRestRoute: Identifiable { let id = UUID(); let minutes: Int }

private enum PagerSheet: Identifiable {
    case journalNew(String)
    case journalList
    case journalEntry(JournalEntry)
    case closeDay
    case settings

    var id: String {
        switch self {
        case .journalNew(let prompt): return "new-\(prompt)"
        case .journalList: return "list"
        case .journalEntry(let entry): return "entry-\(entry.id)"
        case .closeDay: return "close"
        case .settings: return "settings"
        }
    }
}

/// Tab Hope: một cảnh toàn màn hình, vuốt ngang giữa các trang (vườn, cảm xúc, nghỉ và nghe, viết, trò chuyện).
/// Không trang nào cuộn dọc khi đủ chỗ; chỉ khi màn hình quá thấp thì trang mới cuộn để không mất nội dung.
@MainActor
struct HopePagerView: View {
    var isActive = true
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Query(sort: \HealingVisit.createdAt, order: .reverse) private var visits: [HealingVisit]
    @Query(sort: \MoodCheckIn.createdAt, order: .reverse) private var moods: [MoodCheckIn]
    @Query(sort: \JournalEntry.updatedAt, order: .reverse) private var entries: [JournalEntry]
    @AppStorage("hope.garden.companion") private var companionID = "046"
    @AppStorage(HealingHaptics.preferenceKey) private var hapticsOn = true

    @State private var page = 0
    @State private var scene = GardenCreatureScene(size: CGSize(width: 360, height: 420))
    @State private var loading = true
    @State private var loadFailed = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var quote = HopeQuotes.quote(variant: 0)
    @State private var quoteVariant = 0
    @State private var chatOpen = false
    @AppStorage("hope.plant.x") private var plantX = -1.0          // tâm chậu theo tỉ lệ bề ngang sân khấu; âm = vị trí mặc định
    @AppStorage("hope.plant.bottom") private var plantBottom = -1.0 // mép dưới chậu theo tỉ lệ bề cao sân khấu tính từ trên xuống
    @AppStorage("hope.water.log") private var waterLogRaw = ""
    @AppStorage("hope.plant.hintSeen") private var plantHintSeen = false
    @State private var plantDrag: CGSize?
    @State private var canPouring = false
    @State private var pourStart: Date?
    @State private var pourTask: Task<Void, Never>?
    @State private var plantNote: String?
    @State private var plantNoteTask: Task<Void, Never>?
    @State private var bounceStart: Date?
    @State private var screenSize = CGSize.zero
    @State private var stageFrame = CGRect.zero
    @State private var night = HopePagerView.isNightNow()
    @State private var selectedMood: HopeMood?
    @State private var dailyNote: HealingNote?
    @State private var letter: String?
    @State private var restMinutes = 2
    @State private var restRoute: PagerRestRoute?
    @State private var sheet: PagerSheet?
    @State private var chatCompanionID = "Mascot"
    @State private var recordedListen = false
    @State private var errorMessage: String?
    private let sound = AmbientSoundEngine.shared

    private var companion: GardenCreature { GardenCreature.animals.first(where: { $0.id == companionID }) ?? GardenCreature.animals[0] }
    private var restDays: Int { GardenGrowth.restDays(visits) }
    private var stage: GardenStage { GardenStage.stage(forDays: restDays) }
    private var todayMood: HopeMood? { moods.first(where: { Calendar.current.isDateInToday($0.createdAt) })?.mood }
    private var contextMood: HopeMood? { selectedMood ?? todayMood }
    private var running: Bool { isActive && page == 0 && scenePhase == .active }
    private var frameRate: Int { reduceMotion || voiceOver ? 1 : (lowPower ? 30 : 60) }
    private let pageTitles = ["Vườn", "Cảm xúc", "Nghỉ và nghe", "Viết"]
    private let pourDuration = 3.4

    /// Khoá cho bộ đếm 30 giây của câu trích: đổi câu (tay hoặc tự động) hay tạm dừng thì đếm lại từ đầu.
    private struct QuoteTimerKey: Equatable { let active: Bool; let variant: Int }
    private var chatCompanion: HopeCompanion { CompanionCatalog.companion(id: chatCompanionID) }

    static func isNightNow(_ date: Date = .now, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 19 || hour < 5
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $page) {
                gardenPage.tag(0)
                moodPage.tag(1)
                restPage.tag(2)
                writePage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            pageDots
        }
        .background { backdrop }
        .scrollIndicators(.hidden)   // ẩn thanh cuộn ở mọi màn của tab Hope (cả màn mở lên từ đây), vẫn cuộn được
        .fullScreenCover(item: $restRoute) { route in
            BreakSessionView(initialMinutes: route.minutes, mood: contextMood, stage: stage)
        }
        .sheet(item: $sheet) { route in
            sheetContent(route).presentationDragIndicator(.visible)
        }
        .alert("Hope", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Đóng", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .task(id: companionID) { await loadCompanion() }
        .task { await loadLetter() }
        .onChange(of: running) { _, _ in updatePlayback() }
        .onChange(of: reduceMotion) { _, _ in updatePlayback() }
        .onChange(of: voiceOver) { _, _ in updatePlayback() }
        .onChange(of: page) { _, newPage in
            HealingHaptics.soft()
            if newPage != 0 { closeChat() }
        }
        // Câu trích tự đổi sau mỗi 30 giây khi đang xem trang Vườn (chạm vào thẻ để đổi ngay và đếm lại).
        .task(id: QuoteTimerKey(active: running && !voiceOver, variant: quoteVariant)) {
            guard running, !voiceOver else { return }
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            nextQuote(automatic: true)
        }
        .task(id: isActive) { await showPlantHintOnce() }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onDisappear {
            scene.configure(reduced: reduceMotion || voiceOver, paused: true)
            pourTask?.cancel(); pourTask = nil; pourStart = nil; canPouring = false
        }
    }

    // MARK: - Nền, thanh trên, chấm trang

    private var backdrop: some View {
        ZStack {
            Image("GardenBackdrop").resizable().scaledToFill()
            Color.healing(0x07142A).opacity(night ? 0.5 : 0)
        }
        .ignoresSafeArea()
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { screenSize = geometry.size; pushPath() }
                .onChange(of: geometry.size) { _, size in screenSize = size; pushPath() }
        })
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: night)
        .accessibilityHidden(true)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                HopeBrandMark(size: 28)
                Text("Hope").font(.headline).foregroundStyle(HopeTheme.ink)
            }
            .padding(.horizontal, 12).frame(minHeight: 40)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            HopeBellButton(glass: true)
            roundButton(night ? "sun.max" : "moon.stars", label: night ? "Chuyển sang ban ngày" : "Chuyển sang ban đêm") { night.toggle() }
            roundButton("slider.horizontal.3", label: "Cài đặt") { sheet = .settings }
        }
        .padding(.horizontal, HopeTheme.pageInset).padding(.top, 6).padding(.bottom, 8)
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.medium)).frame(width: 40, height: 40)
                .foregroundStyle(HopeTheme.ink).background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(SoftPressStyle()).accessibilityLabel(label)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(pageTitles.indices, id: \.self) { index in
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { page = index } } label: {
                    Capsule().fill(index == page ? HopeTheme.accent : HopeTheme.ink.opacity(0.28))
                        .frame(width: index == page ? 24 : 9, height: 9)
                        .frame(minWidth: 24, minHeight: 32)
                }
                .accessibilityLabel(pageTitles[index])
                .accessibilityAddTraits(index == page ? .isSelected : [])
            }
            Text(pageTitles[page]).font(.caption).foregroundStyle(HopeTheme.ink)
                .padding(.horizontal, 10).frame(minHeight: 28).background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
    }

    private func glass<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func pageScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 12) { content() }
                .padding(.horizontal, HopeTheme.pageInset).padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize).scrollIndicators(.hidden)
    }

    // MARK: - Trang 1: vườn

    private var gardenPage: some View {
        VStack(spacing: 10) {
            Button { nextQuote(automatic: false) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(quote.text).font(.system(.callout, design: .serif).italic()).foregroundStyle(HopeTheme.ink)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text("— \(quote.author)").font(.caption).foregroundStyle(HopeTheme.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(SoftPressStyle())
            .accessibilityLabel("\(quote.text), \(quote.author)")
            .accessibilityHint("Chạm hai lần để đọc câu khác")

            companionPicker

            ZStack(alignment: .top) {
                SpriteView(scene: scene, isPaused: !running || reduceMotion || voiceOver,
                           preferredFramesPerSecond: frameRate, options: [.allowsTransparency])
                    .background(GeometryReader { geometry in
                        // x trong trang (không đổi khi vuốt), y theo toàn màn hình: lối mòn không dịch chuyển lúc đang vuốt trang.
                        Color.clear
                            .onAppear { measureStage(geometry) }
                            .onChange(of: geometry.size) { _, _ in measureStage(geometry) }
                    })
                    .accessibilityHidden(true)
                    .opacity(loading || loadFailed ? 0 : 1)
                    .allowsHitTesting(!loading && !loadFailed)
                if loading { ProgressView("Đang đón bạn ghé thăm…").padding(.top, 60) }
                if loadFailed {
                    VStack(spacing: 10) {
                        Text("Chưa tải được hình người bạn này.")
                        Button("Thử lại") { Task { await loadCompanion() } }.buttonStyle(.bordered)
                    }.padding(.top, 60)
                }
            }
            .frame(maxHeight: .infinity)
            .overlay { GeometryReader { proxy in plantLayer(in: proxy.size) } }
            .overlay { GeometryReader { proxy in chatLayer(height: proxy.size.height) }.allowsHitTesting(chatOpen) }
        }
        .padding(.horizontal, HopeTheme.pageInset)
        .coordinateSpace(name: "gardenPage")
    }

    private var companionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GardenCreature.animals) { animal in
                    let selected = animal.id == companionID
                    Button { companionID = animal.id } label: {
                        Text(animal.name).font(.subheadline.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .foregroundStyle(selected ? HopeTheme.onAccent : HopeTheme.ink)
                            .background(selected ? AnyShapeStyle(HopeTheme.accent) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                    }
                    .buttonStyle(SoftPressStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Trang 2: cảm xúc

    private var moodPage: some View {
        pageScroll {
            glass {
                HStack(spacing: 12) {
                    Image(stage.imageName).resizable().scaledToFit().frame(width: 52, height: 56).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cây của bạn · \(stage.title)").font(.headline).foregroundStyle(HopeTheme.ink)
                        Text(restDays == 0 ? "Ghé nghỉ lần đầu để cây bắt đầu lớn."
                             : "Cây đã lớn nhờ \(restDays) ngày bạn ghé nghỉ. Không có gì phải đuổi theo.")
                            .font(.footnote).foregroundStyle(HopeTheme.secondary)
                    }
                }
            }
            glass {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hôm nay bạn thế nào?").font(.headline).foregroundStyle(HopeTheme.ink)
                    HStack(spacing: 6) { ForEach(HopeMood.allCases) { moodChip($0) } }
                    if contextMood == nil {
                        Text("Chọn một từ gần nhất với lúc này. Không có câu trả lời đúng hay sai.")
                            .font(.footnote).foregroundStyle(HopeTheme.secondary)
                    }
                }
            }
            if let mood = contextMood {
                ForEach(HealingContent.suggestions(for: mood)) { item in
                    Button { open(item.destination) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol).font(.title3).foregroundStyle(HopeTheme.accent).frame(width: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.headline).foregroundStyle(HopeTheme.ink)
                                Text(item.detail).font(.footnote).foregroundStyle(HopeTheme.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(HopeTheme.secondary)
                        }
                        .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }.buttonStyle(SoftPressStyle())
                }
                glass {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Một lời dành cho bạn").font(.headline).foregroundStyle(HopeTheme.ink)
                        if let note = dailyNote {
                            Text(note.text).font(.system(.body, design: .serif)).foregroundStyle(HopeTheme.ink).lineSpacing(3)
                        } else {
                            HStack(spacing: 8) {
                                ThinkingDots()
                                Text("Hope đang nghĩ một lời cho bạn…").font(.subheadline).foregroundStyle(HopeTheme.secondary)
                            }
                        }
                    }
                }
                .task(id: mood) { if dailyNote == nil { dailyNote = await HealingAI.note(for: mood) } }
            }
            if let letter {
                glass {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Thư từ khu vườn", systemImage: "envelope.open").font(.footnote.weight(.semibold)).foregroundStyle(HopeTheme.accent)
                        Text(letter).font(.system(.body, design: .serif)).foregroundStyle(HopeTheme.ink).lineSpacing(3)
                    }
                }
            }
            Text(HealingContent.careFooter).font(.caption).foregroundStyle(HopeTheme.ink.opacity(0.8)).multilineTextAlignment(.center)
        }
    }

    private func moodChip(_ mood: HopeMood) -> some View {
        let selected = mood == contextMood
        return Button { select(mood) } label: {
            VStack(spacing: 5) {
                Image(systemName: mood.symbol).font(.title3)
                Text(mood.title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(selected ? HopeTheme.onAccent : HopeTheme.ink)
            .background(selected ? AnyShapeStyle(HopeTheme.accent) : AnyShapeStyle(HopeTheme.surfaceMuted.opacity(0.7)),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel(mood.title).accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Trang 3: nghỉ và nghe

    private var restPage: some View {
        pageScroll {
            glass {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nghỉ một chút").font(.headline).foregroundStyle(HopeTheme.ink)
                    HStack(spacing: 8) {
                        ForEach([1, 2, 3, 5], id: \.self) { minutes in
                            Button("\(minutes) phút") { restMinutes = minutes }
                                .font(.subheadline.weight(restMinutes == minutes ? .semibold : .regular))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(restMinutes == minutes ? HopeTheme.onAccent : HopeTheme.ink)
                                .background(restMinutes == minutes ? AnyShapeStyle(HopeTheme.accent) : AnyShapeStyle(HopeTheme.surfaceMuted.opacity(0.7)), in: Capsule())
                                .accessibilityAddTraits(restMinutes == minutes ? .isSelected : [])
                        }
                    }
                    Button { restRoute = PagerRestRoute(minutes: restMinutes) } label: {
                        Label("Bắt đầu thở cùng khu vườn", systemImage: "wind")
                    }.buttonStyle(HopePrimaryButtonStyle())
                    Text("Mỗi vòng 10 giây: hít vào 4, giữ 1, thở ra 5. Dừng bất cứ lúc nào.").font(.footnote).foregroundStyle(HopeTheme.secondary)
                }
            }
            glass {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Một khoảng yên").font(.headline).foregroundStyle(HopeTheme.ink)
                        Spacer()
                        if sound.isPlaying { Button("Dừng") { sound.stop() }.font(.subheadline.weight(.semibold)) }
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(AmbientScene.allCases) { scene in soundTile(scene) }
                    }
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(HopeTheme.secondary).accessibilityHidden(true)
                        Slider(value: Binding(get: { sound.volume }, set: { sound.setVolume($0) }), in: 0...1)
                            .accessibilityLabel("Âm lượng")
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(HopeTheme.secondary).accessibilityHidden(true)
                    }
                    HStack(spacing: 8) {
                        Text("Hẹn giờ tắt").font(.footnote).foregroundStyle(HopeTheme.secondary)
                        ForEach([15, 30, 60], id: \.self) { minutes in
                            let on = timerMinutesSelected == minutes && (sound.timerEndsAt ?? .distantPast) > Date()
                            Button("\(minutes)′") { timerMinutesSelected = on ? nil : minutes; sound.setTimer(minutes: on ? nil : minutes) }
                                .font(.subheadline).padding(.horizontal, 12).frame(minHeight: 36)
                                .foregroundStyle(on ? HopeTheme.onAccent : HopeTheme.ink)
                                .background(on ? AnyShapeStyle(HopeTheme.accent) : AnyShapeStyle(HopeTheme.surfaceMuted.opacity(0.7)), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    @State private var timerMinutesSelected: Int?

    private func soundTile(_ scene: AmbientScene) -> some View {
        let playing = sound.isPlaying && sound.scene == scene
        return Button {
            HealingHaptics.soft()
            if playing { sound.stop() }
            else if sound.isPlaying { sound.select(scene) }
            else {
                sound.play(scene)
                if !recordedListen { recordedListen = true; try? HealingStore.recordVisit(.listen, context: context) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: scene.symbol).font(.title3).foregroundStyle(HopeTheme.accent)
                Text(scene.title).font(.subheadline.weight(.semibold)).foregroundStyle(HopeTheme.ink)
                Text(playing ? "Đang phát" : "Phát").font(.caption).foregroundStyle(HopeTheme.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading).padding(12)
            .background(HopeTheme.surfaceMuted.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(playing ? HopeTheme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel(scene.title).accessibilityValue(playing ? "Đang phát" : "Đã tắt")
    }

    // MARK: - Trang 4: viết

    private var writePage: some View {
        pageScroll {
            glass {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Viết cho nhẹ").font(.headline).foregroundStyle(HopeTheme.ink)
                    Text("Nhật ký chỉ nằm trên máy bạn. Nó chỉ được gửi tới Gemini khi bạn tự bấm nhờ Hope đáp lại và đồng ý.")
                        .font(.footnote).foregroundStyle(HopeTheme.secondary)
                    HStack(spacing: 10) {
                        Button { sheet = .journalNew("Điều đang làm mình mệt là…") } label: { Label("Viết một bài", systemImage: "square.and.pencil") }
                            .buttonStyle(HopePrimaryButtonStyle())
                        Button { sheet = .closeDay } label: { Label("Khép lại hôm nay", systemImage: "moon.stars") }.buttonStyle(.bordered).tint(HopeTheme.accent)
                    }
                }
            }
            glass {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Gần đây").font(.headline).foregroundStyle(HopeTheme.ink)
                        Spacer()
                        if entries.count > 3 { Button("Xem tất cả (\(entries.count))") { sheet = .journalList }.font(.subheadline.weight(.semibold)) }
                    }
                    if entries.isEmpty {
                        Text("Chưa có bài nào. Một dòng cũng đủ.").font(.subheadline).foregroundStyle(HopeTheme.secondary)
                    }
                    ForEach(entries.prefix(3)) { entry in
                        Button { sheet = .journalEntry(entry) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(entry.updatedAt.formatted(date: .abbreviated, time: .shortened)) · \(entry.prompt.isEmpty ? "Viết tự do" : entry.prompt)")
                                    .font(.caption).foregroundStyle(HopeTheme.secondary).lineLimit(1)
                                Text(entry.text).font(.subheadline).foregroundStyle(HopeTheme.ink).lineLimit(2).multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(HopeTheme.surfaceMuted.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }.buttonStyle(SoftPressStyle())
                    }
                }
            }
            Toggle("Rung nhẹ khi chuyển nhịp", isOn: $hapticsOn).tint(HopeTheme.accent).foregroundStyle(HopeTheme.ink)
                .padding(.horizontal, 6)
        }
    }

    // MARK: - Khung chat nổi trên trang Vườn (chạm vào con vật là mở, bấm X để đóng)

    @ViewBuilder
    private func chatLayer(height: CGFloat) -> some View {
        if chatOpen {
            chatPanel
                .frame(height: min(height, min(max(height * 0.62, 260), 400)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var chatPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text(chatCompanion.name).font(.headline).foregroundStyle(HopeTheme.ink)
                Spacer(minLength: 0)
                Button { closeChat() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 40, height: 40)
                        .foregroundStyle(HopeTheme.ink).background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(SoftPressStyle()).accessibilityLabel("Đóng cuộc trò chuyện")
            }
            CompanionChatView(companionID: $chatCompanionID, mood: contextMood, embedded: true)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
    }

    private func openChat(named creatureName: String) {
        chatCompanionID = creatureName == GardenCreature.mascot.name ? GardenCreature.mascot.id : companion.id
        HealingHaptics.soft()
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.86)) { chatOpen = true }
    }

    private func closeChat() {
        guard chatOpen else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { chatOpen = false }
    }

    // MARK: - Chậu cây: kéo để đổi chỗ, chạm để tưới (mỗi ngày tối đa 3 lần, cách nhau ít nhất 4 giờ)

    private func plantSize(in area: CGSize) -> CGSize {
        let width = min(170, max(88, min(area.width * 0.38, area.height * 0.3)))
        return CGSize(width: width, height: width * 1312 / 1199)
    }

    /// Giữ chậu trong sân khấu và chừa chỗ phía trên cho thẻ trạng thái.
    private func clampPlant(_ point: CGPoint, area: CGSize, plant: CGSize) -> CGPoint {
        let minX = plant.width * 0.45
        let maxX = max(minX, area.width - plant.width * 0.45)
        let minY = 76 + plant.height / 2
        let maxY = max(minY, area.height - 2 - plant.height / 2)
        return CGPoint(x: min(max(point.x, minX), maxX), y: min(max(point.y, minY), maxY))
    }

    private func plantCenter(area: CGSize, plant: CGSize) -> CGPoint {
        let fx = plantX >= 0 ? plantX : 0.5
        let fy = plantBottom >= 0 ? plantBottom : 0.9
        return clampPlant(CGPoint(x: fx * area.width, y: fy * area.height - plant.height / 2), area: area, plant: plant)
    }

    private func commitPlant(_ center: CGPoint, area: CGSize, plant: CGSize) {
        let moved = clampPlant(center, area: area, plant: plant)
        plantX = moved.x / area.width
        plantBottom = (moved.y + plant.height / 2) / area.height
    }

    @ViewBuilder
    private func plantLayer(in area: CGSize) -> some View {
        if area.width > 40, area.height > 160 {
            let plant = plantSize(in: area)
            let base = plantCenter(area: area, plant: plant)
            let center = plantDrag.map {
                clampPlant(CGPoint(x: base.x + $0.width, y: base.y + $0.height), area: area, plant: plant)
            } ?? base
            plantGroup(area: area, plant: plant, flip: center.x > area.width * 0.55, centerX: center.x, base: base)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .global)
                        .onChanged { plantDrag = $0.translation }
                        .onEnded { value in
                            commitPlant(CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height), area: area, plant: plant)
                            plantDrag = nil
                            HealingHaptics.soft()
                        }
                )
                .onTapGesture { water() }
                .position(center)
        }
    }

    private func plantGroup(area: CGSize, plant: CGSize, flip: Bool, centerX: CGFloat, base: CGPoint) -> some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !running)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let sway = reduceMotion ? 0 : 1.6 * sin(t * 0.8) + 0.6 * sin(t * 1.9)
                let bounce = plantBounce(at: timeline.date)
                Image(stage.imageName).resizable().scaledToFit()
                    .scaleEffect(x: 1 - 0.018 * bounce, y: 1 + 0.035 * bounce, anchor: .bottom)
                    .rotationEffect(.degrees(sway), anchor: .bottom)
            }
            wateringLayer(width: plant.width, height: plant.height, flip: flip)
        }
        .frame(width: plant.width, height: plant.height)
        .scaleEffect(plantDrag == nil ? 1 : 1.04)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: plantDrag == nil)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            plantChip(area: area, centerX: centerX).alignmentGuide(.top) { $0[.bottom] + 6 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cây của bạn, giai đoạn \(stage.title)")
        .accessibilityValue(plantNote ?? "")
        .accessibilityHint("Chạm hai lần để tưới nước. Dùng các thao tác tuỳ chỉnh để dời chậu.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { water() }
        .accessibilityAction(named: "Dời chậu sang trái") { commitPlant(CGPoint(x: base.x - 28, y: base.y), area: area, plant: plant) }
        .accessibilityAction(named: "Dời chậu sang phải") { commitPlant(CGPoint(x: base.x + 28, y: base.y), area: area, plant: plant) }
        .accessibilityAction(named: "Dời chậu lên") { commitPlant(CGPoint(x: base.x, y: base.y - 28), area: area, plant: plant) }
        .accessibilityAction(named: "Dời chậu xuống") { commitPlant(CGPoint(x: base.x, y: base.y + 28), area: area, plant: plant) }
    }

    /// Bình nước đặt theo chậu: vòi nằm ngay trên đất của chậu; chậu ở nửa phải màn hình thì bình lật sang bên trái.
    private func wateringLayer(width: CGFloat, height: CGFloat, flip: Bool) -> some View {
        let canWidth = width * 0.8
        let canHeight = canWidth * 1024 / 1536
        return ZStack {
            Image("GardenWateringCan").resizable().scaledToFit()
                .frame(width: canWidth, height: canHeight)
                .rotationEffect(.degrees(canPouring ? -20 : 0))
                .offset(x: canPouring ? 0 : canWidth * 0.45, y: canPouring ? 0 : -canHeight * 0.1)
                .opacity(canPouring ? 1 : 0)
                .position(x: width * 0.81, y: height - width * 0.61)
            if let start = pourStart, !reduceMotion {
                TimelineView(.animation) { timeline in
                    Canvas { context, _ in
                        drawDrops(&context, elapsed: timeline.date.timeIntervalSince(start), width: width, height: height)
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .scaleEffect(x: flip ? -1 : 1, y: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawDrops(_ context: inout GraphicsContext, elapsed: Double, width: CGFloat, height: CGFloat) {
        let spoutX = width * 0.5, spoutY = height - width * 0.6, fall = width * 0.21
        let emitUntil = pourDuration - 0.7
        for index in 0..<24 {
            let begin = Double(index) * 0.12
            let tau = elapsed - begin
            guard tau > 0, begin < emitUntil else { continue }
            let progress = tau / 0.9
            guard progress < 1 else { continue }
            let x = spoutX + (healingHash(Double(index) * 2.3) - 0.5) * width * 0.2
            let y = spoutY + fall * progress
            let alpha = min(1, tau * 8) * (1 - progress) * 0.9
            let rect = CGRect(x: x - 1.6, y: y - 5, width: 3.2, height: 9)
            context.fill(Path(roundedRect: rect, cornerRadius: 1.6), with: .color(Color.healing(0xD6EEFF, opacity: alpha)))
        }
    }

    /// Thẻ trạng thái phía trên chậu: lời nhắn và, khi đang tưới, thanh tiến độ.
    @ViewBuilder
    private func plantChip(area: CGSize, centerX: CGFloat) -> some View {
        if pourStart != nil || plantNote != nil {
            let chipWidth = min(230, area.width - 24)
            let shift = max(0, 12 - (centerX - chipWidth / 2)) - max(0, (centerX + chipWidth / 2) - (area.width - 12))
            VStack(spacing: 6) {
                Text(plantNote ?? "").font(.footnote).multilineTextAlignment(.center).foregroundStyle(HopeTheme.ink)
                if let start = pourStart {
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                        ProgressView(value: min(1, max(0, timeline.date.timeIntervalSince(start) / pourDuration)))
                            .tint(HopeTheme.accent)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(width: chipWidth)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .offset(x: shift)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Cây rung nhẹ như thạch sau khi được tưới, tắt dần trong khoảng hai giây.
    private func plantBounce(at date: Date) -> Double {
        guard !reduceMotion, let start = bounceStart else { return 0 }
        let tau = date.timeIntervalSince(start)
        guard tau >= 0, tau < 2.4 else { return 0 }
        return sin(tau * 9) * exp(-tau * 3.2)
    }

    private func water() {
        guard pourTask == nil else { return }
        let log = PlantWatering.parse(waterLogRaw)
        let status = PlantWatering.status(log: log)
        if let message = PlantWatering.blockedMessage(status) {
            HealingHaptics.soft()
            showPlantNote(message)
            return
        }
        guard case .ready(let count) = status else { return }
        let number = count + 1
        waterLogRaw = PlantWatering.encode(PlantWatering.recording(.now, in: log))
        plantHintSeen = true
        plantNoteTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            plantNote = "Đang tưới… lần \(number)/\(PlantWatering.perDay) hôm nay"
        }
        pourStart = Date()
        HealingHaptics.soft()
        if !reduceMotion { withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { canPouring = true } }
        pourTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(pourDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6)) { canPouring = false }
            pourStart = nil
            bounceStart = Date()
            HealingHaptics.settle()
            pourTask = nil
            if number < PlantWatering.perDay {
                showPlantNote("Cây đã được tưới (hôm nay \(number)/\(PlantWatering.perDay)). Lần sau cách \(PlantWatering.waitText(PlantWatering.gap)).")
            } else {
                showPlantNote("Cây đã được tưới đủ \(PlantWatering.perDay)/\(PlantWatering.perDay) lần hôm nay.")
            }
        }
    }

    private func showPlantNote(_ text: String) {
        plantNoteTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { plantNote = text }
        plantNoteTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { plantNote = nil }
        }
    }

    private func showPlantHintOnce() async {
        guard isActive, !plantHintSeen else { return }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        guard !Task.isCancelled, page == 0, !plantHintSeen, pourTask == nil else { return }
        plantHintSeen = true
        showPlantNote("Chạm vào cây để tưới nước. Kéo để đổi chỗ chậu.")
    }

    // MARK: - Sheet

    @ViewBuilder
    private func sheetContent(_ route: PagerSheet) -> some View {
        switch route {
        case .journalNew(let prompt): JournalEditorView(entry: nil, kind: .free, prompt: prompt, mood: contextMood) { sheet = nil }
        case .journalList: JournalListView(mood: contextMood)
        case .journalEntry(let entry): JournalEditorView(entry: entry, kind: entry.kind, prompt: entry.prompt, mood: contextMood) { sheet = nil }
        case .closeDay: CloseDayView()
        case .settings: SettingsView()
        }
    }

    // MARK: - Hành động

    private func select(_ mood: HopeMood) {
        HealingHaptics.soft()
        dailyNote = nil
        selectedMood = mood
        do { try HealingStore.recordMood(mood, context: context) } catch { errorMessage = error.localizedDescription }
    }

    private func open(_ destination: HealingDestination) {
        HealingHaptics.soft()
        switch destination {
        case .rest(let minutes): restRoute = PagerRestRoute(minutes: minutes)
        case .journal(_, let prompt): sheet = .journalNew(prompt)
        case .listen: withAnimation { page = 2 }
        case .note: dailyNote = nil; withAnimation { page = 1 }
        case .closeDay: sheet = .closeDay
        }
    }

    private func nextQuote(automatic: Bool) {
        if !automatic { HealingHaptics.soft() }
        quoteVariant += 1
        withAnimation(.easeInOut(duration: 0.4)) { quote = HopeQuotes.quote(variant: quoteVariant) }
    }

    private func loadLetter() async {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return }
        let weekVisits = visits.filter { week.contains($0.createdAt) }
        let days = GardenGrowth.restDays(weekVisits)
        guard days >= 2 else { return }
        var counts: [HopeMood: Int] = [:]
        for item in moods where week.contains(item.createdAt) { counts[item.mood, default: 0] += 1 }
        if let result = await HealingAI.weeklyLetter(moodCounts: counts, restDays: days) { letter = result }
    }

    private func measureStage(_ geometry: GeometryProxy) {
        let local = geometry.frame(in: .named("gardenPage"))
        let global = geometry.frame(in: .global)
        stageFrame = CGRect(x: local.minX, y: global.minY, width: local.width, height: local.height)
        pushPath()
    }

    private func pushPath() {
        scene.pathContext = GardenPathContext(screen: screenSize, frame: stageFrame)
    }

    private func updatePlayback() {
        scene.configure(reduced: reduceMotion || voiceOver, paused: !running || reduceMotion || voiceOver)
    }

    private func loadCompanion() async {
        let selected = companion
        loading = true
        loadFailed = false
        guard !Task.isCancelled, selected.id == companion.id else { return }
        scene.install(selected)
        // Chạm vào con vật: nó chào (hiệu ứng trong cảnh) và khung chat của nó mở ngay trên trang Vườn.
        scene.onGreeting = { name in Task { @MainActor in openChat(named: name) } }
        loadFailed = scene.unavailable
        loading = false
        updatePlayback()
    }
}

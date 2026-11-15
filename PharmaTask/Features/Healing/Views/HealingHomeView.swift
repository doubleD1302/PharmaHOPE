import SwiftUI
import SwiftData

private struct RestRoute: Identifiable {
    let id = UUID()
    let minutes: Int?
}

private enum HealingSheetRoute: Identifiable {
    case journal(JournalKind, String)
    case journalList, listen, note, closeDay

    var id: String {
        switch self {
        case .journal(let kind, let prompt): return "journal-\(kind.rawValue)-\(prompt)"
        case .journalList: return "journalList"
        case .listen: return "listen"
        case .note: return "note"
        case .closeDay: return "closeDay"
        }
    }
}

/// Màn hình Vườn (nghỉ, nhật ký, âm thanh, lời nhắn, khép ngày): nơi ghé nghỉ giữa ca. Không có chỉ tiêu, không có chuỗi ngày, cây chỉ lớn lên.
@MainActor
public struct HealingHomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \HealingVisit.createdAt, order: .reverse) private var visits: [HealingVisit]
    @Query(sort: \MoodCheckIn.createdAt, order: .reverse) private var moods: [MoodCheckIn]
    @AppStorage(HealingHaptics.preferenceKey) private var hapticsOn = true

    @State private var selectedMood: HopeMood?
    @State private var dailyNote: HealingNote?
    @State private var restRoute: RestRoute?
    @State private var sheet: HealingSheetRoute?
    @State private var letter: String?
    @State private var errorMessage: String?
    @State private var glow = false

    private let isActive: Bool
    public init(isActive: Bool = true) { self.isActive = isActive }

    private var restDays: Int { GardenGrowth.restDays(visits) }
    private var stage: GardenStage { GardenStage.stage(forDays: restDays) }
    private var todayMood: HopeMood? {
        moods.first(where: { Calendar.current.isDateInToday($0.createdAt) })?.mood
    }
    private var contextMood: HopeMood? { selectedMood ?? todayMood }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header.softAppear()
                    GardenSceneView(stage: stage, mood: contextMood, isActive: isActive).softAppear(delay: 0.1)
                    caption.softAppear(delay: 0.15)
                    moodSection.softAppear(delay: 0.2)
                    restCard.softAppear(delay: 0.25)
                    tiles.softAppear(delay: 0.3)
                    if let letter { letterCard(letter) }
                    Text(HealingContent.careFooter)
                        .font(.footnote).foregroundStyle(HopeTheme.secondary)
                }
                .padding(.horizontal, HopeTheme.pageInset).padding(.top, 20).padding(.bottom, 32)
            }
            .background(HopeTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(HopeTheme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 9) {
                        HopeBrandMark(size: 30)
                        Text("Vườn Hope").font(.headline).foregroundStyle(HopeTheme.ink)
                    }.accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Rung nhẹ khi chuyển nhịp", isOn: $hapticsOn)
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.body.weight(.medium))
                            .frame(width: 44, height: 44).foregroundStyle(HopeTheme.ink)
                    }.accessibilityLabel("Tùy chọn của Vườn")
                }
            }
            .fullScreenCover(item: $restRoute) { route in
                BreakSessionView(initialMinutes: route.minutes, mood: contextMood, stage: stage)
            }
            .sheet(item: $sheet) { route in
                sheetContent(route)
                    .presentationDragIndicator(.visible)
            }
            .alert("Hope", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Đóng", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .task { await loadLetter() }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 4.8).repeatForever(autoreverses: true)) { glow = true }
            }
        }
    }

    // MARK: - Các khối

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline).foregroundStyle(HopeTheme.secondary)
            Text("Một chỗ cho riêng bạn.")
                .font(.largeTitle.weight(.semibold)).tracking(-0.7)
                .foregroundStyle(HopeTheme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var caption: some View {
        let text = restDays == 0
            ? "Ghé nghỉ lần đầu để cây bắt đầu lớn."
            : "Cây đã lớn nhờ \(restDays) ngày bạn ghé nghỉ. Không có gì phải đuổi theo."
        return Text(text).font(.subheadline).foregroundStyle(HopeTheme.secondary)
            .contentTransition(.opacity)
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HealingCardTitle(title: "Lúc này, bạn thấy thế nào?", subtitle: "Chọn điều gần nhất. Bỏ qua lúc nào cũng được.")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(HopeMood.allCases) { mood in moodChip(mood) }
                }.padding(.vertical, 4).padding(.horizontal, 2)
            }
            if let mood = selectedMood {
                suggestionBlock(mood)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .hopeCard()
        .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.86), value: selectedMood)
    }

    private func moodChip(_ mood: HopeMood) -> some View {
        let selected = mood == selectedMood
        return Button { select(mood) } label: {
            VStack(spacing: 8) {
                Image(systemName: mood.symbol).font(.title2)
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? nil : selectedMood)
                Text(mood.title).font(.footnote.weight(.medium)).lineLimit(1)
            }
            .frame(width: 88, height: 84)
            .foregroundStyle(selected ? HopeTheme.onAccent : HopeTheme.ink)
            .background(selected ? HopeTheme.accent : HopeTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .scaleEffect(selected && !reduceMotion ? 1.04 : 1)
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel(mood.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func suggestionBlock(_ mood: HopeMood) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            Group {
                if let note = dailyNote {
                    Text(note.text)
                        .font(.system(.body, design: .serif)).foregroundStyle(HopeTheme.ink)
                        .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        .id(note.text).transition(.opacity)
                } else {
                    Text("Hope đang nghĩ một lời cho bạn…").font(.subheadline).foregroundStyle(HopeTheme.secondary)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.8), value: dailyNote)
            ForEach(Array(HealingContent.suggestions(for: mood).enumerated()), id: \.element.id) { index, item in
                Button { open(item.destination) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: item.symbol).font(.title3).foregroundStyle(HopeTheme.accent)
                            .frame(width: 44, height: 44)
                            .background(HopeTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.headline).foregroundStyle(HopeTheme.ink)
                            Text(item.detail).font(.subheadline).foregroundStyle(HopeTheme.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(HopeTheme.secondary)
                    }
                    .padding(12)
                    .background(HopeTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(SoftPressStyle())
                .softAppear(delay: 0.15 + Double(index) * 0.1)
            }
            Button("Để sau") { withAnimation { selectedMood = nil } }
                .font(.subheadline).foregroundStyle(HopeTheme.secondary).frame(minHeight: 44)
        }
    }

    private var restCard: some View {
        Button { restRoute = RestRoute(minutes: nil) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NGHỈ MỘT CHÚT").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(HopeTheme.mint)
                    Text("Một đến ba phút\ncho riêng bạn").font(.title2.weight(.semibold)).foregroundStyle(HopeTheme.onHero)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Chuyển động chậm, lời nhắc thả lỏng. Dừng bất cứ lúc nào.")
                        .font(.footnote).foregroundStyle(HopeTheme.onHero.opacity(0.85))
                }.frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [HopeTheme.mint.opacity(0.55), .clear], center: .center, startRadius: 2, endRadius: 70))
                        .frame(width: 130, height: 130)
                        .scaleEffect(glow ? 1.14 : 0.9).opacity(glow ? 0.9 : 0.55)
                    Image("GardenTeaCup").resizable().scaledToFit().frame(width: 96)
                        .offset(y: glow ? -2 : 2)
                }
                .accessibilityHidden(true)
            }
            .padding(22)
            .background(HopeTheme.hero, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityHint("Mở phiên nghỉ ngắn có nhịp thở")
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile(title: "Viết ra cho nhẹ", detail: "Nhật ký riêng", image: "GardenJournal", symbol: nil) { sheet = .journalList }
            tile(title: "Nghe một khoảng yên", detail: "Mưa, lá, suối, quán cà phê", image: nil, symbol: "headphones") { sheet = .listen }
            tile(title: "Một lời dành cho bạn", detail: "Vài dòng viết riêng", image: nil, symbol: "quote.bubble") { sheet = .note }
            tile(title: "Khép lại hôm nay", detail: "Nhìn lại và ghi nhận", image: nil, symbol: "moon.stars") { sheet = .closeDay }
        }
    }

    private func tile(title: String, detail: String, image: String?, symbol: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Group {
                    if let image {
                        Image(image).resizable().scaledToFit().frame(height: 40)
                    } else if let symbol {
                        Image(systemName: symbol).font(.title2).foregroundStyle(HopeTheme.accent)
                    }
                }
                .frame(height: 40, alignment: .leading)
                .accessibilityHidden(true)
                Spacer(minLength: 0)
                Text(title).font(.headline).foregroundStyle(HopeTheme.ink).multilineTextAlignment(.leading)
                Text(detail).font(.footnote).foregroundStyle(HopeTheme.secondary).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
            .padding(16)
            .background(HopeTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(HopeTheme.border.opacity(0.7)))
        }
        .buttonStyle(SoftPressStyle())
    }

    private func letterCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Thư từ khu vườn", systemImage: "envelope.open")
                .font(.footnote.weight(.semibold)).foregroundStyle(HopeTheme.accent)
            Text(text).font(.system(.body, design: .serif)).foregroundStyle(HopeTheme.ink)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
        .hopeCard()
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    @ViewBuilder
    private func sheetContent(_ route: HealingSheetRoute) -> some View {
        switch route {
        case .journal(let kind, let prompt):
            JournalEditorView(entry: nil, kind: kind, prompt: prompt, mood: contextMood) { sheet = nil }
        case .journalList:
            JournalListView(mood: contextMood)
        case .listen:
            AmbientSoundView()
        case .note:
            HealingNoteView(initialMood: contextMood)
        case .closeDay:
            CloseDayView()
        }
    }

    // MARK: - Hành động

    private func select(_ mood: HopeMood) {
        if selectedMood == mood {
            selectedMood = nil
            return
        }
        HealingHaptics.soft()
        dailyNote = nil
        selectedMood = mood
        do { try HealingStore.recordMood(mood, context: context) }
        catch { errorMessage = error.localizedDescription }
        Task { @MainActor in
            let note = await HealingAI.note(for: mood)
            guard selectedMood == mood else { return }
            dailyNote = note
        }
    }

    private func open(_ destination: HealingDestination) {
        HealingHaptics.soft()
        switch destination {
        case .rest(let minutes): restRoute = RestRoute(minutes: minutes)
        case .journal(let kind, let prompt): sheet = .journal(kind, prompt)
        case .listen: sheet = .listen
        case .note: sheet = .note
        case .closeDay: sheet = .closeDay
        }
    }

    private func loadLetter() async {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: .now) else { return }
        let weekVisits = visits.filter { week.contains($0.createdAt) }
        let days = GardenGrowth.restDays(weekVisits)
        guard days >= 2 else { return }
        var counts: [HopeMood: Int] = [:]
        for item in moods where week.contains(item.createdAt) { counts[item.mood, default: 0] += 1 }
        if let result = await HealingAI.weeklyLetter(moodCounts: counts, restDays: days) {
            withAnimation(.easeInOut(duration: 0.9)) { letter = result }
        }
    }
}

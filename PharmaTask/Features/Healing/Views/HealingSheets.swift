import SwiftUI
import SwiftData

// MARK: - Một lời dành cho bạn

/// Chữ hiện ra từ mờ sang rõ, chậm. Mỗi câu mới là một view mới nên hiệu ứng chạy lại.
private struct RevealingText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    var body: some View {
        Text(text)
            .font(.system(.title2, design: .serif).weight(.medium))
            .foregroundStyle(HopeTheme.ink)
            .lineSpacing(6)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .blur(radius: shown || reduceMotion ? 0 : 10)
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.985)
            .onAppear {
                let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 1.5)
                withAnimation(animation) { shown = true }
            }
    }
}

private struct SoftDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(HopeTheme.accent)
                        .frame(width: 8, height: 8)
                        .opacity(0.25 + 0.65 * (0.5 + 0.5 * sin(t * 2.2 - Double(i) * 0.7)))
                }
            }
        }
        .accessibilityLabel("Đang viết cho bạn")
    }
}

@MainActor
struct HealingNoteView: View {
    let initialMood: HopeMood?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var mood: HopeMood
    @State private var note: HealingNote?
    @State private var variant = 0
    @State private var isLoading = false
    @State private var saved = false
    @State private var recordedVisit = false
    @State private var errorMessage: String?

    init(initialMood: HopeMood?) {
        self.initialMood = initialMood
        _mood = State(initialValue: initialMood ?? .okay)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    moodRow
                    ZStack {
                        if let note {
                            VStack(spacing: 14) {
                                Image(systemName: "quote.opening").font(.title).foregroundStyle(HopeTheme.accent.opacity(0.6))
                                RevealingText(text: note.text)
                                Text(note.isAI ? "Viết riêng cho bạn · Gemini" : "Lời nhắn viết sẵn")
                                    .font(.caption).foregroundStyle(HopeTheme.secondary)
                            }
                            .id(note.text)
                            .transition(.opacity)
                        } else {
                            SoftDots()
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .padding(.horizontal, 8)
                    actions
                    Text(HealingContent.careFooter)
                        .font(.footnote).foregroundStyle(HopeTheme.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, HopeTheme.pageInset).padding(.vertical, 18)
            }
            .background(HopeTheme.background)
            .navigationTitle("Một lời dành cho bạn").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
            .alert("Hope", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Đóng", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .task { load() }
        }
        .tint(HopeTheme.accent)
    }

    private var moodRow: some View {
        VStack(spacing: 10) {
            Text("Lúc này bạn thấy thế nào?").font(.subheadline).foregroundStyle(HopeTheme.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HopeMood.allCases) { item in
                        let selected = item == mood
                        Button {
                            guard item != mood else { return }
                            HealingHaptics.soft()
                            mood = item; variant = 0; saved = false
                            load()
                        } label: {
                            Label(item.title, systemImage: item.symbol)
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 14).frame(minHeight: 44)
                                .foregroundStyle(selected ? HopeTheme.onAccent : HopeTheme.ink)
                                .background(selected ? HopeTheme.accent : HopeTheme.surfaceMuted, in: Capsule())
                                .animation(.easeInOut(duration: 0.35), value: selected)
                        }
                        .buttonStyle(SoftPressStyle())
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                variant += 1; saved = false
                load()
            } label: {
                Label("Một lời khác", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(HopeTheme.accent)
                    .background(HopeTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: HopeTheme.controlRadius, style: .continuous))
            }
            .buttonStyle(SoftPressStyle()).disabled(isLoading)
            Button(action: keep) {
                Label(saved ? "Đã giữ lại trong nhật ký" : "Giữ lại trong nhật ký", systemImage: saved ? "checkmark" : "bookmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(HopeTheme.onAccent)
                    .background(HopeTheme.accent, in: RoundedRectangle(cornerRadius: HopeTheme.controlRadius, style: .continuous))
                    .contentTransition(.opacity)
            }
            .buttonStyle(SoftPressStyle()).disabled(note == nil || saved)
            .animation(.easeInOut(duration: 0.4), value: saved)
        }
    }

    private func load() {
        let requestedMood = mood, requestedVariant = variant
        isLoading = true
        withAnimation(.easeInOut(duration: 0.5)) { note = nil }
        Task { @MainActor in
            let result = await HealingAI.note(for: requestedMood, variant: requestedVariant)
            guard requestedMood == mood, requestedVariant == variant else { return }
            withAnimation(.easeInOut(duration: 0.8)) { note = result }
            isLoading = false
            if !recordedVisit {
                recordedVisit = true
                try? HealingStore.recordVisit(.note, context: context)
            }
        }
    }

    private func keep() {
        guard let note else { return }
        do {
            try HealingStore.saveJournal(kind: .free, prompt: "Một lời dành cho mình", text: note.text, context: context)
            HealingHaptics.settle()
            saved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Khép lại hôm nay

@MainActor
struct CloseDayView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<TaskItem> { $0.isCompleted && $0.deletedAt == nil }) private var completedTasks: [TaskItem]
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && $0.deletedAt == nil }) private var openTasks: [TaskItem]
    @State private var text = ""
    @State private var suggestions = HealingContent.acknowledgements
    @State private var closed = false
    @State private var savedLine = ""
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var doneToday: [TaskItem] { HealingStore.completedToday(completedTasks) }
    private var canClose: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private let night = Color.healing(0xF6F5E9)

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        summary
                        acknowledgement
                        actions
                    }
                    .padding(.horizontal, HopeTheme.pageInset).padding(.vertical, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(HopeTheme.background)
                .navigationTitle("Khép lại hôm nay").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }
                .alert("Hope", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                    Button("Đóng", role: .cancel) {}
                } message: { Text(errorMessage ?? "") }
            }
            .tint(HopeTheme.accent)
            closing
        }
        .task {
            let loaded = await HealingAI.acknowledgements(completed: doneToday.count, unfinished: openTasks.count)
            if loaded.count >= 3 { withAnimation(.easeInOut(duration: 0.6)) { suggestions = loaded } }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Image(systemName: "moon.stars.fill").font(.system(size: 34))
                    .foregroundStyle(HopeTheme.accent)
                    .rotationEffect(.degrees(6 * sin(t * 0.7)))
                    .offset(y: 2 * sin(t * 0.9))
            }
            .frame(width: 48, height: 48)
            .accessibilityHidden(true)
            Text("Nhìn lại một chút rồi để ngày hôm nay nghỉ.")
                .font(.subheadline).foregroundStyle(HopeTheme.secondary)
        }
        .softAppear()
    }

    private var summary: some View {
        let done = doneToday
        return VStack(alignment: .leading, spacing: 12) {
            HealingCardTitle(title: done.isEmpty ? "Hôm nay bạn đã có mặt." : "Hôm nay bạn đã hoàn thành \(done.count) việc.",
                             subtitle: done.isEmpty ? "Không có việc nào được tick, và vậy cũng được." : nil)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(done.prefix(6).enumerated()), id: \.element.id) { index, task in
                    Label(task.title, systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(HopeTheme.ink).lineLimit(2)
                        .labelStyle(CheckLabelStyle())
                        .softAppear(delay: min(0.12 * Double(index), 0.7))
                }
                if done.count > 6 {
                    Text("và \(done.count - 6) việc khác").font(.footnote).foregroundStyle(HopeTheme.secondary)
                }
            }
            if !openTasks.isEmpty {
                Text("Còn \(openTasks.count) việc chưa xong. Chúng vẫn ở đó, mai bạn xem lại cũng được.")
                    .font(.footnote).foregroundStyle(HopeTheme.secondary).padding(.top, 4)
            }
        }
        .hopeCard()
        .softAppear(delay: 0.15)
    }

    private var acknowledgement: some View {
        VStack(alignment: .leading, spacing: 12) {
            HealingCardTitle(title: "Một điều mình muốn ghi nhận ở bản thân", subtitle: "Một dòng thôi, bằng lời của bạn.")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { line in
                        Button {
                            HealingHaptics.soft()
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { text = line }
                        } label: {
                            Text(line).font(.footnote.weight(.medium)).lineLimit(1)
                                .padding(.horizontal, 14).frame(minHeight: 40)
                                .foregroundStyle(HopeTheme.ink)
                                .background(HopeTheme.surfaceMuted, in: Capsule())
                        }
                        .buttonStyle(SoftPressStyle())
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                }
            }
            TextField("Hôm nay mình đã…", text: $text, axis: .vertical)
                .lineLimit(2...5)
                .focused($focused)
                .padding(14)
                .background(HopeTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(focused ? HopeTheme.accent.opacity(0.5) : HopeTheme.border))
                .animation(.easeInOut(duration: 0.3), value: focused)
        }
        .softAppear(delay: 0.3)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button("Khép lại hôm nay") { close(withText: true) }
                .buttonStyle(HopePrimaryButtonStyle()).disabled(!canClose)
            Button("Khép lại mà không viết") { close(withText: false) }
                .font(.subheadline).foregroundStyle(HopeTheme.secondary).frame(minHeight: 44)
        }
        .softAppear(delay: 0.45)
    }

    private var closing: some View {
        ZStack {
            LinearGradient(colors: [Color.healing(0x07142A), Color.healing(0x12302C)], startPoint: .top, endPoint: .bottom)
            StarField(level: closed ? 1 : 0, count: 34, paused: reduceMotion)
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "moon.stars.fill").font(.system(size: 54))
                    .foregroundStyle(Color.healing(0xF4E3B5))
                    .symbolEffect(.pulse, options: .repeating, isActive: closed && !reduceMotion)
                Text("Hôm nay đã đủ rồi.").font(.system(.largeTitle, design: .serif).weight(.medium)).foregroundStyle(night)
                    .softAppear(delay: 0.6)
                if !savedLine.isEmpty {
                    Text("\u{201C}\(savedLine)\u{201D}").font(.system(.title3, design: .serif)).italic()
                        .foregroundStyle(night.opacity(0.85)).multilineTextAlignment(.center)
                        .softAppear(delay: 1.0)
                }
                Text("Chúc bạn một giấc ngủ nhẹ.").font(.body).foregroundStyle(night.opacity(0.75))
                    .softAppear(delay: 1.4)
                Spacer()
                Button("Xong") { dismiss() }.buttonStyle(HopePrimaryButtonStyle()).softAppear(delay: 1.8)
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .opacity(closed ? 1 : 0)
        }
        .ignoresSafeArea()
        .opacity(closed ? 1 : 0)
        .allowsHitTesting(closed)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.6), value: closed)
        .preferredColorScheme(closed ? .dark : nil)
    }

    private func close(withText: Bool) {
        do {
            if withText {
                let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
                try HealingStore.saveJournal(kind: .closeDay, prompt: "Một điều mình ghi nhận ở bản thân", text: line, context: context)
                savedLine = line
            } else {
                try HealingStore.recordVisit(.closeDay, context: context)
            }
            focused = false
            HealingHaptics.settle()
            closed = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CheckLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.icon.foregroundStyle(HopeTheme.accent)
            configuration.title
        }
    }
}

import SwiftUI
import SwiftData

private enum EditorRoute: Identifiable {
    case new
    case edit(JournalEntry)
    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let entry): return entry.id
        }
    }
}

/// Danh sách nhật ký riêng, chỉ lưu trên máy.
@MainActor
struct JournalListView: View {
    let mood: HopeMood?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \JournalEntry.createdAt, order: .reverse) private var entries: [JournalEntry]
    @State private var route: EditorRoute?
    @State private var pendingDelete: JournalEntry?
    @State private var errorMessage: String?

    private var days: [(day: Date, items: [JournalEntry])] {
        let grouped = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if entries.isEmpty { emptyState }
                    ForEach(days, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.day, format: .dateTime.weekday(.wide).day().month(.wide))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(HopeTheme.secondary)
                            ForEach(group.items) { entry in
                                card(entry)
                            }
                        }
                    }
                    Text("Nhật ký chỉ lưu trên máy này. Hope không gửi nhật ký đi đâu trừ khi bạn tự chọn nghe lời đáp trong một bài viết.")
                        .font(.footnote).foregroundStyle(HopeTheme.secondary).padding(.top, 8)
                }
                .padding(.horizontal, HopeTheme.pageInset).padding(.vertical, 20)
            }
            .background(HopeTheme.background)
            .navigationTitle("Viết ra cho nhẹ").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { route = .new } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Viết bài mới")
                }
            }
            .sheet(item: $route) { route in
                switch route {
                case .new:
                    JournalEditorView(entry: nil, kind: .free, prompt: HealingContent.journalPrompts[0], mood: mood) { self.route = nil }
                case .edit(let entry):
                    JournalEditorView(entry: entry, kind: entry.kind, prompt: entry.prompt, mood: mood) { self.route = nil }
                }
            }
            .confirmationDialog("Xóa bài viết này?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Xóa vĩnh viễn", role: .destructive) {
                    if let entry = pendingDelete {
                        do { try HealingStore.delete(entry, context: context) } catch { errorMessage = error.localizedDescription }
                    }
                    pendingDelete = nil
                }
                Button("Giữ lại", role: .cancel) { pendingDelete = nil }
            } message: { Text("Bài viết sẽ biến mất khỏi máy này và không thể khôi phục.") }
            .alert("Hope", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Đóng", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
        .tint(HopeTheme.accent)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Image("GardenJournal").resizable().scaledToFit().frame(width: 130)
                    .offset(y: 4 * sin(t * 0.9))
                    .rotationEffect(.degrees(1.2 * sin(t * 0.6)))
            }
            .accessibilityHidden(true)
            Text("Trang đầu đang chờ bạn.").font(.title3.weight(.semibold)).foregroundStyle(HopeTheme.ink)
            Text("Viết vài dòng, không cần đúng hay hay. Chỉ cần là của bạn.")
                .font(.subheadline).foregroundStyle(HopeTheme.secondary).multilineTextAlignment(.center)
            Button("Viết bài đầu tiên") { route = .new }
                .buttonStyle(HopePrimaryButtonStyle()).padding(.top, 6)
        }
        .frame(maxWidth: .infinity).padding(.top, 30)
        .softAppear()
    }

    private func card(_ entry: JournalEntry) -> some View {
        Button { route = .edit(entry) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.kind.title).font(.caption.weight(.semibold)).foregroundStyle(HopeTheme.accent)
                    Spacer()
                    Text(entry.createdAt, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(HopeTheme.secondary)
                }
                if !entry.prompt.isEmpty {
                    Text(entry.prompt).font(.footnote).foregroundStyle(HopeTheme.secondary)
                }
                Text(entry.text).font(.body).foregroundStyle(HopeTheme.ink).lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .hopeCard()
        }
        .buttonStyle(SoftPressStyle())
        .contextMenu {
            Button("Xóa", systemImage: "trash", role: .destructive) { pendingDelete = entry }
        }
        .softAppear()
    }
}

/// Soạn hoặc sửa một bài. Có thể xin một lời đáp từ AI, và chỉ gửi bài đi sau khi bạn đồng ý.
@MainActor
struct JournalEditorView: View {
    let entry: JournalEntry?
    let kind: JournalKind
    let mood: HopeMood?
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var prompt: String
    @State private var text: String
    @State private var aiPrompts: [String] = []
    @State private var reply: String?
    @State private var isReplying = false
    @State private var confirmingReply = false
    @State private var hasKey = GeminiKeyStore.hasKey
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    init(entry: JournalEntry?, kind: JournalKind, prompt: String, mood: HopeMood?, onDone: @escaping () -> Void) {
        self.entry = entry; self.kind = kind; self.mood = mood; self.onDone = onDone
        _prompt = State(initialValue: prompt)
        _text = State(initialValue: entry?.text ?? "")
    }

    private var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var promptChoices: [String] { HealingContent.journalPrompts + aiPrompts }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if entry == nil { promptChips }
                    Text(prompt)
                        .font(.system(.title2, design: .serif).weight(.medium)).foregroundStyle(HopeTheme.ink)
                        .id(prompt).transition(.opacity)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    editor
                    replySection
                    Text("Bài viết chỉ lưu trên máy này.")
                        .font(.footnote).foregroundStyle(HopeTheme.secondary)
                }
                .padding(.horizontal, HopeTheme.pageInset).padding(.vertical, 18)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: prompt)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(HopeTheme.background)
            .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng", action: onDone) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu", action: save).fontWeight(.semibold).disabled(!canSave)
                }
            }
            .confirmationDialog("Gửi bài viết này tới Gemini?", isPresented: $confirmingReply, titleVisibility: .visible) {
                Button("Gửi và nghe lời đáp") { requestReply() }
                Button("Không gửi", role: .cancel) {}
            } message: {
                Text("Nội dung bạn vừa viết sẽ được gửi tới Gemini để tạo lời đáp. Bài viết vẫn chỉ được lưu trên máy này.")
            }
            .alert("Hope", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Đóng", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .task {
                hasKey = GeminiKeyStore.hasKey
                if entry == nil {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    focused = true
                    if let mood {
                        let loaded = await HealingAI.journalPrompts(mood: mood)
                        withAnimation(.easeInOut(duration: 0.6)) { aiPrompts = loaded }
                    }
                }
            }
        }
        .tint(HopeTheme.accent)
    }

    private var promptChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(promptChoices, id: \.self) { choice in
                    let selected = choice == prompt
                    Button {
                        HealingHaptics.soft()
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) { prompt = choice }
                    } label: {
                        Text(choice).font(.footnote.weight(.medium)).lineLimit(1)
                            .padding(.horizontal, 14).frame(minHeight: 40)
                            .foregroundStyle(selected ? HopeTheme.onAccent : HopeTheme.ink)
                            .background(selected ? HopeTheme.accent : HopeTheme.surfaceMuted, in: Capsule())
                    }
                    .buttonStyle(SoftPressStyle())
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .font(.body).foregroundStyle(HopeTheme.ink)
                .frame(minHeight: 220)
                .padding(10)
                .background(HopeTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(focused ? HopeTheme.accent.opacity(0.5) : HopeTheme.border, lineWidth: 1))
                .animation(.easeInOut(duration: 0.3), value: focused)
                .accessibilityLabel("Nội dung nhật ký")
            if text.isEmpty {
                Text("Viết điều gì đến trước cũng được…")
                    .font(.body).foregroundStyle(HopeTheme.secondary.opacity(0.8))
                    .padding(.horizontal, 16).padding(.vertical, 18).allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder private var replySection: some View {
        if let reply {
            VStack(alignment: .leading, spacing: 10) {
                Label("Một lời đáp từ Hope", systemImage: "sparkles")
                    .font(.footnote.weight(.semibold)).foregroundStyle(HopeTheme.accent)
                Text(reply).font(.system(.body, design: .serif)).foregroundStyle(HopeTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .hopeCard()
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        Button { confirmingReply = true } label: {
            HStack(spacing: 10) {
                if isReplying { ProgressView().tint(HopeTheme.accent) } else { Image(systemName: "sparkles") }
                Text(isReplying ? "Hope đang đọc…" : (reply == nil ? "Nghe một lời đáp" : "Nghe lời đáp khác"))
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(HopeTheme.accent)
            .background(HopeTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: HopeTheme.controlRadius, style: .continuous))
        }
        .buttonStyle(SoftPressStyle())
        .disabled(!canSave || isReplying || !hasKey)
        .opacity(canSave && hasKey ? 1 : 0.55)
        if !hasKey {
            Text("Thêm khóa Gemini trong Cài đặt để nghe lời đáp.")
                .font(.footnote).foregroundStyle(HopeTheme.secondary)
        }
    }

    private func requestReply() {
        guard !isReplying else { return }
        isReplying = true
        let snapshot = text
        let currentPrompt = prompt
        Task { @MainActor in
            let result = await HealingAI.reflection(on: snapshot, prompt: currentPrompt)
            isReplying = false
            if let result {
                HealingHaptics.settle()
                withAnimation(.easeInOut(duration: 0.9)) { reply = result }
            } else {
                errorMessage = "Chưa nhận được lời đáp lúc này. Bài viết của bạn vẫn còn nguyên."
            }
        }
    }

    private func save() {
        do {
            if let entry {
                try HealingStore.update(entry, text: text, context: context)
            } else {
                try HealingStore.saveJournal(kind: kind, prompt: prompt, text: text, context: context)
            }
            HealingHaptics.settle()
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

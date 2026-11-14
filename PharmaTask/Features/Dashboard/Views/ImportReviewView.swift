import SwiftUI
import SwiftData

@MainActor
struct ImportReviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ShiftConfig.startTime, order: .reverse) private var shifts: [ShiftConfig]
    @State private var existingTitles: Set<String> = []
    let pending: PendingTaskImport
    var onSaved: () -> Void
    private let sourceText: String
    private let sourceLabel: String
    @State private var drafts: [TaskDraft] = []
    @State private var selectedShift = ""
    @State private var error: String?
    @State private var loaded = false
    @State private var confirmDiscard = false
    private var selected: Int { drafts.filter(\.isSelected).count }
    init(pending: PendingTaskImport, onSaved: @escaping () -> Void) {
        self.pending = pending; self.onSaved = onSaved
        sourceText = pending.sourceText; sourceLabel = pending.sourceLabel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Kiểm tra từng đầu việc trước khi lưu. Bạn có thể sửa nội dung hoặc bỏ chọn dòng không đúng.")
                        .font(.subheadline).foregroundStyle(HopeTheme.secondary)
                    Picker("Lưu vào ca", selection: $selectedShift) {
                        Text("Chưa gắn ca").tag("")
                        ForEach(shifts) { shift in
                            Text("\(shift.name) · \(shift.targetDate.formatted(date: .abbreviated, time: .omitted))").tag(shift.id)
                        }
                    }
                    DisclosureGroup("Tin nhắn gốc · \(sourceLabel)") {
                        Text(sourceText).font(.subheadline).textSelection(.enabled)
                    }
                }
                ForEach($drafts) { $draft in
                    Section {
                        Toggle("Lưu công việc này", isOn: $draft.isSelected)
                        TextField("Tên việc", text: $draft.title, axis: .vertical).lineLimit(1...4)
                        TextField("Chi tiết…", text: $draft.notes, axis: .vertical).lineLimit(2...6)
                        Picker("Ưu tiên", selection: $draft.priorityRaw) {
                            ForEach(TaskPriority.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                        }
                        TextField("Giờ HH:mm (để trống nếu chưa có)", text: Binding(
                            get: { draft.dueTime ?? "" },
                            set: { value in
                                let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                draft.dueTime = value.isEmpty ? nil : value
                            }))
                            .keyboardType(.numbersAndPunctuation)
                        if let due = TaskText.deadline(draft.dueTime, shift: shifts.first { $0.id == selectedShift }, fallback: .now) {
                            Text("Hạn dự kiến: \(due.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(HopeTheme.secondary)
                        }
                        if existingTitles.contains(TaskText.normalized(draft.title)) || drafts.contains(where: {
                            $0.id != draft.id && $0.isSelected && TaskText.normalized($0.title) == TaskText.normalized(draft.title)
                        }) {
                            Label("Đã có việc trùng tên trong ca này. Kiểm tra trước khi lưu.", systemImage: "exclamationmark.circle")
                                .font(.caption).foregroundStyle(HopeTheme.amber)
                        }
                    }
                }
                if let error = error { Section { Text(error).foregroundStyle(HopeTheme.urgent) } }
                Section { Button("Bỏ bản nháp", role: .destructive) { confirmDiscard = true } }
            }
            .scrollContentBackground(.hidden).background(HopeTheme.background)
            .navigationTitle("Duyệt kết quả AI").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Để sau", action: saveDraft) }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu \(selected) việc", action: commit).disabled(selected == 0 || !loaded) }
            }
            .confirmationDialog("Bỏ bản nháp này?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Bỏ bản nháp", role: .destructive) {
                    context.delete(pending)
                    do { try context.save(); onSaved(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription }
                }
            }
            .interactiveDismissDisabled()
            .tint(HopeTheme.accent)
            .onAppear {
                guard !loaded else { return }
                do {
                    drafts = try pending.drafts()
                    selectedShift = shifts.contains { $0.id == pending.shiftID } ? (pending.shiftID ?? "") : ""
                    loaded = true
                    loadDuplicates()
                } catch { self.error = error.localizedDescription }
            }
            .onChange(of: selectedShift) { _, _ in loadDuplicates() }
        }
    }
    private func loadDuplicates() {
        let shiftID: String? = selectedShift.isEmpty ? nil : selectedShift
        do {
            existingTitles = Set(try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.shiftId == shiftID && $0.deletedAt == nil })).map { TaskText.normalized($0.title) })
        } catch { self.error = error.localizedDescription }
    }
    private func saveDraft() {
        guard loaded else { dismiss(); return }
        do {
            pending.draftsData = try JSONEncoder().encode(drafts)
            pending.shiftID = selectedShift.isEmpty ? nil : selectedShift
            try context.save(); dismiss()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
    private func commit() {
        do {
            _ = try TaskImportService.commit(pending, drafts: drafts, shiftID: selectedShift.isEmpty ? nil : selectedShift, context: context)
            onSaved(); dismiss()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

@MainActor
struct ImportInboxView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PendingTaskImport.createdAt, order: .reverse) private var imports: [PendingTaskImport]
    @State private var selected: PendingTaskImport?
    @State private var viewModel = ShiftDashboardViewModel()
    var body: some View {
        List {
            if imports.isEmpty { ContentUnavailableView("Không có bản nháp", systemImage: "checkmark.circle") }
            ForEach(imports) { pending in
                Button { selected = pending } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pending.sourceLabel).font(.headline)
                        Text(pending.sourceText).font(.subheadline).foregroundStyle(HopeTheme.secondary).lineLimit(2)
                        Text(pending.createdAt, format: .dateTime.day().month().hour().minute()).font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Chờ duyệt AI").tint(HopeTheme.accent)
        .sheet(item: $selected) { pending in ImportReviewView(pending: pending) { selected = nil; viewModel.refresh(context: context) } }
        .alert("Hope", isPresented: $viewModel.showAlert) { Button("Đóng", role: .cancel) {} } message: { Text(viewModel.alertMessage ?? "") }
    }
}

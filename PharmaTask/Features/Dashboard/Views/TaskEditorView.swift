import SwiftUI
import SwiftData

@MainActor
struct TaskEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    var onSaved: () -> Void
    var onDeleted: () -> Void
    @State private var title: String
    @State private var notes: String
    @State private var priority: TaskPriority
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var reminder: Bool
    @State private var lead: Int
    @State private var error: String?
    @State private var confirmDelete = false

    init(task: TaskItem, onSaved: @escaping () -> Void, onDeleted: @escaping () -> Void) {
        self.task = task; self.onSaved = onSaved; self.onDeleted = onDeleted
        _title = State(initialValue: task.title); _notes = State(initialValue: task.notes ?? "")
        _priority = State(initialValue: task.priority); _hasDeadline = State(initialValue: task.dueAt != nil)
        _deadline = State(initialValue: task.dueAt ?? .now.addingTimeInterval(3600))
        _reminder = State(initialValue: task.reminderEnabled); _lead = State(initialValue: task.reminderLeadMinutes)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Công việc") {
                    TextField("Tên công việc", text: $title, axis: .vertical).lineLimit(1...4)
                    TextField("Ghi chú…", text: $notes, axis: .vertical).lineLimit(3...8)
                    Picker("Ưu tiên", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Toggle("Có hạn hoàn thành", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Hạn", selection: $deadline)
                        Toggle("Nhắc công việc", isOn: $reminder)
                        if reminder {
                            Picker("Nhắc trước", selection: $lead) {
                                ForEach([0, 5, 10, 15, 30, 60], id: \.self) { value in
                                    Text(value == 0 ? "Không nhắc trước" : "\(value) phút").tag(value)
                                }
                            }
                        }
                    }
                } header: { Text("Hạn và thông báo") } footer: {
                    Text("Nhắc trước hạn, đúng hạn và thêm một lần sau 15 phút quá hạn nếu chưa xong. Việc trong ca chỉ nhắc đến giờ kết thúc ca; bạn có thể hoãn 10 hoặc 15 phút.")
                }
                if let source = task.sourceText, !source.isEmpty {
                    Section("Tin nhắn gốc") { Text(source).font(.subheadline).textSelection(.enabled) }
                }
                if task.deletedAt == nil {
                    Section { Button("Xóa công việc", role: .destructive) { confirmDelete = true } }
                }
                if let error = error { Section { Text(error).foregroundStyle(HopeTheme.urgent) } }
            }
            .scrollContentBackground(.hidden).background(HopeTheme.background)
            .navigationTitle("Chỉnh sửa công việc").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Xóa công việc này?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Xóa", role: .destructive) {
                    do { try TaskCommands.delete(task, context: context); onDeleted(); dismiss() }
                    catch { context.rollback(); self.error = error.localizedDescription }
                }
            } message: { Text("Bạn có thể hoàn tác hoặc khôi phục trong Tra cứu → Đã xóa.") }
            .tint(HopeTheme.accent)
        }
    }
    private func save() {
        do {
            try TaskCommands.update(task, title: title, notes: notes, priority: priority,
                dueAt: hasDeadline ? deadline : nil, reminderEnabled: reminder, leadMinutes: lead, context: context)
            onSaved(); dismiss()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}

struct TaskDeadlineLabel: View {
    let task: TaskItem
    var body: some View {
        if let deadline = task.dueAt {
            TimelineView(.periodic(from: .now, by: 60)) { clock in
                let overdue = deadline < clock.date && !task.isCompleted && task.deletedAt == nil
                Label {
                    Text((overdue ? "Quá hạn · " : "") + deadline.formatted(.dateTime.day().month().hour().minute()))
                } icon: { Image(systemName: overdue ? "exclamationmark.clock" : "clock") }
                .font(.caption).foregroundStyle(overdue ? HopeTheme.urgent : HopeTheme.secondary)
                if let snoozed = task.snoozedUntil, snoozed > clock.date, !task.isCompleted {
                    Text("Nhắc lại \(snoozed.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(HopeTheme.blue)
                }
            }
        } else if let clock = task.dueTime {
            Label(clock, systemImage: "clock").font(.caption).foregroundStyle(HopeTheme.secondary)
        }
    }
}

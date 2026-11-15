import SwiftUI
import SwiftData

@MainActor
struct TaskHistoryView: View {
    @Query(sort: \ShiftConfig.startTime, order: .reverse) private var shifts: [ShiftConfig]
    @State private var search = ""
    @State private var state = 0
    @State private var priority = ""
    @State private var shiftID = ""
    @State private var allDates = false
    @State private var from = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var to = Date()
    @State private var month = HopeCalendarMath.startOfMonth(.now)
    @State private var picking = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DisclosureGroup("Bộ lọc") {
                    VStack(spacing: 10) {
                        Picker("Trạng thái", selection: $state) {
                            Text("Tất cả").tag(0); Text("Cần làm").tag(1); Text("Hoàn thành").tag(2)
                            Text("Quá hạn").tag(3); Text("Đã xóa").tag(4)
                        }
                        Picker("Ưu tiên", selection: $priority) {
                            Text("Mọi ưu tiên").tag("")
                            ForEach(TaskPriority.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                        }
                        Picker("Ca", selection: $shiftID) {
                            Text("Mọi ca").tag("")
                            Text("Chưa gắn ca").tag("__inbox__")
                            ForEach(shifts) { shift in
                                Text("\(shift.name) · \(shift.targetDate.formatted(date: .abbreviated, time: .omitted))").tag(shift.id)
                            }
                        }
                        Toggle("Mọi ngày tạo việc", isOn: $allDates)
                        if !allDates {
                            Text("Chạm một ngày để chọn ngày bắt đầu, chạm ngày thứ hai để chọn ngày kết thúc. Chấm dưới ngày là có việc tạo hôm đó.")
                                .font(.footnote).foregroundStyle(HopeTheme.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            HistoryCalendar(month: $month, from: $from, to: $to, picking: $picking).id(month)
                            HStack {
                                Text("\(from.formatted(date: .abbreviated, time: .omitted)) – \(to.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.footnote.weight(.medium)).foregroundStyle(HopeTheme.ink)
                                Spacer()
                            }
                            HStack(spacing: 8) {
                                quickRange("Hôm nay", days: 0)
                                quickRange("7 ngày qua", days: 6)
                                quickRange("30 ngày qua", days: 29)
                            }
                        }
                    }.padding(.top, 12).font(.subheadline)
                }.padding(20).background(HopeTheme.surface)
                if state == 3 {
                    TimelineView(.periodic(from: .now, by: 60)) { clock in results(now: clock.date) }
                } else { results(now: .now) }
            }
            .navigationTitle("Tra cứu").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Tìm tên, ghi chú, tin nhắn gốc")
            .background(HopeTheme.background).tint(HopeTheme.accent)
            .onChange(of: from) { _, date in if to < date { to = date } }
        }
    }
    private func quickRange(_ title: String, days: Int) -> some View {
        Button(title) {
            let cal = Calendar.current
            to = cal.startOfDay(for: .now)
            from = cal.date(byAdding: .day, value: -days, to: to) ?? to
            month = HopeCalendarMath.startOfMonth(to)
            picking = false
        }
        .font(.footnote.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 36)
        .background(HopeTheme.surfaceMuted, in: Capsule()).foregroundStyle(HopeTheme.ink)
    }
    private func results(now: Date) -> some View {
        HistoryResults(search: TaskText.normalized(search), state: state, priority: priority, shiftID: shiftID,
            start: allDates ? .distantPast : Calendar.current.startOfDay(for: from),
            end: allDates ? .distantFuture : (Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: max(from, to))) ?? .distantFuture),
            now: now, shifts: shifts)
    }
}

@MainActor
private struct HistoryResults: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [TaskItem]
    @State private var editing: TaskItem?
    @State private var lastDeleted: TaskItem?
    @State private var viewModel = ShiftDashboardViewModel()
    let shiftNames: [String: String]
    init(search: String, state: Int, priority: String, shiftID: String, start: Date, end: Date, now: Date, shifts: [ShiftConfig]) {
        self.shiftNames = Dictionary(uniqueKeysWithValues: shifts.map { ($0.id, $0.name) })
        _tasks = Query(TaskSearchQuery.descriptor(search: search, state: state, priority: priority,
            shiftID: shiftID, start: start, end: end, now: now))
    }
    var body: some View {
        List {
            if tasks.isEmpty { ContentUnavailableView.search }
            Section("\(tasks.count) công việc") {
                ForEach(tasks) { task in
                    Button {
                        if task.deletedAt == nil { editing = task }
                        else { perform { try TaskCommands.restore(task, context: context) } }
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Label(task.title, systemImage: task.deletedAt != nil ? "trash" : (task.isCompleted ? "checkmark.circle.fill" : "circle"))
                                .font(.body).foregroundStyle(HopeTheme.ink)
                            if let notes = task.notes, !notes.isEmpty { Text(notes).font(.subheadline).foregroundStyle(HopeTheme.secondary).lineLimit(2) }
                            Text(task.shiftId.flatMap { shiftNames[$0] } ?? (task.shiftId == nil ? "Chưa gắn ca" : "Ca không còn tồn tại"))
                                .font(.caption).foregroundStyle(HopeTheme.secondary)
                            Text(task.createdAt, format: .dateTime.day().month().year().hour().minute())
                                .font(.caption).foregroundStyle(HopeTheme.secondary)
                            if let completed = task.completedAt, task.isCompleted {
                                Text("Hoàn thành \(completed.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(HopeTheme.accent)
                            }
                            TaskDeadlineLabel(task: task)
                            if task.deletedAt != nil {
                                Text("Chạm để khôi phục").font(.subheadline).foregroundStyle(HopeTheme.accent)
                            }
                        }.padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if task.deletedAt == nil {
                            Button("Chỉnh sửa", systemImage: "pencil") { editing = task }
                            Button(task.isCompleted ? "Mở lại" : "Hoàn thành", systemImage: "checkmark.circle") {
                                perform { try TaskCommands.complete(task, completed: !task.isCompleted, context: context) }
                            }
                            Button("Xóa", systemImage: "trash", role: .destructive) { remove(task) }
                        } else {
                            Button("Khôi phục", systemImage: "arrow.uturn.backward") { perform { try TaskCommands.restore(task, context: context) } }
                        }
                    }
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .sheet(item: $editing) { task in
            TaskEditorView(task: task, onSaved: { viewModel.refresh(context: context) }, onDeleted: {
                lastDeleted = task; viewModel.refresh(context: context)
            })
        }
        .safeAreaInset(edge: .bottom) {
            if let task = lastDeleted {
                HStack {
                    Text("Đã xóa công việc").font(.subheadline)
                    Spacer()
                    Button("Hoàn tác") { perform { try TaskCommands.restore(task, context: context); lastDeleted = nil } }
                }.padding(16).background(HopeTheme.surfaceMuted)
            }
        }
        .alert("Hope", isPresented: $viewModel.showAlert) { Button("Đóng", role: .cancel) {} } message: { Text(viewModel.alertMessage ?? "") }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action(); viewModel.refresh(context: context) }
        catch { context.rollback(); viewModel.report(error) }
    }
    private func remove(_ task: TaskItem) {
        do { try TaskCommands.delete(task, context: context); lastDeleted = task; viewModel.refresh(context: context) }
        catch { context.rollback(); viewModel.report(error) }
    }
}


/// Lịch chọn khoảng ngày tạo việc, có chấm ở những ngày có việc.
@MainActor
private struct HistoryCalendar: View {
    @Binding var month: Date
    @Binding var from: Date
    @Binding var to: Date
    @Binding var picking: Bool
    @Query private var tasks: [TaskItem]

    init(month: Binding<Date>, from: Binding<Date>, to: Binding<Date>, picking: Binding<Bool>) {
        _month = month; _from = from; _to = to; _picking = picking
        let range = HopeCalendarMath.visibleRange(for: month.wrappedValue)
        let start = range.start
        let end = range.end
        _tasks = Query(filter: #Predicate<TaskItem> { $0.createdAt >= start && $0.createdAt < end && $0.deletedAt == nil })
    }

    private var marks: [Date: [Color]] {
        let calendar = Calendar.current
        return Dictionary(grouping: tasks, by: { calendar.startOfDay(for: $0.createdAt) })
            .mapValues { items in [items.allSatisfy(\.isCompleted) ? HopeTheme.accent : HopeTheme.amber] }
    }

    var body: some View {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: max(from, to))
        HopeMonthCalendar(month: $month, selected: [start, end], range: start...end, marks: marks) { day in
            if !picking || day < start { from = day; to = day; picking = true }
            else { to = day; picking = false }
        }
    }
}

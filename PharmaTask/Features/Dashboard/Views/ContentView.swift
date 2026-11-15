import SwiftUI
import SwiftData

@MainActor
public struct ContentView: View {
    @Query(filter: #Predicate<ShiftConfig> { $0.isActive }, sort: \ShiftConfig.startTime, order: .reverse)
    private var activeShifts: [ShiftConfig]
    @State private var selectedTab = 0
    @State private var showingStoreProblem = SharedModelContainer.isRunningOnTemporaryStore
    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HopeDashboardView(shift: activeShifts.first, openSchedule: { selectedTab = 1 }, openGarden: { selectedTab = 3 })
            }
            .tabItem { Label("Hôm nay", systemImage: "checkmark.circle") }.tag(0)
            ShiftManagementView()
                .tabItem { Label("Lịch ca", systemImage: "calendar") }.tag(1)
            TaskHistoryView()
                .tabItem { Label("Tra cứu", systemImage: "magnifyingglass") }.tag(2)
            HealingGardenView(isActive: selectedTab == 3)
                .tabItem { Label("Hope", systemImage: "leaf") }.tag(3)
        }
        .tint(HopeTheme.accent)
        .alert("Chưa mở được dữ liệu của bạn", isPresented: $showingStoreProblem) {
            Button("Đã hiểu", role: .cancel) {}
        } message: {
            Text("Dữ liệu cũ vẫn còn nguyên trên máy, Hope chưa xoá gì. Lúc này Hope đang dùng kho tạm nên việc bạn thêm sẽ mất khi đóng app. Hãy cập nhật Hope lên bản mới nhất rồi mở lại.")
        }
    }
}

@MainActor
private struct HopeDashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Query private var tasks: [TaskItem]
    @State private var viewModel = ShiftDashboardViewModel()
    @State private var draft = ""
    @State private var showingSettings = false
    @State private var showingCompleted = false
    @State private var taskToConfirm: TaskItem?
    @State private var showingConfirmation = false
    @State private var editingTask: TaskItem?
    @State private var lastDeleted: TaskItem?
    @FocusState private var composerFocused: Bool
    let shift: ShiftConfig?
    let openSchedule: () -> Void
    let openGarden: () -> Void

    init(shift: ShiftConfig?, openSchedule: @escaping () -> Void, openGarden: @escaping () -> Void) {
        self.shift = shift
        self.openSchedule = openSchedule
        self.openGarden = openGarden
        let shiftID = shift?.id
        _tasks = Query(filter: #Predicate<TaskItem> { $0.shiftId == shiftID && $0.deletedAt == nil },
                       sort: [SortDescriptor(\TaskItem.createdAt, order: .reverse)])
    }

    var body: some View {
        let snapshot = TaskDashboardSnapshot(tasks: tasks)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                greeting
                shiftCard(snapshot)
                gardenShortcut
                if snapshot.total == 0 {
                    emptyState
                } else {
                    if !snapshot.pending.isEmpty {
                        HopeSectionHeading("Việc cần làm", count: snapshot.pending.count)
                        ForEach(snapshot.pending) { task in
                            TaskRowView(task: task) {
                                taskToConfirm = task
                                showingConfirmation = true
                            }
                            .contextMenu { taskActions(task) }
                            .accessibilityAction(named: "Chỉnh sửa") { editingTask = task }
                        }
                    } else {
                        Label("Bạn đã hoàn thành mọi việc trong ca.", systemImage: "checkmark.seal")
                            .font(.subheadline.weight(.medium)).foregroundStyle(HopeTheme.accent)
                            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(HopeTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 20))
                    }
                    if !snapshot.completed.isEmpty {
                        DisclosureGroup(isExpanded: $showingCompleted) {
                            LazyVStack(spacing: 10) {
                                ForEach(snapshot.completed) { task in
                                    TaskRowView(task: task) { viewModel.toggleTask(task, context: context) }
                                        .contextMenu { taskActions(task) }
                                }
                            }.padding(.top, 12)
                        } label: {
                            HopeSectionHeading("Đã hoàn thành", count: snapshot.completed.count)
                        }
                        .tint(HopeTheme.secondary)
                    }
                }
            }
            .padding(.horizontal, HopeTheme.pageInset)
            .padding(.top, 20).padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(HopeTheme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(HopeTheme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 9) {
                    HopeBrandMark(size: 30)
                    Text("Hope").font(.headline).foregroundStyle(HopeTheme.ink)
                }.accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.body.weight(.medium))
                        .frame(width: 44, height: 44).foregroundStyle(HopeTheme.ink)
                }.accessibilityLabel("Cài đặt")
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(item: $editingTask) { task in
            TaskEditorView(task: task, onSaved: { viewModel.refresh(context: context) }, onDeleted: {
                lastDeleted = task; viewModel.refresh(context: context)
            })
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let task = lastDeleted {
                HStack {
                    Text("Đã xóa công việc").font(.subheadline)
                    Spacer()
                    Button("Hoàn tác") {
                        do { try TaskCommands.restore(task, context: context); lastDeleted = nil; viewModel.refresh(context: context) }
                        catch { context.rollback(); viewModel.report(error) }
                    }
                    Button { lastDeleted = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Đóng thông báo")
                }.padding(.horizontal, 20).background(HopeTheme.surfaceMuted)
            }
        }
        .confirmationDialog("Hoàn thành công việc?", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("Xác nhận hoàn thành") {
                if let task = taskToConfirm { viewModel.toggleTask(task, context: context) }
                taskToConfirm = nil
            }
            Button("Để sau", role: .cancel) { taskToConfirm = nil }
        } message: { Text(taskToConfirm?.title ?? "") }
        .alert("Hope", isPresented: $viewModel.showAlert) {
            Button("Đóng", role: .cancel) {}
        } message: { Text(viewModel.alertMessage ?? "") }
        .task(id: shift?.id) { refreshIfRunning() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshIfRunning() } }
        .onChange(of: shift?.id) { _, _ in
            showingConfirmation = false
            taskToConfirm = nil
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showingCompleted)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline).foregroundStyle(HopeTheme.secondary)
            Text("Hôm nay của bạn.")
                .font(.largeTitle.weight(.semibold)).tracking(-0.7)
                .foregroundStyle(HopeTheme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shiftCard(_ snapshot: TaskDashboardSnapshot) -> some View {
        Button(action: openSchedule) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(shift == nil ? "SẴN SÀNG CHO CA MỚI" : "CA ĐANG TRỰC")
                            .font(.caption.weight(.semibold)).tracking(1.2)
                            .foregroundStyle(HopeTheme.mint)
                        Text(shift?.name ?? "Chọn ca của bạn")
                            .font(.title2.weight(.semibold)).foregroundStyle(HopeTheme.onHero)
                            .fixedSize(horizontal: false, vertical: true)
                        if let shift = shift {
                            Label {
                                Text("Tan ca \(shift.endTime.formatted(date: .omitted, time: .shortened))")
                            } icon: { Image(systemName: "clock") }
                            .font(.subheadline).foregroundStyle(HopeTheme.onHero.opacity(0.85))
                        } else {
                            Text("Xem lịch và bắt đầu ca trực.")
                                .font(.subheadline).foregroundStyle(HopeTheme.onHero.opacity(0.85))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if !typeSize.isAccessibilitySize { HopeIllustration("HopeShift", width: 92) }
                }
                if snapshot.total > 0 {
                    ProgressView(value: snapshot.progress).tint(HopeTheme.mint)
                        .accessibilityLabel("Tiến độ ca")
                        .accessibilityValue("\(snapshot.completed.count) trên \(snapshot.total) việc")
                    ViewThatFits(in: .horizontal) {
                        HStack { progressText(snapshot); Spacer(); remainingText(snapshot) }
                        VStack(alignment: .leading, spacing: 6) { progressText(snapshot); remainingText(snapshot) }
                    }
                } else {
                    Label("Xem lịch ca", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(HopeTheme.onHero)
                }
            }
            .padding(22)
            .background(HopeTheme.hero, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 28))
        }.buttonStyle(.plain).accessibilityHint("Mở lịch ca trực")
    }

    private func progressText(_ snapshot: TaskDashboardSnapshot) -> some View {
        Text("\(snapshot.completed.count)/\(snapshot.total) việc hoàn thành")
            .font(.caption.weight(.medium)).foregroundStyle(HopeTheme.onHero)
    }

    private func remainingText(_ snapshot: TaskDashboardSnapshot) -> some View {
        Text(snapshot.urgentCount > 0 ? "\(snapshot.urgentCount) việc ưu tiên" : "Cứ từng việc một")
            .font(.caption).foregroundStyle(HopeTheme.mint)
    }

    private var gardenShortcut: some View {
        Button { composerFocused = false; openGarden() } label: {
            HStack(spacing: 14) {
                Image(systemName: "leaf").font(.title2)
                    .frame(width: 44, height: 44).foregroundStyle(HopeTheme.accent)
                    .background(HopeTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nghỉ một chút").font(.headline).foregroundStyle(HopeTheme.ink)
                    Text("Ghé khu vườn Hope, vài phút cho riêng bạn.")
                        .font(.subheadline).foregroundStyle(HopeTheme.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize {
                    Image(systemName: "arrow.up.right").font(.body).foregroundStyle(HopeTheme.accent)
                }
            }
            .padding(16).background(HopeTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 22))
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Mở tab Vườn để nghỉ ngơi")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            HopeIllustration("HopeInbox", width: 150)
            Text("Để đầu óc nhẹ hơn.").font(.title3.weight(.semibold)).foregroundStyle(HopeTheme.ink)
            Text("Thêm việc ở khung bên dưới để bắt đầu.")
                .font(.subheadline).foregroundStyle(HopeTheme.secondary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 12).frame(maxWidth: .infinity)
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField("Thêm một việc cần làm…", text: $draft, axis: .vertical)
                .font(.body).foregroundStyle(HopeTheme.ink).lineLimit(1...4)
                .focused($composerFocused).submitLabel(.done).onSubmit(addTask)
                .accessibilityLabel("Tên công việc mới")
            Button(action: addTask) {
                Image(systemName: "plus").font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48).foregroundStyle(HopeTheme.onAccent)
                    .background(HopeTheme.accent, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            .accessibilityLabel("Thêm công việc")
        }
        .padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 8)
        .background(HopeTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(HopeTheme.border, lineWidth: 1))
        .padding(.horizontal, HopeTheme.pageInset).padding(.vertical, 10)
        .background(HopeTheme.background)
    }

    private func addTask() {
        if viewModel.addTask(title: draft, context: context) { draft = "" }
    }

    private func refreshIfRunning() {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            viewModel.refresh(context: context, startActivity: true)
            let defaults = UserDefaults(suiteName: SharedModelContainer.appGroupID)
            if let message = defaults?.string(forKey: "hope.notificationActionError") {
                defaults?.removeObject(forKey: "hope.notificationActionError")
                viewModel.report(HopeDataError.invalid(message))
            }
        }
    }

    @ViewBuilder private func taskActions(_ task: TaskItem) -> some View {
        Button("Chỉnh sửa", systemImage: "pencil") { editingTask = task }
        if task.dueAt != nil && !task.isCompleted && task.reminderEnabled {
            ForEach([10, 15], id: \.self) { minutes in
                Button("Nhắc sau \(minutes) phút", systemImage: "clock.arrow.circlepath") {
                    do { try TaskCommands.snooze(task, minutes: minutes, shift: shift, context: context); viewModel.refresh(context: context) }
                    catch { context.rollback(); viewModel.report(error) }
                }
            }
        }
        Button("Xóa", systemImage: "trash", role: .destructive) {
            do { try TaskCommands.delete(task, context: context); lastDeleted = task; viewModel.refresh(context: context) }
            catch { context.rollback(); viewModel.report(error) }
        }
    }
}

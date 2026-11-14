import SwiftUI
import SwiftData

@MainActor
public struct ShiftManagementView: View {
    @State private var weekOffset = 0
    public init() {}
    public var body: some View {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let base = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: base) ?? base
        return NavigationStack {
            HopeWeekView(weekStart: start, moveWeek: { weekOffset += $0 })
                .id(start)
        }
    }
}

@MainActor
private struct HopeWeekView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var shifts: [ShiftConfig]
    @State private var selectedDate: Date
    @State private var showingEditor = false
    @State private var editingShift: ShiftConfig?
    @State private var endingShift: ShiftConfig?
    @State private var confirmEnd = false
    @State private var viewModel = ShiftDashboardViewModel()
    @State private var formName = ""
    @State private var formStart = Date()
    @State private var formEnd = Date()
    @State private var formNotes = ""
    @State private var formColor = "teal"
    @State private var formRoutineType = RoutineType.morning
    @State private var formError: String?
    let weekStart: Date
    let moveWeek: (Int) -> Void

    init(weekStart: Date, moveWeek: @escaping (Int) -> Void) {
        self.weekStart = weekStart
        self.moveWeek = moveWeek
        let end = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        _shifts = Query(filter: #Predicate<ShiftConfig> { $0.targetDate >= weekStart && $0.targetDate < end },
                        sort: [SortDescriptor(\ShiftConfig.startTime)])
        _selectedDate = State(initialValue: Date.now >= weekStart && Date.now < end ? .now : weekStart)
    }

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }
    private var workingShifts: [ShiftConfig] { shifts.filter { !$0.name.lowercased().contains("nghỉ") } }
    private var dailyShifts: [ShiftConfig] {
        shifts.filter { Calendar.current.isDate($0.targetDate, inSameDayAs: selectedDate) }
    }
    private var hours: Double { workingShifts.reduce(0) { $0 + $1.durationHours } }
    private var freeDays: Int {
        days.filter { day in !workingShifts.contains { Calendar.current.isDate($0.targetDate, inSameDayAs: day) } }.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tuần của bạn.").font(.largeTitle.weight(.semibold)).tracking(-0.7)
                        .foregroundStyle(HopeTheme.ink)
                    Text("Sắp xếp ca trực, chủ động mỗi ngày.")
                        .font(.subheadline).foregroundStyle(HopeTheme.secondary)
                }
                calendarCard
                statistics
                HopeSectionHeading(Calendar.current.isDateInToday(selectedDate) ? "Ca trực hôm nay" : "Ca trực trong ngày", count: dailyShifts.count)
                if dailyShifts.isEmpty { emptyDay }
                ForEach(dailyShifts) { shift in shiftCard(shift) }
            }
            .padding(.horizontal, HopeTheme.pageInset).padding(.top, 20).padding(.bottom, 32)
        }
        .background(HopeTheme.background)
        .navigationTitle("Lịch ca").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(HopeTheme.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { openEditor(nil) } label: {
                    Image(systemName: "plus").font(.title3.weight(.medium))
                        .frame(width: 44, height: 44).foregroundStyle(HopeTheme.accent)
                }.accessibilityLabel("Thêm ca trực vào ngày đang chọn")
            }
        }
        .sheet(isPresented: $showingEditor) { editor }
        .alert("Hope", isPresented: $viewModel.showAlert) {
            Button("Đóng", role: .cancel) {}
        } message: { Text(viewModel.alertMessage ?? "") }
        .confirmationDialog("Kết thúc ca trực?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Kết thúc ca", role: .destructive) {
                viewModel.endShift(currentShift: endingShift, context: context)
                endingShift = nil
            }
            Button("Tiếp tục làm", role: .cancel) { endingShift = nil }
        } message: { Text("Công việc của ca vẫn được giữ trong dữ liệu trên thiết bị.") }
        .task { seedIfNeeded() }
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Button { moveWeek(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }.accessibilityLabel("Tuần trước")
                Spacer(minLength: 0)
                VStack(spacing: 3) {
                    Text(weekStart, format: .dateTime.month(.wide).year())
                        .font(.headline).foregroundStyle(HopeTheme.ink)
                    if let end = days.last {
                        Text("\(weekStart.formatted(.dateTime.day().month())) – \(end.formatted(.dateTime.day().month()))")
                            .font(.caption).foregroundStyle(HopeTheme.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button { moveWeek(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }.accessibilityLabel("Tuần sau")
            }.tint(HopeTheme.accent)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(days, id: \.self) { day in dayButton(day) }
                }
            }
            Text(selectedDate, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline).foregroundStyle(HopeTheme.secondary)
        }.hopeCard()
    }

    private func dayButton(_ date: Date) -> some View {
        let selected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let hasShift = shifts.contains { Calendar.current.isDate($0.targetDate, inSameDayAs: date) }
        let weekday = Calendar.current.component(.weekday, from: date)
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { selectedDate = date }
        } label: {
            VStack(spacing: 10) {
                Text(weekday == 1 ? "CN" : "T\(weekday)").font(.caption.weight(.medium))
                Text(date, format: .dateTime.day()).font(.headline.monospacedDigit())
                Circle().fill(hasShift ? (selected ? HopeTheme.mint : HopeTheme.accent) : .clear)
                    .frame(width: 4, height: 4)
            }
            .padding(.vertical, 12).frame(minWidth: 44)
            .foregroundStyle(selected ? HopeTheme.onAccent : HopeTheme.ink)
            .background(selected ? HopeTheme.accent : HopeTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .fixedSize(horizontal: true, vertical: false)
        }.buttonStyle(.plain)
            .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
            .accessibilityValue(selected ? "Đang chọn" : (hasShift ? "Có ca trực" : "Chưa có ca"))
    }

    private var statistics: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            stat(hours.formatted(.number.precision(.fractionLength(0...1))) + "h", title: "Giờ làm", symbol: "clock", color: HopeTheme.accent)
            stat(workingShifts.count.formatted(), title: "Ca trực", symbol: "calendar", color: HopeTheme.amber)
            stat(freeDays.formatted(), title: "Chưa có ca", symbol: "leaf", color: HopeTheme.blue)
        }
    }

    private func stat(_ value: String, title: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.body).foregroundStyle(color).accessibilityHidden(true)
            Text(value).font(.title2.weight(.semibold)).foregroundStyle(HopeTheme.ink)
            Text(title).font(.caption).foregroundStyle(HopeTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(HopeTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private func shiftCard(_ shift: ShiftConfig) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: HopeTheme.shiftSymbol(shift.name)).font(.title2)
                    .foregroundStyle(HopeTheme.shiftColor(shift.colorTag))
                    .frame(width: 48, height: 48).background(HopeTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(shift.name).font(.title3.weight(.semibold)).foregroundStyle(HopeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(shift.startTime.formatted(date: .omitted, time: .shortened)) – \(shift.endTime.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(HopeTheme.secondary)
                    if !Calendar.current.isDate(shift.startTime, inSameDayAs: shift.endTime) {
                        Text("Kết thúc vào ngày hôm sau").font(.caption).foregroundStyle(HopeTheme.amber)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button("Chỉnh sửa ca", systemImage: "pencil") { openEditor(shift) }
                    if shift.isActive {
                        Button("Kết thúc ca", systemImage: "stop.circle", role: .destructive) {
                            endingShift = shift; confirmEnd = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44).foregroundStyle(HopeTheme.secondary)
                }.accessibilityLabel("Tùy chọn \(shift.name)")
            }
            if !shift.notes.isEmpty {
                Text(shift.notes).font(.subheadline).foregroundStyle(HopeTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if shift.isActive {
                Label("Đang trực", systemImage: "circle.inset.filled")
                    .font(.subheadline.weight(.medium)).foregroundStyle(HopeTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(HopeTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12))
            } else if !shift.name.lowercased().contains("nghỉ") {
                Button { viewModel.activateShift(shift, context: context) } label: {
                    Label("Bắt đầu ca", systemImage: "play.fill")
                }.buttonStyle(HopePrimaryButtonStyle())
            }
        }.hopeCard()
    }

    private var emptyDay: some View {
        VStack(spacing: 14) {
            HopeIllustration("HopeShift", width: 150)
            Text("Một khoảng trống cho bạn.").font(.title3.weight(.semibold)).foregroundStyle(HopeTheme.ink)
            Text("Ngày này chưa có ca trực. Bạn có thể thêm ca mới khi đã có lịch.")
                .font(.subheadline).foregroundStyle(HopeTheme.secondary).multilineTextAlignment(.center)
            Button("Thêm ca trực") { openEditor(nil) }.buttonStyle(HopePrimaryButtonStyle())
        }.hopeCard()
    }

    private var editor: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tên ca trực", text: $formName).textInputAutocapitalization(.sentences)
                    LabeledContent("Ngày", value: (editingShift?.targetDate ?? selectedDate).formatted(date: .abbreviated, time: .omitted))
                    Picker("Checklist theo loại ca", selection: $formRoutineType) {
                        ForEach(RoutineType.allCases) { Text($0.title).tag($0) }
                    }
                } header: { Text("Ca của bạn") }
                Section {
                    DatePicker("Bắt đầu", selection: $formStart, displayedComponents: .hourAndMinute)
                    DatePicker("Kết thúc", selection: $formEnd, displayedComponents: .hourAndMinute)
                } header: { Text("Thời gian") } footer: { Text("Giờ kết thúc sớm hơn giờ bắt đầu được tính là ca qua đêm.") }
                Section("Điều cần nhớ") {
                    TextField("Điều cần nhớ cho ca này…", text: $formNotes, axis: .vertical).lineLimit(3...8)
                    Picker("Màu đánh dấu", selection: $formColor) {
                        Text("Xanh lá").tag("teal")
                        Text("Màu mơ").tag("amber")
                        Text("Xanh trời").tag("blue")
                        Text("Hồng đất").tag("rose")
                        Text("Tím").tag("purple")
                    }
                }
                if let error = formError {
                    Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(HopeTheme.urgent) }
                }
            }
            .scrollContentBackground(.hidden).background(HopeTheme.background)
            .navigationTitle(editingShift == nil ? "Thêm ca trực" : "Chỉnh sửa ca")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { showingEditor = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu", action: saveShift).fontWeight(.semibold)
                        .disabled(formName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .tint(HopeTheme.accent)
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }

    private func openEditor(_ shift: ShiftConfig?) {
        editingShift = shift
        formName = shift?.name ?? ""
        formNotes = shift?.notes ?? ""
        formColor = shift?.colorTag ?? "teal"
        formRoutineType = shift?.routineType ?? .morning
        formStart = shift?.startTime ?? Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        formEnd = shift?.endTime ?? Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        formError = nil
        showingEditor = true
    }

    private func saveShift() {
        let name = formName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let calendar = Calendar.current
        let date = editingShift?.targetDate ?? selectedDate
        let startParts = calendar.dateComponents([.hour, .minute], from: formStart)
        let endParts = calendar.dateComponents([.hour, .minute], from: formEnd)
        guard let start = calendar.date(bySettingHour: startParts.hour ?? 0, minute: startParts.minute ?? 0, second: 0, of: date),
              var end = calendar.date(bySettingHour: endParts.hour ?? 0, minute: endParts.minute ?? 0, second: 0, of: date) else { return }
        if start == end && !name.lowercased().contains("nghỉ") {
            formError = "Giờ bắt đầu và kết thúc phải khác nhau."
            return
        }
        if end < start { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
        if let shift = editingShift {
            shift.name = name; shift.startTime = start; shift.endTime = end
            shift.colorTag = formColor; shift.notes = formNotes
            shift.routineType = formRoutineType; shift.updatedAt = .now
        } else {
            let shift = ShiftConfig(name: name, startTime: start, endTime: end, isActive: false,
                                    targetDate: selectedDate, pharmacistName: "Tôi", colorTag: formColor, notes: formNotes)
            shift.routineType = formRoutineType
            context.insert(shift)
        }
        do {
            try context.save()
            showingEditor = false
            viewModel.refresh(context: context, startActivity: true)
        } catch { context.rollback(); formError = error.localizedDescription }
    }

    private func seedIfNeeded() {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        do {
            // Check the whole store, not only the currently visible week.
            if try context.fetchCount(FetchDescriptor<ShiftConfig>()) == 0 {
                for shift in ShiftConfig.defaultShifts() { context.insert(shift) }
                try context.save()
            }
        } catch { context.rollback(); viewModel.report(error) }
    }
}

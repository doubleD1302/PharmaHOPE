import SwiftUI
import SwiftData

/// Phép tính khi lặp một ca sang ngày khác, tách riêng để kiểm thử.
enum ShiftRepeat {
    /// Giữ nguyên giờ và phút của ca, chuyển sang ngày mới. Ca qua đêm (kết thúc sớm hơn bắt đầu) kết thúc vào hôm sau.
    static func rebased(start: Date, end: Date, to day: Date, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        let s = calendar.dateComponents([.hour, .minute], from: start)
        let e = calendar.dateComponents([.hour, .minute], from: end)
        guard let newStart = calendar.date(bySettingHour: s.hour ?? 0, minute: s.minute ?? 0, second: 0, of: day),
              var newEnd = calendar.date(bySettingHour: e.hour ?? 0, minute: e.minute ?? 0, second: 0, of: day) else { return nil }
        if newEnd < newStart { newEnd = calendar.date(byAdding: .day, value: 1, to: newEnd) ?? newEnd }
        return (newStart, newEnd)
    }

    /// Các ngày cần tạo: mỗi tuần trong `weeks` tuần kể từ tuần của ca nguồn, ở các thứ đã chọn (0 = thứ Hai), sau ngày nguồn.
    static func targetDays(from source: Date, weekdays: Set<Int>, weeks: Int, calendar: Calendar = .current) -> [Date] {
        var cal = calendar
        cal.firstWeekday = 2
        let sourceDay = cal.startOfDay(for: source)
        guard let monday = cal.dateInterval(of: .weekOfYear, for: sourceDay)?.start else { return [] }
        var days: [Date] = []
        for week in 0..<max(0, min(weeks, 12)) {
            for weekday in weekdays.sorted() where (0..<7).contains(weekday) {
                if let day = cal.date(byAdding: .day, value: week * 7 + weekday, to: monday), day > sourceDay { days.append(day) }
            }
        }
        return days
    }
}

@MainActor
public struct ShiftManagementView: View {
    @State private var month = HopeCalendarMath.startOfMonth(.now)
    public init() {}
    public var body: some View {
        NavigationStack {
            HopeMonthView(month: $month).id(month)
        }
    }
}

@MainActor
private struct HopeMonthView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var shifts: [ShiftConfig]
    @State private var selectedDate: Date
    @State private var showingEditor = false
    @State private var editingShift: ShiftConfig?
    @State private var endingShift: ShiftConfig?
    @State private var confirmEnd = false
    @State private var viewModel = ShiftDashboardViewModel()
    @State private var formName = ""
    @State private var formDate = Date()
    @State private var formStart = Date()
    @State private var formEnd = Date()
    @State private var formNotes = ""
    @State private var formColor = "teal"
    @State private var formRoutineType = RoutineType.morning
    @State private var formError: String?
    @State private var repeatingShift: ShiftConfig?
    @State private var repeatWeekdays: Set<Int> = []
    @State private var repeatWeeks = 4
    @Binding var month: Date

    init(month: Binding<Date>) {
        _month = month
        let range = HopeCalendarMath.visibleRange(for: month.wrappedValue)
        let start = range.start
        let end = range.end
        _shifts = Query(filter: #Predicate<ShiftConfig> { $0.targetDate >= start && $0.targetDate < end },
                        sort: [SortDescriptor(\ShiftConfig.startTime)])
        let inMonth = Calendar.current.isDate(.now, equalTo: month.wrappedValue, toGranularity: .month)
        _selectedDate = State(initialValue: inMonth ? .now : month.wrappedValue)
    }

    private var calendar: Calendar { Calendar.current }
    private var monthShifts: [ShiftConfig] { shifts.filter { calendar.isDate($0.targetDate, equalTo: month, toGranularity: .month) } }
    private var workingShifts: [ShiftConfig] { monthShifts.filter { !$0.name.lowercased().contains("nghỉ") } }
    private var dailyShifts: [ShiftConfig] { shifts.filter { calendar.isDate($0.targetDate, inSameDayAs: selectedDate) } }
    private var hours: Double { workingShifts.reduce(0) { $0 + $1.durationHours } }
    private var freeDays: Int {
        let total = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let worked = Set(workingShifts.map { calendar.startOfDay(for: $0.targetDate) }).count
        return max(0, total - worked)
    }
    private var marks: [Date: [Color]] {
        Dictionary(grouping: shifts, by: { calendar.startOfDay(for: $0.targetDate) })
            .mapValues { $0.map { HopeTheme.shiftColor($0.colorTag) } }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lịch của bạn.").font(.largeTitle.weight(.semibold)).tracking(-0.7)
                        .foregroundStyle(HopeTheme.ink)
                    Text("Chạm một ngày để xem và chỉnh ca của ngày đó.")
                        .font(.subheadline).foregroundStyle(HopeTheme.secondary)
                }
                calendarCard
                statistics
                HopeSectionHeading(calendar.isDateInToday(selectedDate) ? "Ca trực hôm nay" : "Ca trực trong ngày", count: dailyShifts.count)
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
        .sheet(item: $repeatingShift) { shift in repeatSheet(shift) }
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
        VStack(alignment: .leading, spacing: 12) {
            HopeMonthCalendar(month: $month, selected: [calendar.startOfDay(for: selectedDate)], marks: marks) { day in
                selectedDate = day
            }
            HStack {
                Text(selectedDate, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline).foregroundStyle(HopeTheme.secondary)
                Spacer()
                Button("Hôm nay") {
                    selectedDate = .now
                    month = HopeCalendarMath.startOfMonth(.now)
                }.font(.subheadline.weight(.semibold)).tint(HopeTheme.accent)
            }
        }.hopeCard()
    }

    private var statistics: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            stat(hours.formatted(.number.precision(.fractionLength(0...1))) + "h", title: "Giờ làm trong tháng", symbol: "clock", color: HopeTheme.accent)
            stat(workingShifts.count.formatted(), title: "Ca trực", symbol: "calendar", color: HopeTheme.amber)
            stat(freeDays.formatted(), title: "Ngày chưa có ca", symbol: "leaf", color: HopeTheme.blue)
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
                    if !calendar.isDate(shift.startTime, inSameDayAs: shift.endTime) {
                        Text("Kết thúc vào ngày hôm sau").font(.caption).foregroundStyle(HopeTheme.amber)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button("Chỉnh sửa ca", systemImage: "pencil") { openEditor(shift) }
                    Button("Lặp lại ca…", systemImage: "repeat") { openRepeat(shift) }
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
                    DatePicker("Ngày", selection: $formDate, displayedComponents: .date)
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

    private func repeatSheet(_ shift: ShiftConfig) -> some View {
        let names = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]
        return NavigationStack {
            Form {
                Section {
                    LabeledContent("Ca", value: shift.name)
                    LabeledContent("Giờ", value: "\(shift.startTime.formatted(date: .omitted, time: .shortened)) – \(shift.endTime.formatted(date: .omitted, time: .shortened))")
                    LabeledContent("Từ ngày", value: shift.targetDate.formatted(date: .abbreviated, time: .omitted))
                }
                Section {
                    HStack(spacing: 6) {
                        ForEach(names.indices, id: \.self) { index in
                            let on = repeatWeekdays.contains(index)
                            Button {
                                if on { repeatWeekdays.remove(index) } else { repeatWeekdays.insert(index) }
                            } label: {
                                Text(names[index]).font(.subheadline.weight(on ? .semibold : .regular))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(on ? HopeTheme.onAccent : HopeTheme.ink)
                                    .background(on ? HopeTheme.accent : HopeTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    Stepper("Số tuần: \(repeatWeeks)", value: $repeatWeeks, in: 1...8)
                } header: { Text("Lặp vào các thứ") } footer: {
                    Text("Những ngày đã có ca cùng tên và giờ sẽ được bỏ qua.")
                }
            }
            .scrollContentBackground(.hidden).background(HopeTheme.background)
            .navigationTitle("Lặp lại ca").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { repeatingShift = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tạo ca") { applyRepeat(shift) }.fontWeight(.semibold).disabled(repeatWeekdays.isEmpty)
                }
            }
            .tint(HopeTheme.accent)
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    private func openRepeat(_ shift: ShiftConfig) {
        let weekday = calendar.component(.weekday, from: shift.targetDate)   // 1 = Chủ nhật
        repeatWeekdays = [(weekday + 5) % 7]
        repeatWeeks = 4
        repeatingShift = shift
    }

    private func applyRepeat(_ source: ShiftConfig) {
        var created = 0
        for day in ShiftRepeat.targetDays(from: source.targetDate, weekdays: repeatWeekdays, weeks: repeatWeeks) {
            guard let times = ShiftRepeat.rebased(start: source.startTime, end: source.endTime, to: day) else { continue }
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let sameDay = (try? context.fetch(FetchDescriptor<ShiftConfig>(
                predicate: #Predicate { $0.targetDate >= day && $0.targetDate < next }))) ?? []
            if sameDay.contains(where: { $0.name == source.name && $0.startTime == times.start && $0.endTime == times.end }) { continue }
            let copy = ShiftConfig(name: source.name, startTime: times.start, endTime: times.end, isActive: false,
                                   targetDate: day, pharmacistName: source.pharmacistName, colorTag: source.colorTag, notes: source.notes)
            copy.routineType = source.routineType
            context.insert(copy)
            created += 1
        }
        do {
            try context.save()
            repeatingShift = nil
            viewModel.refresh(context: context, startActivity: true)
            if created == 0 { viewModel.alertMessage = "Không có ngày nào cần tạo thêm."; viewModel.showAlert = true }
        } catch { context.rollback(); viewModel.report(error) }
    }

    private func openEditor(_ shift: ShiftConfig?) {
        editingShift = shift
        formName = shift?.name ?? ""
        formDate = shift?.targetDate ?? selectedDate
        formNotes = shift?.notes ?? ""
        formColor = shift?.colorTag ?? "teal"
        formRoutineType = shift?.routineType ?? .morning
        formStart = shift?.startTime ?? calendar.date(bySettingHour: 6, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        formEnd = shift?.endTime ?? calendar.date(bySettingHour: 14, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        formError = nil
        showingEditor = true
    }

    private func saveShift() {
        let name = formName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let date = calendar.startOfDay(for: formDate)
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
            shift.name = name; shift.startTime = start; shift.endTime = end; shift.targetDate = date
            shift.colorTag = formColor; shift.notes = formNotes
            shift.routineType = formRoutineType; shift.updatedAt = .now
        } else {
            let shift = ShiftConfig(name: name, startTime: start, endTime: end, isActive: false,
                                    targetDate: date, pharmacistName: "Tôi", colorTag: formColor, notes: formNotes)
            shift.routineType = formRoutineType
            context.insert(shift)
        }
        do {
            try context.save()
            showingEditor = false
            viewModel.refresh(context: context, startActivity: true)
            selectedDate = date
            if !calendar.isDate(date, equalTo: month, toGranularity: .month) { month = HopeCalendarMath.startOfMonth(date) }
        } catch { context.rollback(); formError = error.localizedDescription }
    }

    private func seedIfNeeded() {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        do {
            // Check the whole store, not only the currently visible month.
            if try context.fetchCount(FetchDescriptor<ShiftConfig>()) == 0 {
                for shift in ShiftConfig.defaultShifts() { context.insert(shift) }
                try context.save()
            }
        } catch { context.rollback(); viewModel.report(error) }
    }
}

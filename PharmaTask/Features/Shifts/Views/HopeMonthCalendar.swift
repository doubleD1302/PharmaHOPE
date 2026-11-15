import SwiftUI

/// Phép tính lịch tháng, tách riêng để kiểm thử.
enum HopeCalendarMath {
    /// 42 ngày (6 tuần) hiển thị cho tháng chứa `month`, tuần bắt đầu từ thứ Hai.
    static func grid(for month: Date, calendar: Calendar = .current) -> [Date] {
        var cal = calendar
        cal.firstWeekday = 2
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) else { return [] }
        let weekday = cal.component(.weekday, from: first)      // 1 = Chủ nhật
        let lead = (weekday + 5) % 7                             // số ngày từ thứ Hai tới ngày mùng 1
        guard let start = cal.date(byAdding: .day, value: -lead, to: first) else { return [] }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    /// Khoảng thời gian [ngày đầu lưới, ngày sau cuối lưới) để truy vấn dữ liệu dùng cho chấm đánh dấu.
    static func visibleRange(for month: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let days = grid(for: month, calendar: calendar)
        let start = calendar.startOfDay(for: days.first ?? month)
        let end = calendar.date(byAdding: .day, value: 1, to: days.last ?? month).map { calendar.startOfDay(for: $0) } ?? start
        return (start, end)
    }

    static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    static func shiftMonth(_ month: Date, by value: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: value, to: startOfMonth(month, calendar: calendar)) ?? month
    }
}

/// Lịch tháng dùng chung cho Lịch ca và Tra cứu. Mỗi ô là một nút cao ít nhất 44 điểm.
struct HopeMonthCalendar: View {
    @Binding var month: Date
    /// Các ngày đang được chọn (đầu ngày).
    var selected: Set<Date> = []
    /// Khoảng ngày được tô nhạt (dùng cho chọn khoảng).
    var range: ClosedRange<Date>?
    /// Chấm đánh dấu theo ngày (khóa là đầu ngày).
    var marks: [Date: [Color]] = [:]
    var onPick: (Date) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let weekdayNames = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]

    var body: some View {
        let calendar = Calendar.current
        let days = HopeCalendarMath.grid(for: month, calendar: calendar)
        VStack(spacing: 8) {
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Tháng trước")
                Spacer(minLength: 0)
                Text(month, format: .dateTime.month(.wide).year()).font(.headline).foregroundStyle(HopeTheme.ink)
                Spacer(minLength: 0)
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Tháng sau")
            }.tint(HopeTheme.accent)
            HStack(spacing: 0) {
                ForEach(weekdayNames, id: \.self) { name in
                    Text(name).font(.caption).foregroundStyle(HopeTheme.secondary).frame(maxWidth: .infinity)
                }
            }.accessibilityHidden(true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(days, id: \.self) { day in cell(day, calendar: calendar) }
            }
        }
    }

    private func move(_ value: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            month = HopeCalendarMath.shiftMonth(month, by: value)
        }
    }

    private func cell(_ day: Date, calendar: Calendar) -> some View {
        let key = calendar.startOfDay(for: day)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let isSelected = selected.contains(key)
        let inRange = range.map { $0.contains(key) } ?? false
        let isToday = calendar.isDateInToday(day)
        let dots = marks[key] ?? []
        return Button { onPick(key) } label: {
            VStack(spacing: 3) {
                Text(day, format: .dateTime.day()).font(.callout.monospacedDigit().weight(isSelected ? .bold : .regular))
                HStack(spacing: 3) {
                    ForEach(Array(dots.prefix(3).enumerated()), id: \.offset) { _, color in
                        Circle().fill(isSelected ? HopeTheme.onAccent : color).frame(width: 5, height: 5)
                    }
                }.frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(isSelected ? HopeTheme.onAccent : (inMonth ? HopeTheme.ink : HopeTheme.secondary.opacity(0.55)))
            .background(isSelected ? HopeTheme.accent : (inRange ? HopeTheme.surfaceMuted : Color.clear),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isToday && !isSelected ? HopeTheme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue([isSelected ? "Đang chọn" : nil, dots.isEmpty ? nil : "Có dữ liệu"].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

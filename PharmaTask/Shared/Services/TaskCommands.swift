import Foundation
import SwiftData

public enum HopeDataError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

public enum TaskText {
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .lowercased(with: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "d")
    }
    public static func validTime(_ value: String) -> Bool {
        value.range(of: "^([01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil
    }
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
    public static func deadline(_ clock: String?, shift: ShiftConfig?, fallback: Date, calendar: Calendar = .current) -> Date? {
        guard let clock = clock, validTime(clock) else { return nil }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard var date = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: shift?.startTime ?? fallback) else { return nil }
        if let shift = shift, !calendar.isDate(shift.startTime, inSameDayAs: shift.endTime), date < shift.startTime {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }
}

@MainActor
public enum TaskCommands {
    public static func update(_ task: TaskItem, title: String, notes: String, priority: TaskPriority,
                              dueAt: Date?, reminderEnabled: Bool, leadMinutes: Int, context: ModelContext) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 500, notes.count <= 20_000 else { throw HopeDataError.invalid("Nhập tên việc từ 1 đến 500 ký tự và ghi chú tối đa 20.000 ký tự.") }
        guard [0, 5, 10, 15, 30, 60].contains(leadMinutes) else { throw HopeDataError.invalid("Khoảng nhắc trước không hợp lệ.") }
        task.title = title; task.notes = notes; task.priority = priority
        task.dueAt = dueAt; task.dueTime = dueAt.map { TaskText.clock($0) }
        task.reminderEnabled = reminderEnabled; task.reminderLeadMinutes = leadMinutes
        task.snoozedUntil = nil; task.updatedAt = .now; task.rebuildSearchText()
        try context.save()
    }
    public static func complete(_ task: TaskItem, completed: Bool, context: ModelContext) throws {
        guard task.deletedAt == nil else { return }
        if task.isCompleted != completed {
            task.isCompleted = completed; task.completedAt = completed ? .now : nil
            task.snoozedUntil = nil; task.updatedAt = .now
        }
        try context.save()
    }
    public static func delete(_ task: TaskItem, context: ModelContext) throws {
        task.deletedAt = .now; task.updatedAt = .now; task.snoozedUntil = nil
        try context.save()
    }
    public static func restore(_ task: TaskItem, context: ModelContext) throws {
        task.deletedAt = nil; task.updatedAt = .now
        try context.save()
    }
    public static func snooze(_ task: TaskItem, minutes: Int, shift: ShiftConfig?, context: ModelContext, now: Date = .now) throws {
        guard [10, 15].contains(minutes), !task.isCompleted, task.deletedAt == nil,
              task.reminderEnabled, task.dueAt != nil else { throw HopeDataError.invalid("Chỉ hoãn nhắc cho việc đang chờ và đã bật nhắc theo hạn.") }
        let date = now.addingTimeInterval(Double(minutes) * 60)
        if task.shiftId != nil && shift == nil { throw HopeDataError.invalid("Ca của công việc không còn tồn tại.") }
        if let shift = shift, shift.id != task.shiftId || !shift.isActive || date >= shift.endTime {
            throw HopeDataError.invalid("Lần nhắc phải nằm trong ca đang trực và trước giờ kết thúc ca.")
        }
        task.snoozedUntil = date; task.updatedAt = now
        try context.save()
    }
    public static func prepareLegacyData(in context: ModelContext) throws {
        let shifts = try context.fetch(FetchDescriptor<ShiftConfig>())
        let byID = Dictionary(uniqueKeysWithValues: shifts.map { ($0.id, $0) })
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        for task in tasks {
            if task.dueAt == nil, task.dueTime != nil {
                task.dueAt = TaskText.deadline(task.dueTime, shift: task.shiftId.flatMap { byID[$0] }, fallback: task.createdAt)
            }
            if task.searchText.isEmpty { task.rebuildSearchText() }
        }
        if context.hasChanges { try context.save() }
    }
}

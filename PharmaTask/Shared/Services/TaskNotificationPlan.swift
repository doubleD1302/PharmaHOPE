import Foundation

public struct PlannedTaskNotification: Equatable {
    public let id: String
    public let taskID: String?
    public let title: String
    public let body: String
    public let date: Date
}

/// Thông báo trước khi ca trực bắt đầu: 30 phút trước và đúng giờ bắt đầu, cho các ca chưa bắt đầu trong 7 ngày tới.
public enum ShiftNotificationPlan {
    public static func make(shifts: [ShiftConfig], now: Date = .now) -> [PlannedTaskNotification] {
        var plan: [PlannedTaskNotification] = []
        let horizon = now.addingTimeInterval(7 * 24 * 3600)
        for shift in shifts where !shift.isActive && !shift.name.lowercased().contains("nghỉ") && shift.startTime > now && shift.startTime < horizon {
            let clock = TaskText.clock(shift.startTime)
            let early = shift.startTime.addingTimeInterval(-30 * 60)
            if early > now {
                plan.append(.init(id: "hope.shiftstart.\(shift.id).30", taskID: nil, title: "Sắp đến \(shift.name)",
                                  body: "Còn 30 phút nữa là \(clock). Mở Hope để bắt đầu ca.", date: early))
            }
            plan.append(.init(id: "hope.shiftstart.\(shift.id).0", taskID: nil, title: "Đến giờ \(shift.name)",
                              body: "Bạn chưa bắt đầu ca. Mở Hope để bắt đầu.", date: shift.startTime))
        }
        return Array(plan.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.prefix(20))
    }
}

public enum TaskNotificationPlan {
    public static func make(tasks: [TaskItem], shiftEnd: Date?, now: Date = .now) -> [PlannedTaskNotification] {
        var plan: [PlannedTaskNotification] = []
        for task in tasks where !task.isCompleted && task.deletedAt == nil && task.reminderEnabled {
            let end = task.shiftId == nil ? Date.distantFuture : (shiftEnd ?? .distantPast)
            guard end > now else { continue }
            guard let due = task.dueAt else { continue }
            func add(_ suffix: String, date: Date, title: String) {
                guard date > now, date <= end else { return }
                if suffix != "snooze", let snoozed = task.snoozedUntil, date <= snoozed { return }
                plan.append(.init(id: "hope.task.\(task.id).\(suffix)", taskID: task.id, title: title, body: task.title, date: date))
            }
            if let snoozed = task.snoozedUntil {
                add("snooze", date: snoozed, title: "Đến giờ nhắc lại")
                if due <= snoozed { continue }
            }
            let minutes = max(0, min(task.reminderLeadMinutes, 60))
            if minutes > 0 { add("before", date: due.addingTimeInterval(-Double(minutes) * 60), title: "Còn \(minutes) phút đến hạn") }
            add("due", date: due, title: "Đến hạn công việc")
            add("overdue", date: due.addingTimeInterval(15 * 60), title: "Công việc đã quá hạn 15 phút")
        }
        let remaining = tasks.filter { !$0.isCompleted && $0.deletedAt == nil && $0.shiftId != nil }
        if let shiftEnd = shiftEnd, shiftEnd > now, !remaining.isEmpty {
            for minutes in [30, 15] {
                let date = shiftEnd.addingTimeInterval(-Double(minutes) * 60)
                if date > now {
                    plan.append(.init(id: "hope.clockout.\(minutes)", taskID: nil,
                        title: "Còn \(minutes) phút hết ca", body: "Bạn còn \(remaining.count) việc chưa hoàn thành.", date: date))
                }
            }
        }
        // iOS has a bounded queue. Reserve room and always keep the nearest events first.
        return Array(plan.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.prefix(60))
    }
}

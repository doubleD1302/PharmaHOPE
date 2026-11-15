import Foundation

enum HopeAlertKind: String, Sendable {
    case taskSoon, taskDue, taskLate, taskSnooze, shiftSoon, shiftStart, shiftEnd, rest, closeDay

    var symbol: String {
        switch self {
        case .taskSoon, .taskDue, .taskSnooze: return "alarm"
        case .taskLate: return "exclamationmark.triangle"
        case .shiftSoon, .shiftStart: return "clock.badge"
        case .shiftEnd: return "moon.stars"
        case .rest: return "leaf"
        case .closeDay: return "moon.zzz"
        }
    }

    /// Đoạn chuông dùng cho loại thông báo này (trùng với âm của thông báo hệ thống đã lên lịch).
    var melody: BellMelody.Kind {
        switch self {
        case .taskLate, .shiftEnd: return .urgent
        case .taskDue, .taskSnooze, .shiftStart: return .due
        default: return .info
        }
    }

    /// Có thông báo hệ thống đã lên lịch cho loại này; khi app đang mở iOS tự phát chuông nên không phát thêm trong app.
    var hasScheduledNotification: Bool {
        switch self {
        case .rest, .closeDay: return false
        default: return true
        }
    }

    /// Thứ tự hiển thị: việc cần xử lý gấp trước.
    var severity: Int {
        switch self {
        case .taskLate: return 0
        case .taskDue: return 1
        case .taskSnooze: return 2
        case .shiftEnd: return 3
        case .taskSoon: return 4
        case .shiftStart: return 5
        case .shiftSoon: return 6
        case .rest: return 7
        case .closeDay: return 8
        }
    }
}

struct HopeAlert: Identifiable, Equatable, Sendable {
    /// Khoá ổn định của thông báo, dùng để nhớ đã đọc và đã phát chuông.
    let id: String
    let kind: HopeAlertKind
    let title: String
    let body: String
    var taskID: String?
    var shiftID: String?
}

/// Tạo danh sách thông báo hiện hành từ dữ liệu: việc đến hạn, quá hạn, ca trực, và vài lời nhắc nhẹ trong ngày.
/// Đây là trạng thái hiện tại (không phải sự kiện bắn một lần), nên việc quá hạn nằm đó đến khi bạn xong hoặc hoãn.
enum HopeAlertEngine {
    static func make(tasks: [TaskItem], shifts: [ShiftConfig], visits: [HealingVisit],
                     now: Date = .now, calendar: Calendar = .current) -> [HopeAlert] {
        var out: [HopeAlert] = []
        let open = tasks.filter { !$0.isCompleted && $0.deletedAt == nil }

        for task in open where task.reminderEnabled {
            guard let due = task.dueAt else { continue }
            let snoozedUntil = task.snoozedUntil ?? .distantPast
            if snoozedUntil > now { continue }
            let stamp = task.snoozedUntil.map { Int($0.timeIntervalSince1970) } ?? 0
            if task.snoozedUntil != nil, now.timeIntervalSince(snoozedUntil) < 6 * 3600 {
                out.append(HopeAlert(id: "t:\(task.id):snooze:\(stamp)", kind: .taskSnooze, title: "Đến giờ nhắc lại", body: task.title, taskID: task.id))
            }
            let lead = Double(max(0, min(task.reminderLeadMinutes, 60)))
            if now >= due.addingTimeInterval(15 * 60), due.addingTimeInterval(15 * 60) > snoozedUntil {
                out.append(HopeAlert(id: "t:\(task.id):late:\(stamp)", kind: .taskLate, title: "Quá hạn",
                                     body: "\(task.title) · quá hạn \(overdueText(now.timeIntervalSince(due)))", taskID: task.id))
            } else if now >= due, due > snoozedUntil {
                out.append(HopeAlert(id: "t:\(task.id):due:\(stamp)", kind: .taskDue, title: "Đến hạn công việc", body: task.title, taskID: task.id))
            } else if lead > 0, now >= due.addingTimeInterval(-lead * 60), now < due, due.addingTimeInterval(-lead * 60) > snoozedUntil {
                let minutes = max(1, Int(ceil(due.timeIntervalSince(now) / 60)))
                out.append(HopeAlert(id: "t:\(task.id):soon:\(stamp)", kind: .taskSoon, title: "Sắp đến hạn", body: "\(task.title) · còn \(minutes) phút", taskID: task.id))
            }
        }

        for shift in shifts where !shift.name.lowercased().contains("nghỉ") {
            let start = shift.startTime, end = shift.endTime
            if !shift.isActive {
                if now >= start.addingTimeInterval(-30 * 60), now < start {
                    let minutes = max(1, Int(ceil(start.timeIntervalSince(now) / 60)))
                    out.append(HopeAlert(id: "s:\(shift.id):soon", kind: .shiftSoon, title: "Sắp đến \(shift.name)",
                                         body: "Còn \(minutes) phút nữa là \(TaskText.clock(start)). Bắt đầu ca khi bạn sẵn sàng.", shiftID: shift.id))
                } else if now >= start, now < min(end, start.addingTimeInterval(90 * 60)) {
                    out.append(HopeAlert(id: "s:\(shift.id):start", kind: .shiftStart, title: "Đã đến giờ \(shift.name)",
                                         body: "Bạn chưa bắt đầu ca. Vào Lịch ca để bắt đầu.", shiftID: shift.id))
                }
            } else {
                let pending = open.filter { $0.shiftId == shift.id }.count
                guard pending > 0 else { continue }
                if now < end {
                    if now >= end.addingTimeInterval(-15 * 60) {
                        out.append(HopeAlert(id: "s:\(shift.id):end15", kind: .shiftEnd, title: "Còn 15 phút hết ca", body: "Bạn còn \(pending) việc chưa hoàn thành.", shiftID: shift.id))
                    } else if now >= end.addingTimeInterval(-30 * 60) {
                        out.append(HopeAlert(id: "s:\(shift.id):end30", kind: .shiftEnd, title: "Còn 30 phút hết ca", body: "Bạn còn \(pending) việc chưa hoàn thành.", shiftID: shift.id))
                    }
                } else if now < end.addingTimeInterval(6 * 3600) {
                    out.append(HopeAlert(id: "s:\(shift.id):ended", kind: .shiftEnd, title: "\(shift.name) đã hết giờ",
                                         body: "Còn \(pending) việc chưa xong. Bạn có thể kết thúc ca hoặc làm tiếp.", shiftID: shift.id))
                }
            }
        }

        let dayStart = calendar.startOfDay(for: now)
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let dayKey = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        let hour = calendar.component(.hour, from: now)
        let today = visits.filter { $0.createdAt >= dayStart }
        if hour >= 14, today.isEmpty {
            out.append(HopeAlert(id: "rest:\(dayKey)", kind: .rest, title: "Nghỉ một phút nhé?", body: "Hôm nay bạn chưa ghé khu vườn. Một phút thở cũng đủ."))
        }
        if hour >= 21, !today.contains(where: { $0.kind == .closeDay }) {
            out.append(HopeAlert(id: "close:\(dayKey)", kind: .closeDay, title: "Khép lại hôm nay", body: "Ghi nhận vài điều bạn đã làm được trước khi nghỉ."))
        }
        return out.sorted { $0.kind.severity == $1.kind.severity ? $0.id < $1.id : $0.kind.severity < $1.kind.severity }
    }

    static func overdueText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(1, minutes)) phút" }
        if minutes < 1440 { return "\(minutes / 60) giờ" }
        return "\(minutes / 1440) ngày"
    }
}

/// Nhớ thông báo nào đã đọc và đã phát chuông, để không báo lại mỗi lần mở app.
enum HopeAlertState {
    static let readKey = "hope.alerts.read"
    static let seenKey = "hope.alerts.seen"
    static let soundKey = "hope.alerts.sound"
    static let closeDayKey = "hope.alerts.closeDayReminder"

    static func readKeys(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: readKey) ?? [])
    }

    static func markRead(_ keys: [String], _ defaults: UserDefaults = .standard) {
        let merged = readKeys(defaults).union(keys)
        defaults.set(Array(merged.suffix(300)), forKey: readKey)
    }

    /// Trả về những khoá chưa từng thấy, và ghi nhớ chúng. Khoá cũ hơn 14 ngày bị bỏ để không phình mãi.
    static func newlySeen(_ keys: [String], now: Date = .now, _ defaults: UserDefaults = .standard) -> [String] {
        var seen = (defaults.dictionary(forKey: seenKey) as? [String: Double]) ?? [:]
        seen = seen.filter { now.timeIntervalSince1970 - $0.value < 14 * 86_400 }
        let fresh = keys.filter { seen[$0] == nil }
        for key in fresh { seen[key] = now.timeIntervalSince1970 }
        defaults.set(seen, forKey: seenKey)
        return fresh
    }

    static var soundEnabled: Bool { UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true }
}

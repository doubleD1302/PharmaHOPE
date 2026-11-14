import Foundation
import SwiftData

@MainActor
public enum RoutineChecklistService {
    private static var defaults: UserDefaults { UserDefaults(suiteName: SharedModelContainer.appGroupID) ?? .standard }
    public static func markInitialized() { defaults.set(true, forKey: "hope.routines.initialized") }
    public static func seedIfNeeded(context: ModelContext) throws {
        guard !defaults.bool(forKey: "hope.routines.initialized") else { return }
        if try context.fetchCount(FetchDescriptor<RoutineTemplate>()) == 0 {
            let entries: [(RoutineType, String, TaskPriority)] = [
                (.morning, "Kiểm đếm quỹ đầu ca", .high), (.morning, "Ghi nhiệt độ và độ ẩm tủ thuốc", .high),
                (.morning, "Kiểm tra danh mục thuốc cận hạn", .medium),
                (.afternoon, "Ghi nhiệt độ và độ ẩm ca chiều", .high), (.afternoon, "Đối soát doanh thu và chốt quỹ", .high),
                (.night, "Kiểm tra thiết bị và khu vực bảo quản", .high), (.night, "Vệ sinh quầy trước khi kết thúc ca", .low),
                (.split, "Chuẩn bị quầy cho giờ cao điểm", .medium)
            ]
            for (index, entry) in entries.enumerated() {
                context.insert(RoutineTemplate(title: entry.1, priority: entry.2, type: entry.0, position: index))
            }
            try context.save()
        }
        markInitialized()
    }
    @discardableResult
    public static func apply(to shift: ShiftConfig, context: ModelContext) throws -> Int {
        guard !shift.checklistApplied else { return 0 }
        let shiftID = shift.id
        let previous = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.shiftId == shiftID }))
        // Legacy or deleted routine instances still count as already applied to this shift.
        guard !previous.contains(where: { $0.isRoutine }) else { shift.checklistApplied = true; return 0 }
        let type = shift.routineType.rawValue
        let templates = try context.fetch(FetchDescriptor<RoutineTemplate>(predicate: #Predicate { $0.typeRaw == type && $0.isEnabled },
            sortBy: [SortDescriptor(\RoutineTemplate.position), SortDescriptor(\RoutineTemplate.title)]))
        for template in templates {
            let task = TaskItem(title: template.title, notes: template.notes,
                priority: TaskPriority(rawValue: template.priorityRaw) ?? .medium, dueTime: template.dueTime,
                isRoutine: true, shiftId: shift.id)
            task.routineTemplateID = template.id
            task.dueAt = TaskText.deadline(template.dueTime, shift: shift, fallback: shift.startTime)
            context.insert(task)
        }
        shift.checklistApplied = true; shift.updatedAt = .now
        return templates.count
    }
}

import Foundation
import SwiftData

@MainActor
public enum TaskImportService {
    public static func stage(tasks: [TaskItem], source: String, label: String, shiftID: String?, context: ModelContext) throws -> PendingTaskImport {
        guard !tasks.isEmpty else { throw HopeDataError.invalid("Không tìm thấy đầu việc trong nội dung này.") }
        guard tasks.count <= 200, source.count <= 200_000 else { throw HopeDataError.invalid("Mỗi bản nháp hỗ trợ tối đa 200 việc và 200.000 ký tự nguồn.") }
        let pending = try PendingTaskImport(sourceText: source, sourceLabel: label, shiftID: shiftID, drafts: tasks.map { TaskDraft(task: $0) })
        context.insert(pending)
        try context.save()
        return pending
    }
    public static func commit(_ pending: PendingTaskImport, drafts: [TaskDraft], shiftID: String?, context: ModelContext) throws -> Int {
        guard drafts.count <= 200, pending.sourceText.count <= 200_000 else { throw HopeDataError.invalid("Bản nháp vượt giới hạn số việc hoặc độ dài nguồn.") }
        let id = pending.id
        guard try context.fetchCount(FetchDescriptor<PendingTaskImport>(predicate: #Predicate { $0.id == id })) == 1 else {
            throw HopeDataError.invalid("Bản nháp này đã được xử lý. Hãy mở lại danh sách chờ duyệt.")
        }
        guard try context.fetchCount(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.importBatchID == id })) == 0 else {
            throw HopeDataError.invalid("Bản nháp này đã được lưu thành công việc trước đó.")
        }
        let selected = drafts.filter { $0.isSelected }
        guard !selected.isEmpty else { throw HopeDataError.invalid("Chọn ít nhất một công việc để lưu.") }
        let shifts = try context.fetch(FetchDescriptor<ShiftConfig>())
        let shift = shifts.first { $0.id == shiftID }
        if shiftID != nil && shift == nil { throw HopeDataError.invalid("Ca đã chọn không còn tồn tại.") }
        // Validate the full selection before inserting any row.
        for draft in selected {
            guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draft.title.count <= 500,
                  draft.notes.count <= 20_000, TaskPriority(rawValue: draft.priorityRaw) != nil,
                  draft.dueTime == nil || TaskText.validTime(draft.dueTime ?? "") else {
                throw HopeDataError.invalid("Kiểm tra lại tên việc, mức ưu tiên và giờ HH:mm trong các dòng đã chọn.")
            }
        }
        for draft in selected {
            let task = TaskItem(title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines), notes: draft.notes,
                priority: TaskPriority(rawValue: draft.priorityRaw)!, dueTime: draft.dueTime, shiftId: shiftID)
            task.sourceText = pending.sourceText
            task.importBatchID = pending.id
            task.dueAt = TaskText.deadline(draft.dueTime, shift: shift, fallback: .now)
            task.rebuildSearchText()
            context.insert(task)
        }
        context.delete(pending)
        try context.save()
        return selected.count
    }
}

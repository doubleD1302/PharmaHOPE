import Foundation
import SwiftData

public struct TaskBackupRecord: Codable, Sendable {
    public var id, title, priorityRaw: String
    public var notes, dueTime, shiftId, sourceText, routineTemplateID, importBatchID: String?
    public var isCompleted, isRoutine, reminderEnabled: Bool
    public var createdAt: Date
    public var dueAt, completedAt, deletedAt, updatedAt, snoozedUntil: Date?
    public var reminderLeadMinutes: Int
    public init(_ task: TaskItem) {
        id = task.id; title = task.title; priorityRaw = task.priorityRaw; notes = task.notes
        dueTime = task.dueTime; shiftId = task.shiftId; sourceText = task.sourceText; routineTemplateID = task.routineTemplateID
        importBatchID = task.importBatchID
        isCompleted = task.isCompleted; isRoutine = task.isRoutine; reminderEnabled = task.reminderEnabled
        createdAt = task.createdAt; dueAt = task.dueAt; completedAt = task.completedAt; deletedAt = task.deletedAt
        updatedAt = task.updatedAt; snoozedUntil = task.snoozedUntil; reminderLeadMinutes = task.reminderLeadMinutes
    }
    public var modified: Date { updatedAt ?? createdAt }
    public func apply(to task: TaskItem) {
        task.title = title; task.notes = notes; task.priorityRaw = priorityRaw; task.dueTime = dueTime; task.shiftId = shiftId
        task.sourceText = sourceText; task.routineTemplateID = routineTemplateID; task.isCompleted = isCompleted
        task.importBatchID = importBatchID
        task.isRoutine = isRoutine; task.reminderEnabled = reminderEnabled; task.createdAt = createdAt; task.dueAt = dueAt
        task.completedAt = completedAt; task.deletedAt = deletedAt; task.updatedAt = updatedAt; task.snoozedUntil = snoozedUntil
        task.reminderLeadMinutes = reminderLeadMinutes; task.rebuildSearchText()
    }
}

public struct ShiftBackupRecord: Codable, Sendable {
    public var id, name, pharmacistName, colorTag, notes, routineTypeRaw: String
    public var startTime, endTime, targetDate: Date
    public var updatedAt: Date?
    public var checklistApplied: Bool
    public init(_ shift: ShiftConfig) {
        id = shift.id; name = shift.name; pharmacistName = shift.pharmacistName; colorTag = shift.colorTag
        notes = shift.notes; routineTypeRaw = shift.routineTypeRaw; startTime = shift.startTime
        endTime = shift.endTime; targetDate = shift.targetDate; updatedAt = shift.updatedAt; checklistApplied = shift.checklistApplied
    }
    public var modified: Date { updatedAt ?? targetDate }
    public func apply(to shift: ShiftConfig) {
        shift.name = name; shift.pharmacistName = pharmacistName; shift.colorTag = colorTag; shift.notes = notes
        shift.routineTypeRaw = routineTypeRaw; shift.startTime = startTime; shift.endTime = endTime
        shift.targetDate = targetDate; shift.updatedAt = updatedAt; shift.checklistApplied = checklistApplied
    }
}

public struct RoutineBackupRecord: Codable, Sendable {
    public var id, title, notes, priorityRaw, typeRaw: String
    public var dueTime: String?
    public var isEnabled: Bool
    public var position: Int
    public var updatedAt: Date
    public init(_ template: RoutineTemplate) {
        id = template.id; title = template.title; notes = template.notes; priorityRaw = template.priorityRaw
        typeRaw = template.typeRaw; dueTime = template.dueTime; isEnabled = template.isEnabled
        position = template.position; updatedAt = template.updatedAt
    }
    public func apply(to template: RoutineTemplate) {
        template.title = title; template.notes = notes; template.priorityRaw = priorityRaw; template.typeRaw = typeRaw
        template.dueTime = dueTime; template.isEnabled = isEnabled; template.position = position; template.updatedAt = updatedAt
    }
}

public struct ImportBackupRecord: Codable, Sendable {
    public var id, sourceText, sourceLabel: String
    public var shiftID: String?
    public var createdAt: Date
    public var drafts: [TaskDraft]
    public init(_ pending: PendingTaskImport) throws {
        id = pending.id; sourceText = pending.sourceText; sourceLabel = pending.sourceLabel; shiftID = pending.shiftID
        createdAt = pending.createdAt; drafts = try pending.drafts()
    }
}

public struct HopeBackup: Codable, Sendable {
    public static let maximumBytes = 10 * 1024 * 1024
    public var app = "Hope"
    public var schemaVersion = 1
    public var exportedAt = Date()
    public var tasks: [TaskBackupRecord]
    public var shifts: [ShiftBackupRecord]
    public var routines: [RoutineBackupRecord]
    public var imports: [ImportBackupRecord]

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw HopeDataError.invalid("Bản sao lưu vượt quá giới hạn 10 MB.") }
        return data
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw HopeDataError.invalid("Chỉ nhập bản sao lưu tối đa 10 MB.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let archive: Self
        do { archive = try decoder.decode(Self.self, from: data) }
        catch { throw HopeDataError.invalid("Không đọc được tệp sao lưu Hope. Kiểm tra định dạng JSON và phiên bản tệp.") }
        try archive.validate()
        return archive
    }
    public func validate() throws {
        guard app == "Hope", schemaVersion == 1 else { throw HopeDataError.invalid("Tệp không thuộc Hope hoặc có phiên bản chưa được hỗ trợ.") }
        func validIDs(_ ids: [String]) -> Bool {
            ids.count <= 30_000 && Set(ids).count == ids.count && ids.allSatisfy { !$0.isEmpty && $0.count <= 128 && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        func validDate(_ date: Date?) -> Bool {
            guard let date = date else { return true }
            return date.timeIntervalSince1970.isFinite && (-2_208_988_800...32_503_680_000).contains(date.timeIntervalSince1970)
        }
        func validText(_ title: String, _ notes: String?) -> Bool {
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 500 && (notes?.count ?? 0) <= 20_000
        }
        guard validIDs(tasks.map(\.id)), validIDs(shifts.map(\.id)), validIDs(routines.map(\.id)), validIDs(imports.map(\.id)), validDate(exportedAt) else {
            throw HopeDataError.invalid("Tệp có ID trùng, ID không hợp lệ hoặc số bản ghi vượt giới hạn.")
        }
        for task in tasks {
            guard validText(task.title, task.notes), TaskPriority(rawValue: task.priorityRaw) != nil,
                  task.dueTime == nil || TaskText.validTime(task.dueTime ?? ""),
                  [0, 5, 10, 15, 30, 60].contains(task.reminderLeadMinutes), (task.sourceText?.count ?? 0) <= 200_000,
                  [task.shiftId, task.routineTemplateID, task.importBatchID].allSatisfy({ ($0?.count ?? 0) <= 128 }),
                  [task.createdAt, task.dueAt, task.completedAt, task.deletedAt, task.updatedAt, task.snoozedUntil].allSatisfy(validDate) else {
                throw HopeDataError.invalid("Tệp có công việc hoặc mốc thời gian không hợp lệ. Chưa nhập dữ liệu.")
            }
        }
        for shift in shifts {
            guard validText(shift.name, shift.notes), shift.pharmacistName.count <= 500, shift.id != "__inbox__", shift.colorTag.count <= 100,
                  shift.endTime >= shift.startTime, shift.endTime.timeIntervalSince(shift.startTime) <= 48 * 3600,
                  shift.routineTypeRaw == "auto" || RoutineType(rawValue: shift.routineTypeRaw) != nil,
                  [shift.startTime, shift.endTime, shift.targetDate, shift.updatedAt].allSatisfy(validDate) else {
                throw HopeDataError.invalid("Tệp có ca trực không hợp lệ. Chưa nhập dữ liệu.")
            }
        }
        for routine in routines {
            guard validText(routine.title, routine.notes), TaskPriority(rawValue: routine.priorityRaw) != nil,
                  RoutineType(rawValue: routine.typeRaw) != nil, (0...100_000).contains(routine.position), validDate(routine.updatedAt),
                  routine.dueTime == nil || TaskText.validTime(routine.dueTime ?? "") else {
                throw HopeDataError.invalid("Tệp có mẫu checklist không hợp lệ. Chưa nhập dữ liệu.")
            }
        }
        for pending in imports {
            guard validDate(pending.createdAt), pending.sourceText.count <= 200_000, pending.sourceLabel.count <= 500, pending.drafts.count <= 200,
                  validIDs(pending.drafts.map(\.id)) else { throw HopeDataError.invalid("Tệp có bản nháp AI không hợp lệ.") }
            // Unselected drafts may intentionally contain unfinished edits; preserve them for review.
            for draft in pending.drafts {
                guard draft.title.count <= 500, draft.notes.count <= 20_000, TaskPriority(rawValue: draft.priorityRaw) != nil else {
                    throw HopeDataError.invalid("Bản nháp vượt giới hạn hoặc có mức ưu tiên không hợp lệ.")
                }
            }
        }
    }
    public static func readFile(_ url: URL) throws -> Self {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumBytes {
            throw HopeDataError.invalid("Chỉ nhập bản sao lưu tối đa 10 MB.")
        }
        return try decode(Data(contentsOf: url, options: .mappedIfSafe))
    }
}

public struct BackupMergeSummary {
    public var inserted = 0
    public var updated = 0
    public var kept = 0
}

@MainActor
public enum HopeBackupService {
    public static func snapshot(context: ModelContext) throws -> HopeBackup {
        HopeBackup(tasks: try context.fetch(FetchDescriptor<TaskItem>()).map(TaskBackupRecord.init),
            shifts: try context.fetch(FetchDescriptor<ShiftConfig>()).map(ShiftBackupRecord.init),
            routines: try context.fetch(FetchDescriptor<RoutineTemplate>()).map(RoutineBackupRecord.init),
            imports: try context.fetch(FetchDescriptor<PendingTaskImport>()).map { try ImportBackupRecord($0) })
    }
    public static func merge(_ archive: HopeBackup, context: ModelContext, updateLibraryPreference: Bool = true) throws -> BackupMergeSummary {
        try archive.validate() // Validation is complete before any model is changed.
        var summary = BackupMergeSummary()
        let tasks = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TaskItem>()).map { ($0.id, $0) })
        let shifts = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ShiftConfig>()).map { ($0.id, $0) })
        let routines = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<RoutineTemplate>()).map { ($0.id, $0) })
        let imports = Set(try context.fetch(FetchDescriptor<PendingTaskImport>()).map(\.id))
        do {
            for record in archive.shifts {
                if let shift = shifts[record.id] {
                    if record.modified > (shift.updatedAt ?? shift.targetDate) { record.apply(to: shift); summary.updated += 1 }
                    else { summary.kept += 1 }
                } else {
                    let shift = ShiftConfig(id: record.id, name: record.name, startTime: record.startTime, endTime: record.endTime, isActive: false)
                    record.apply(to: shift); context.insert(shift); summary.inserted += 1
                }
            }
            for record in archive.tasks {
                if let task = tasks[record.id] {
                    if record.modified > (task.updatedAt ?? task.createdAt) { record.apply(to: task); summary.updated += 1 }
                    else { summary.kept += 1 }
                } else {
                    let task = TaskItem(id: record.id, title: record.title)
                    record.apply(to: task); context.insert(task); summary.inserted += 1
                }
            }
            for record in archive.routines {
                if let routine = routines[record.id] {
                    if record.updatedAt > routine.updatedAt { record.apply(to: routine); summary.updated += 1 }
                    else { summary.kept += 1 }
                } else {
                    let routine = RoutineTemplate(id: record.id, title: record.title, type: RoutineType(rawValue: record.typeRaw)!)
                    record.apply(to: routine); context.insert(routine); summary.inserted += 1
                }
            }
            for record in archive.imports {
                if imports.contains(record.id) { summary.kept += 1; continue }
                let batchID = record.id
                if try context.fetchCount(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.importBatchID == batchID })) > 0 {
                    summary.kept += 1; continue
                }
                let pending = try PendingTaskImport(sourceText: record.sourceText, sourceLabel: record.sourceLabel,
                    shiftID: record.shiftID, drafts: record.drafts)
                pending.id = record.id; pending.createdAt = record.createdAt
                context.insert(pending); summary.inserted += 1
            }
            try context.save() // One atomic persistence save; no partial import on validation failure.
            if updateLibraryPreference { RoutineChecklistService.markInitialized() }
            return summary
        } catch { context.rollback(); throw error }
    }
}

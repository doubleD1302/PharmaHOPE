import Foundation
import SwiftData

public struct TaskDraft: Codable, Identifiable, Sendable {
    public var id: String = UUID().uuidString
    public var title: String
    public var notes: String
    public var priorityRaw: String
    public var dueTime: String?
    public var isSelected: Bool = true
    public init(task: TaskItem) {
        title = task.title; notes = task.notes ?? ""; priorityRaw = task.priorityRaw; dueTime = task.dueTime
    }
}

@Model
public final class PendingTaskImport {
    @Attribute(.unique) public var id: String
    public var createdAt: Date
    public var sourceText: String
    public var sourceLabel: String
    public var shiftID: String?
    public var draftsData: Data
    public init(sourceText: String, sourceLabel: String, shiftID: String?, drafts: [TaskDraft]) throws {
        self.id = UUID().uuidString; self.createdAt = .now; self.sourceText = sourceText
        self.sourceLabel = sourceLabel; self.shiftID = shiftID
        self.draftsData = try JSONEncoder().encode(drafts)
    }
    public func drafts() throws -> [TaskDraft] { try JSONDecoder().decode([TaskDraft].self, from: draftsData) }
}

import AppIntents
import SwiftData
import ActivityKit
import Foundation

public struct CompleteTaskIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Hoàn thành công việc"
    public static var description = IntentDescription("Đánh dấu hoàn thành tác vụ trực tiếp từ Màn hình khóa.")
    
    @Parameter(title: "Task ID")
    public var taskID: String

    public init() {}
    
    public init(taskID: String) {
        self.taskID = taskID
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        let container = SharedModelContainer.shared
        let context = container.mainContext
        let targetId = self.taskID
        
        var descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.id == targetId && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        
        if let task = try context.fetch(descriptor).first {
            // A retried completion intent must never undo an already completed task.
            try TaskCommands.complete(task, completed: true, context: context)
            
            // Đồng bộ cập nhật ngay lập tức giao diện Live Activity
            try await ShiftTaskSync.refresh(using: context)
        }
        
        return .result()
    }
    
}

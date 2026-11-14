import ActivityKit
import Foundation

public struct ShiftActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public struct ShortTask: Codable, Hashable {
            public var id: String
            public var title: String
            public var priority: String
            public var isCompleted: Bool
            
            public init(id: String, title: String, priority: String, isCompleted: Bool = false) {
                self.id = id
                self.title = title
                self.priority = priority
                self.isCompleted = isCompleted
            }
        }
        
        public var shiftName: String
        public var completedCount: Int
        public var totalCount: Int
        public var pendingTasks: [ShortTask] // Tối đa 2-3 tác vụ quan trọng hiển thị trên Lock Screen
        
        public init(
            shiftName: String,
            completedCount: Int,
            totalCount: Int,
            pendingTasks: [ShortTask]
        ) {
            self.shiftName = shiftName
            self.completedCount = completedCount
            self.totalCount = totalCount
            self.pendingTasks = pendingTasks
        }
    }
    
    public var shiftId: String
    public var shiftEndTime: Date
    
    public init(shiftId: String, shiftEndTime: Date) {
        self.shiftId = shiftId
        self.shiftEndTime = shiftEndTime
    }
}

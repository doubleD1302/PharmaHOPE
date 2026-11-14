import Foundation
import SwiftData

public enum RoutineType: String, Codable, CaseIterable, Identifiable, Sendable {
    case morning, afternoon, night, split, custom
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .morning: return "Ca sáng"
        case .afternoon: return "Ca chiều"
        case .night: return "Ca đêm"
        case .split: return "Ca gãy"
        case .custom: return "Ca khác"
        }
    }
    public static func infer(_ name: String) -> Self {
        let name = TaskText.normalized(name)
        if name.contains("gay") { return .split }
        if name.contains("dem") || name.contains("toi") { return .night }
        if name.contains("chieu") { return .afternoon }
        if name.contains("sang") { return .morning }
        return .custom
    }
}

@Model
public final class RoutineTemplate {
    @Attribute(.unique) public var id: String
    public var title: String
    public var notes: String
    public var priorityRaw: String
    public var typeRaw: String
    public var dueTime: String?
    public var isEnabled: Bool
    public var position: Int
    public var updatedAt: Date
    public init(id: String = UUID().uuidString, title: String, notes: String = "", priority: TaskPriority = .medium,
                type: RoutineType, dueTime: String? = nil, isEnabled: Bool = true, position: Int = 0) {
        self.id = id; self.title = title; self.notes = notes; self.priorityRaw = priority.rawValue
        self.typeRaw = type.rawValue; self.dueTime = dueTime; self.isEnabled = isEnabled
        self.position = position; self.updatedAt = .now
    }
}

import Foundation
import SwiftData

public enum TaskPriority: String, Codable, CaseIterable {
    case high = "high"       // Khẩn cấp / Cận date / Két tiền
    case medium = "medium"   // Trong ca
    case low = "low"         // Cuối ca / Vệ sinh bàn giao
    
    public var title: String {
        switch self {
        case .high: return "Khẩn cấp"
        case .medium: return "Trong ca"
        case .low: return "Cuối ca"
        }
    }
    
    public var sortOrder: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

@Model
public final class TaskItem {
    @Attribute(.unique) public var id: String
    public var title: String
    public var notes: String?
    public var priorityRaw: String
    public var isCompleted: Bool
    public var dueTime: String?        // Định dạng "HH:mm" (ví dụ: "10:30")
    public var isRoutine: Bool         // Thuộc danh mục công việc cố định hằng ngày
    public var createdAt: Date
    public var shiftId: String?
    public var dueAt: Date? = nil
    public var completedAt: Date? = nil
    public var deletedAt: Date? = nil
    public var updatedAt: Date? = nil
    public var snoozedUntil: Date? = nil
    public var sourceText: String? = nil
    public var routineTemplateID: String? = nil
    public var importBatchID: String? = nil
    public var searchText: String = ""
    public var reminderEnabled: Bool = true
    public var reminderLeadMinutes: Int = 10
    
    public var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        notes: String? = nil,
        priority: TaskPriority = .medium,
        isCompleted: Bool = false,
        dueTime: String? = nil,
        isRoutine: Bool = false,
        createdAt: Date = .now,
        shiftId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.priorityRaw = priority.rawValue
        self.isCompleted = isCompleted
        self.dueTime = dueTime
        self.isRoutine = isRoutine
        self.createdAt = createdAt
        self.shiftId = shiftId
        self.updatedAt = createdAt
        self.completedAt = isCompleted ? createdAt : nil
        rebuildSearchText()
    }

    public func rebuildSearchText() {
        searchText = TaskText.normalized([title, notes ?? "", sourceText ?? ""].joined(separator: " "))
    }
    
    // Checklist mẫu chuyên biệt cho nhân viên nhà thuốc (Pharmacity / Long Châu)
    public static func defaultPharmacityRoutines(shiftId: String) -> [TaskItem] {
        return [
            TaskItem(
                title: "Kiểm đếm quỹ đầu ca & ký biên bản bàn giao",
                notes: "Đối soát tiền mặt thực tế với két tiền POS",
                priority: .high,
                isRoutine: true,
                shiftId: shiftId
            ),
            TaskItem(
                title: "Đo & ghi log nhiệt ẩm kế tủ thuốc mát & quầy",
                notes: "Tủ lạnh vắc xin/men vi sinh: 2 - 8°C; Quầy bán lẻ: < 30°C, độ ẩm < 75%",
                priority: .high,
                isRoutine: true,
                shiftId: shiftId
            ),
            TaskItem(
                title: "Soát danh mục thuốc cận date (dưới 6 tháng)",
                notes: "Dán tem cảnh báo hoặc lập danh sách hoàn kho trả nhà cung cấp",
                priority: .medium,
                isRoutine: true,
                shiftId: shiftId
            ),
            TaskItem(
                title: "Vệ sinh khay đếm thuốc & lau bề mặt kính tủ trưng bày",
                notes: "Dùng cồn 70 độ lau sạch bụi bẩn và khay chia viên",
                priority: .medium,
                isRoutine: true,
                shiftId: shiftId
            ),
            TaskItem(
                title: "In báo cáo doanh thu & chốt két tiền cuối ca",
                notes: "Bàn giao số dư, hóa đơn hủy và bill quẹt thẻ cho ca sau",
                priority: .low,
                isRoutine: true,
                shiftId: shiftId
            )
        ]
    }
}

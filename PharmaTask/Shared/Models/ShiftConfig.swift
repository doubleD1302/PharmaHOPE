import Foundation
import SwiftData

@Model
public final class ShiftConfig {
    @Attribute(.unique) public var id: String
    public var name: String                // "Ca Sáng"
    public var startTime: Date
    public var endTime: Date
    public var isActive: Bool
    public var targetDate: Date
    public var pharmacistName: String      // Tên dược sĩ phụ trách ca
    public var colorTag: String            // "teal", "amber", "rose", "purple", "blue"
    public var notes: String               // Ghi chú bàn giao hoặc dặn dò đầu ca
    public var routineTypeRaw: String = "auto"
    public var checklistApplied: Bool = false
    public var updatedAt: Date? = nil

    public var routineType: RoutineType {
        get { RoutineType(rawValue: routineTypeRaw) ?? RoutineType.infer(name) }
        set { routineTypeRaw = newValue.rawValue }
    }
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        startTime: Date,
        endTime: Date,
        isActive: Bool = true,
        targetDate: Date = .now,
        pharmacistName: String = "DS. Trực chính",
        colorTag: String = "teal",
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.isActive = isActive
        self.targetDate = targetDate
        self.pharmacistName = pharmacistName
        self.colorTag = colorTag
        self.notes = notes
        self.updatedAt = .now
    }
    
    /// Tính tổng thời gian của ca (giờ)
    public var durationHours: Double {
        let diff = endTime.timeIntervalSince(startTime)
        return max(0, diff / 3600.0)
    }
    
    /// Ca mẫu chuẩn ban đầu cho nhà thuốc
    public static func defaultShifts() -> [ShiftConfig] {
        let calendar = Calendar.current
        let today = Date()
        
        let sangStart = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: today) ?? today
        let sangEnd = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: today) ?? today
        
        let chieuStart = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: today) ?? today
        let chieuEnd = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: today) ?? today
        
        let gayStart = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today) ?? today
        let gayEnd = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: today) ?? today
        
        return [
            ShiftConfig(name: "Ca Sáng", startTime: sangStart, endTime: sangEnd, isActive: false, pharmacistName: "DS. Nguyễn Lan", colorTag: "teal", notes: "Kiểm date tủ mát & nhận bàn giao két"),
            ShiftConfig(name: "Ca Chiều", startTime: chieuStart, endTime: chieuEnd, isActive: false, pharmacistName: "DS. Trần Minh", colorTag: "amber", notes: "Chốt két doanh thu cuối ngày & in báo cáo"),
            ShiftConfig(name: "Ca Gãy Trưa", startTime: gayStart, endTime: gayEnd, isActive: false, pharmacistName: "DS. Lê Hoa", colorTag: "blue", notes: "Hỗ trợ giờ cao điểm trưa")
        ]
    }
}

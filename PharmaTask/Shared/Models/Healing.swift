import Foundation
import SwiftData

/// Cảm xúc người dùng tự chọn khi ghé khu vườn. Không dùng để chấm điểm hay đặt chỉ tiêu.
public enum HopeMood: String, CaseIterable, Identifiable, Codable, Sendable {
    case relieved, okay, tired, tense, overwhelmed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .relieved: return "Nhẹ nhõm"
        case .okay: return "Bình thường"
        case .tired: return "Mệt"
        case .tense: return "Căng thẳng"
        case .overwhelmed: return "Quá tải"
        }
    }

    public var symbol: String {
        switch self {
        case .relieved: return "sun.haze"
        case .okay: return "cloud.sun"
        case .tired: return "moon.zzz"
        case .tense: return "wind"
        case .overwhelmed: return "cloud.rain"
        }
    }

    /// Dùng trong lời nhắn gửi Gemini; chỉ là từ khóa cảm xúc, không có văn bản người dùng viết.
    public var promptWord: String { title.lowercased() }
}

public enum HealingVisitKind: String, CaseIterable, Sendable {
    case checkIn, rest, journal, listen, note, closeDay
}

public enum JournalKind: String, CaseIterable, Sendable {
    case free, gratitude, closeDay
    public var title: String {
        switch self {
        case .free: return "Viết tự do"
        case .gratitude: return "Điều nhỏ đã làm được"
        case .closeDay: return "Khép lại hôm nay"
        }
    }
}

@Model
public final class MoodCheckIn {
    @Attribute(.unique) public var id: String
    public var createdAt: Date
    public var moodRaw: String

    public init(mood: HopeMood, createdAt: Date = .now) {
        self.id = UUID().uuidString
        self.createdAt = createdAt
        self.moodRaw = mood.rawValue
    }
    public var mood: HopeMood { HopeMood(rawValue: moodRaw) ?? .okay }
}

@Model
public final class JournalEntry {
    @Attribute(.unique) public var id: String
    public var createdAt: Date
    public var updatedAt: Date
    public var kindRaw: String
    public var prompt: String
    public var text: String

    public init(kind: JournalKind, prompt: String, text: String, createdAt: Date = .now) {
        self.id = UUID().uuidString
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.kindRaw = kind.rawValue
        self.prompt = prompt
        self.text = text
    }
    public var kind: JournalKind { JournalKind(rawValue: kindRaw) ?? .free }
}

/// Mỗi lần bạn ghé nghỉ. Khu vườn lớn dần theo số ngày có ghé, không bao giờ nhỏ lại.
@Model
public final class HealingVisit {
    @Attribute(.unique) public var id: String
    public var createdAt: Date
    public var kindRaw: String
    public var minutes: Int

    public init(kind: HealingVisitKind, minutes: Int = 0, createdAt: Date = .now) {
        self.id = UUID().uuidString
        self.createdAt = createdAt
        self.kindRaw = kind.rawValue
        self.minutes = minutes
    }
    public var kind: HealingVisitKind { HealingVisitKind(rawValue: kindRaw) ?? .checkIn }
}

public enum GardenStage: Int, CaseIterable, Sendable {
    case sprout, leafy, lush, bloom

    public static func stage(forDays days: Int) -> GardenStage {
        switch days {
        case ..<3: return .sprout
        case 3..<8: return .leafy
        case 8..<16: return .lush
        default: return .bloom
        }
    }

    public var imageName: String {
        switch self {
        case .sprout: return "GardenSprout"
        case .leafy: return "GardenLeafy"
        case .lush: return "GardenLush"
        case .bloom: return "GardenBloom"
        }
    }

    public var title: String {
        switch self {
        case .sprout: return "Mầm non"
        case .leafy: return "Đang xanh"
        case .lush: return "Xum xuê"
        case .bloom: return "Nở hoa"
        }
    }
}

public enum GardenGrowth {
    /// Số ngày khác nhau có ít nhất một lần ghé.
    public static func restDays(_ visits: [HealingVisit], calendar: Calendar = .current) -> Int {
        Set(visits.map { calendar.startOfDay(for: $0.createdAt) }).count
    }
}

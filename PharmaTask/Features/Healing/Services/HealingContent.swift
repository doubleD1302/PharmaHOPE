import Foundation

/// Nơi đến khi chạm vào một gợi ý.
public enum HealingDestination: Hashable, Sendable {
    case rest(minutes: Int)
    case journal(JournalKind, prompt: String)
    case listen
    case note
    case closeDay
}

public struct HealingSuggestion: Identifiable, Hashable, Sendable {
    public var id: String { title }
    public let title: String
    public let detail: String
    public let symbol: String
    public let destination: HealingDestination
}

/// Toàn bộ chữ của tab Vườn. Giọng nhẹ, không ra lệnh, không hứa hẹn chữa bệnh.
public enum HealingContent {
    public static let journalPrompts: [String] = [
        "Điều đang làm mình mệt là…",
        "Lúc này mình cần…",
        "Một điều nhỏ mình đã làm được hôm nay…",
        "Điều mình muốn buông xuống lúc này là…",
        "Một người hay một điều khiến mình thấy dịu lại…"
    ]

    public static let acknowledgements: [String] = [
        "Mình đã kiên nhẫn hơn mình nghĩ.",
        "Mình đã không bỏ cuộc giữa chừng.",
        "Mình đã giữ bình tĩnh khi mọi thứ dồn lại.",
        "Mình đã biết dừng lại khi cần.",
        "Mình đã quan tâm đến người khác thật lòng."
    ]

    /// Mỗi nhịp thở dài 10 giây: hít vào 4 giây, giữ 1 giây, thở ra 5 giây.
    public static let breathCycle: (inhale: Double, hold: Double, exhale: Double) = (4, 1, 5)

    public static let restCues: [String] = [
        "Thả lỏng hai vai xuống.",
        "Nhìn ra xa một điểm bất kỳ, để mắt được nghỉ.",
        "Để hàm thư giãn, môi hé nhẹ.",
        "Cảm nhận hai bàn chân đang chạm sàn.",
        "Không cần nghĩ gì cả. Chỉ cần thở.",
        "Mỗi hơi thở ra, buông thêm một chút.",
        "Việc cần làm vẫn ở đó. Lúc này chỉ cần ở đây."
    ]

    public static func suggestions(for mood: HopeMood) -> [HealingSuggestion] {
        let breathe = HealingSuggestion(title: "Thở cùng khu vườn", detail: "Một phút, nhịp thở chậm.",
                                        symbol: "wind", destination: .rest(minutes: 1))
        let rest = HealingSuggestion(title: "Nghỉ ba phút", detail: "Hình ảnh chuyển động chậm, lời nhắc thả lỏng.",
                                     symbol: "leaf", destination: .rest(minutes: 3))
        let rest2 = HealingSuggestion(title: "Nghỉ hai phút", detail: "Dừng lại, thở, rồi quay về với việc.",
                                      symbol: "leaf", destination: .rest(minutes: 2))
        let listen = HealingSuggestion(title: "Nghe một khoảng yên", detail: "Mưa, lá, suối hoặc quán cà phê.",
                                       symbol: "headphones", destination: .listen)
        let grateful = HealingSuggestion(title: "Một điều nhỏ đã làm được", detail: "Viết một dòng cho chính bạn.",
                                         symbol: "pencil.line",
                                         destination: .journal(.gratitude, prompt: "Một điều nhỏ mình đã làm được hôm nay…"))
        let vent = HealingSuggestion(title: "Viết ra cho nhẹ", detail: "Điều đang làm bạn mệt là gì?",
                                     symbol: "square.and.pencil",
                                     destination: .journal(.free, prompt: "Điều đang làm mình mệt là…"))
        let need = HealingSuggestion(title: "Lúc này mình cần…", detail: "Gọi tên điều bạn cần, không cần giải pháp.",
                                     symbol: "heart.text.square",
                                     destination: .journal(.free, prompt: "Lúc này mình cần…"))
        let note = HealingSuggestion(title: "Một lời dành cho bạn", detail: "Vài dòng ngắn, viết riêng cho lúc này.",
                                     symbol: "quote.bubble", destination: .note)
        switch mood {
        case .relieved: return [grateful, listen]
        case .okay: return [breathe, note]
        case .tired: return [rest, listen]
        case .tense: return [breathe, need]
        case .overwhelmed: return [rest2, vent]
        }
    }

    private static let offlineNotes: [HopeMood: [String]] = [
        .relieved: [
            "Nhẹ nhõm là dấu hiệu bạn vừa đi qua một đoạn khó. Cứ ở lại với cảm giác ấy thêm một chút.",
            "Có điều gì đó vừa được gỡ khỏi vai bạn. Hãy để nó thật sự nhẹ đi.",
            "Nhẹ nhõm cũng đáng được ghi nhận như mọi nỗ lực."
        ],
        .okay: [
            "Một ngày bình thường cũng là một ngày bạn đã giữ mọi thứ vận hành. Cảm ơn bản thân vì điều đó.",
            "Không cần phải đặc biệt. Bình thường đã là đủ.",
            "Lúc này bạn không cần làm thêm gì. Chỉ cần ở đây."
        ],
        .tired: [
            "Mệt không có nghĩa là bạn làm chưa đủ. Cơ thể chỉ đang nhắc bạn cần được nghỉ.",
            "Bạn đã dành nhiều sự chú ý cho người khác. Giờ dành một chút cho mình.",
            "Uống một ngụm nước, thả lỏng vai. Chỉ vậy thôi cũng được."
        ],
        .tense: [
            "Hít vào chậm, thở ra dài hơn một chút. Mọi thứ không cần xong ngay trong hơi thở này.",
            "Căng thẳng là dấu hiệu bạn đang quan tâm. Giờ hãy quan tâm cả đến mình.",
            "Bạn không phải gồng mình mọi lúc. Đôi vai có thể buông xuống."
        ],
        .overwhelmed: [
            "Khi mọi thứ đổ về cùng lúc, chỉ cần chọn một việc nhỏ nhất. Phần còn lại có thể chờ.",
            "Quá tải không phải lỗi của bạn. Hãy cho mình một khoảng dừng ngắn.",
            "Chỉ cần một việc tiếp theo thôi. Bạn không phải gánh cả ngày trong một lúc."
        ]
    ]

    /// Lời nhắn viết sẵn. Cùng một ngày và cùng cảm xúc sẽ ra cùng một câu; `variant` để đổi câu.
    public static func offlineNote(for mood: HopeMood, on date: Date = .now, variant: Int = 0, calendar: Calendar = .current) -> String {
        let notes = offlineNotes[mood] ?? []
        guard !notes.isEmpty else { return "Bạn đã ở đây rồi. Vậy là đủ cho lúc này." }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return notes[(day + max(variant, 0)) % notes.count]
    }

    public static func daypart(for date: Date = .now, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<11: return "buổi sáng"
        case 11..<14: return "buổi trưa"
        case 14..<18: return "buổi chiều"
        case 18..<22: return "buổi tối"
        default: return "đêm khuya"
        }
    }

    public static let careFooter = "Hope không thay thế chuyên gia. Nếu bạn thấy kiệt sức kéo dài hoặc không an toàn, hãy nói với người thân hoặc người có chuyên môn."
}

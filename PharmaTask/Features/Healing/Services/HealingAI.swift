import Foundation

public struct HealingNote: Equatable, Sendable {
    public let text: String
    public let isAI: Bool
}

/// Mọi chỗ Hope dùng AI. Quy tắc dữ liệu:
/// - Mặc định chỉ gửi cảm xúc đã chọn, buổi trong ngày hoặc số lượng. Không gửi tên việc hay nhật ký.
/// - Duy nhất `reflection` gửi nội dung người dùng viết, và giao diện phải xin đồng ý trước mỗi lần.
/// Thiếu khóa, mất mạng hay lỗi API đều quay về nội dung viết sẵn, không bao giờ báo lỗi ra giữa trải nghiệm.
public enum HealingAI {
    static let persona = """
    Bạn là Hope, người bạn dịu dàng trong ứng dụng dành cho dược sĩ làm ca trực. Giọng ấm, giản dị, không sáo rỗng.
    Xưng "mình" và gọi người dùng là "bạn". Không emoji, không markdown, không tiêu đề, không dấu ngoặc kép.
    Không ra lệnh, không khuyên y tế, không chẩn đoán, không hứa hẹn chữa lành, không nói kiểu "hãy tích cực lên".
    """

    // MARK: - Một lời dành cho bạn

    public static func note(for mood: HopeMood, variant: Int = 0, date: Date = .now) async -> HealingNote {
        let fallback = HealingNote(text: HealingContent.offlineNote(for: mood, on: date, variant: variant), isAI: false)
        let cacheKey = "note.\(mood.rawValue).\(variant).\(dayStamp(date))"
        if let cached = cachedText(cacheKey) { return HealingNote(text: cached, isAI: true) }
        let system = persona + "\nViết một lời nhắn tối đa hai câu và dưới 35 từ. Ghi nhận cảm xúc trước, sau đó chỉ nhẹ nhàng gợi một việc rất nhỏ hoặc không gợi gì. Chỉ trả về chính lời nhắn."
        let user = "Cảm xúc hiện tại: \(mood.promptWord). Thời điểm: \(HealingContent.daypart(for: date)). Lần thứ \(variant + 1) trong hôm nay, hãy viết khác các lần trước."
        guard let result = await GeminiClient.shared.generate(system: system, user: user, maxOutputTokens: 600),
              let text = cleaned(result.text), text.count >= 8, text.count <= 280 else { return fallback }
        store(text, for: cacheKey)
        return HealingNote(text: text, isAI: true)
    }

    // MARK: - Lời nhắc trong lúc nghỉ

    public static func restCues(mood: HopeMood?, date: Date = .now) async -> [String] {
        let fallback = HealingContent.restCues
        let moodWord = mood?.promptWord ?? "bình thường"
        let cacheKey = "cues.\(mood?.rawValue ?? "none").\(dayStamp(date))"
        if let cached = cachedText(cacheKey) { let lines = parseLines(cached, maximum: 8); if lines.count >= 4 { return lines } }
        let system = persona + "\nViết 7 lời nhắc thả lỏng cho một phiên nghỉ ngắn, mỗi lời một dòng, dưới 14 từ, mô tả cảm giác cơ thể hoặc hơi thở. Chỉ trả về 7 dòng."
        let user = "Cảm xúc hiện tại: \(moodWord). Thời điểm: \(HealingContent.daypart(for: date))."
        guard let result = await GeminiClient.shared.generate(system: system, user: user, maxOutputTokens: 700) else { return fallback }
        let lines = parseLines(result.text, maximum: 8).filter { $0.count <= 100 }
        guard lines.count >= 4 else { return fallback }
        store(lines.joined(separator: "\n"), for: cacheKey)
        return lines
    }

    // MARK: - Hope nói khi chạm vào

    public static func mascotLine(stage: GardenStage, mood: HopeMood?, variant: Int, date: Date = .now) async -> HealingNote {
        let fallbackLines = ["Chào bạn. Mình ở đây.", "Cây vẫn đang lớn, chậm mà chắc.", "Bạn đến là mình vui rồi.", "Cứ ngồi một lát nhé."]
        let fallback = HealingNote(text: fallbackLines[abs(variant) % fallbackLines.count], isAI: false)
        let system = persona + "\nViết một câu chào rất ngắn, dưới 14 từ, như nhân vật cây nhỏ đang trò chuyện cùng người đến thăm vườn. Chỉ trả về câu đó."
        let user = "Cây đang ở giai đoạn: \(stage.title). Cảm xúc người dùng: \(mood?.promptWord ?? "chưa nói"). Thời điểm: \(HealingContent.daypart(for: date)). Lần chạm thứ \(variant + 1)."
        guard let result = await GeminiClient.shared.generate(system: system, user: user, maxOutputTokens: 300),
              let text = cleaned(result.text), text.count >= 4, text.count <= 120 else { return fallback }
        return HealingNote(text: text, isAI: true)
    }

    // MARK: - Câu mở đầu cho nhật ký

    public static func journalPrompts(mood: HopeMood, date: Date = .now) async -> [String] {
        let cacheKey = "prompts.\(mood.rawValue).\(dayStamp(date))"
        if let cached = cachedText(cacheKey) { let lines = parseLines(cached, maximum: 6); if lines.count >= 3 { return lines } }
        let system = persona + "\nViết 4 câu mở đầu để người dùng viết tiếp vào nhật ký, mỗi câu một dòng, kết thúc bằng dấu ba chấm, bắt đầu bằng \"Mình\" hoặc \"Điều\", dưới 12 từ. Chỉ trả về 4 dòng."
        let user = "Cảm xúc hiện tại: \(mood.promptWord)."
        guard let result = await GeminiClient.shared.generate(system: system, user: user, maxOutputTokens: 400) else { return [] }
        let lines = parseLines(result.text, maximum: 6).filter { $0.count <= 80 }
        guard lines.count >= 3 else { return [] }
        store(lines.joined(separator: "\n"), for: cacheKey)
        return lines
    }

    // MARK: - Một lời đáp cho bài viết (gửi nội dung bài viết, cần người dùng đồng ý)

    public static func reflection(on text: String, prompt: String) async -> String? {
        let body = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
        guard !body.isEmpty else { return nil }
        let system = persona + """

        Người dùng vừa viết nhật ký riêng và chủ động nhờ bạn đáp lại. Hãy đáp trong ba câu: phản chiếu lại điều họ cảm thấy bằng lời của bạn, ghi nhận một điều họ đã làm được, rồi để ngỏ.
        Không đưa lời khuyên, không phân tích. Nếu nội dung cho thấy họ muốn tự làm hại bản thân, hãy nhẹ nhàng khuyến khích họ nói với người thân hoặc người có chuyên môn ngay.
        Chỉ trả về lời đáp.
        """
        let user = "Câu mở đầu: \(prompt)\nBài viết:\n\(body)"
        guard let result = await GeminiClient.shared.generate(system: system, user: user, maxOutputTokens: 900),
              let reply = cleaned(result.text), reply.count >= 8 else { return nil }
        return String(reply.prefix(600))
    }

    // MARK: - Gợi ý điều ghi nhận khi khép lại ngày

    public static func acknowledgements(completed: Int, unfinished: Int, date: Date = .now) async -> [String] {
        let system = persona + "\nViết 4 gợi ý ngắn để người dùng ghi nhận bản thân cuối ngày, mỗi gợi ý một dòng, viết ở ngôi thứ nhất bắt đầu bằng \"Mình đã\", dưới 12 từ, nói về phẩm chất chứ không về số lượng việc. Chỉ trả về 4 dòng."
        let user = "Hôm nay đã xong \(completed) việc, còn \(unfinished) việc chưa xong. Thời điểm: \(HealingContent.daypart(for: date))."
        guard let result = await GeminiClient.shared.generate(system: system, user: user, maxOutputTokens: 400) else { return [] }
        let lines = parseLines(result.text, maximum: 6).filter { $0.count <= 80 }
        return lines.count >= 3 ? lines : []
    }

    // MARK: - Thư từ khu vườn

    public static func weeklyLetter(moodCounts: [HopeMood: Int], restDays: Int, date: Date = .now) async -> String? {
        let cacheKey = "letter.\(weekStamp(date))"
        if let cached = cachedText(cacheKey) { return cached }
        guard restDays > 0 else { return nil }
        let summary = HopeMood.allCases.compactMap { mood -> String? in
            guard let n = moodCounts[mood], n > 0 else { return nil }
            return "\(mood.title.lowercased()) \(n) lần"
        }.joined(separator: ", ")
        let system = persona + "\nViết một lá thư rất ngắn, tối đa 3 câu và dưới 55 từ, từ khu vườn gửi người dùng, nhìn lại tuần qua một cách dịu dàng. Không so sánh, không đặt mục tiêu, không đếm thiếu sót. Chỉ trả về lá thư."
        let user = "Tuần này bạn ghé vườn \(restDays) ngày. Cảm xúc đã chọn: \(summary.isEmpty ? "chưa chọn" : summary)."
        guard let result = await GeminiClient.shared.generate(system: system, user: user, maxOutputTokens: 700),
              let letter = cleaned(result.text), letter.count >= 20, letter.count <= 400 else { return nil }
        store(letter, for: cacheKey)
        return letter
    }

    // MARK: - Xử lý chữ

    /// Bỏ ký hiệu trang trí mà model đôi khi thêm vào.
    static func cleaned(_ raw: String) -> String? {
        let text = raw
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Tách thành các dòng sạch: bỏ gạch đầu dòng và số thứ tự.
    static func parseLines(_ raw: String, maximum: Int) -> [String] {
        var lines: [String] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            var text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            while let first = text.first, "-•*·".contains(first) || first.isNumber || first == "." || first == ")" {
                text.removeFirst()
                text = text.trimmingCharacters(in: .whitespaces)
            }
            if let cleanedLine = cleaned(text), cleanedLine.count >= 6 { lines.append(cleanedLine) }
            if lines.count >= maximum { break }
        }
        return lines
    }

    // MARK: - Lưu tạm theo ngày để tiết kiệm lượt gọi

    private static let cachePrefix = "healing.ai."

    private static func dayStamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)\(c.month ?? 0)\(c.day ?? 0)"
    }

    private static func weekStamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(c.yearForWeekOfYear ?? 0)w\(c.weekOfYear ?? 0)"
    }

    private static func cachedText(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: cachePrefix + key)
    }

    private static func store(_ text: String, for key: String) {
        let defaults = UserDefaults.standard
        defaults.set(text, forKey: cachePrefix + key)
        // Dọn các mục cũ để không phình mãi.
        let stale = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(cachePrefix) && !$0.hasSuffix(dayStamp(.now)) && !$0.contains("letter.") }
        for item in stale.prefix(50) { defaults.removeObject(forKey: item) }
    }
}

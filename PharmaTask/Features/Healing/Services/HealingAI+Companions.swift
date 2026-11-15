import Foundation

/// Phần AI cho lời chào và trò chuyện với nhân vật. Câu trích của vườn là câu có thật, không do AI viết.
/// Quy tắc dữ liệu: lời chào chỉ gửi thời điểm trong ngày và cảm xúc đã chọn.
/// Trò chuyện gửi những gì bạn gõ trong khung chat, và giao diện chỉ mở sau khi bạn đồng ý một lần.
extension HealingAI {
    // MARK: - Lời chào khi chạm vào nhân vật

    static func companionHello(_ companion: HopeCompanion, variant: Int, mood: HopeMood?, date: Date = .now) async -> HealingNote {
        let fallback = HealingNote(text: companion.hello[abs(variant) % companion.hello.count], isAI: false)
        let system = "Bạn là \(companion.name), \(companion.persona). \(companion.style)\nViết MỘT câu chào ngắn dưới 12 từ như nhắn tin cho bạn, tiếng Việt đời thường, không văn hoa, không ẩn dụ, không emoji, không dấu ngoặc kép. Chỉ trả về câu đó.\nVí dụ giọng: \(companion.hello[0])"
        let user = "Cảm xúc người dùng: \(mood?.promptWord ?? "chưa nói"). Thời điểm: \(HealingContent.daypart(for: date)). Lần chạm thứ \(variant + 1)."
        guard let result = await GeminiClient.shared.generate(system: system, user: user, maxOutputTokens: 300),
              let text = cleaned(result.text), text.count >= 4, text.count <= 120 else { return fallback }
        return HealingNote(text: text, isAI: true)
    }

    // MARK: - Trò chuyện

    /// Lời nhắc hệ thống cho trò chuyện: nhắn tin như người thật, không viết văn; giọng riêng của từng nhân vật kèm câu mẫu.
    static func chatSystemPrompt(for companion: HopeCompanion) -> String {
        let examples = companion.examples.map { "Bạn: \($0.user)\n\(companion.name): \($0.reply)" }.joined(separator: "\n")
        return """
        Bạn là \(companion.name), \(companion.persona). Bạn đang nhắn tin với một người bạn là dược sĩ làm ca trực, trong ứng dụng Hope. Hãy nhắn như người thật đang nhắn tin, KHÔNG viết văn, nhưng phải thật sự hiểu chuyện, có kiến thức và đáng tin.

        ĐỘ DÀI THEO TÌNH HUỐNG (ĐỘ DÀI THEO TÌNH HUỐNG quan trọng hơn mọi thứ khác):
        - Chào hỏi, chuyện phiếm, than thở ngắn: 1 đến 3 câu ngắn, ấm áp.
        - Khi bạn ấy HỎI điều gì (cách làm, vì sao, nên chọn gì, kiến thức, chuyện nghề dược, chuyện đời sống): trả lời cho đến nơi đến chốn, khoảng 4 đến 8 câu (tối đa khoảng 150 từ), có thể chia hai đoạn ngắn. Nói thẳng câu trả lời trước, rồi giải thích lý do hoặc cơ chế, rồi đưa ví dụ hoặc bước làm cụ thể.
        - Khi họ kể chuyện khó khăn: đọc ra điều họ thật sự cần (được lắng nghe, được động viên hay muốn cách giải quyết), gọi đúng tên điều họ đang trải qua ở mức cụ thể, rồi mới hỏi hoặc gợi ý MỘT bước nhỏ làm được ngay.
        - Câu trả lời dài vẫn phải giữ đúng giọng riêng của nhân vật.

        CÁCH NÓI:
        - Tiếng Việt đời thường, như nhắn cho bạn thân. Dùng từ khẩu ngữ: ừ, à, hả, nha, nhé, ơi, thôi, luôn, ghê, thiệt.
        - Cấm ẩn dụ, so sánh hoa mỹ, hình ảnh thơ mộng, câu cảm thán sáo rỗng, từ ngữ trang trọng hay văn chương.
        - Nhắc đúng chi tiết họ nêu (ví dụ "khách đông", "bị la"), nhớ những gì đã nói trước đó trong cuộc trò chuyện và nối tiếp nó, đừng hỏi lại điều đã biết.
        - Không nói khuôn mẫu kiểu "mình hiểu cảm giác của bạn", không khuyên chung chung kiểu "hãy tích cực lên".

        NHẬN BIẾT NGỮ CẢNH (đừng lúc nào cũng khuyên nghỉ ngơi):
        - Đọc chính những gì bạn ấy viết để biết họ đang thế nào. Chỉ nhắc nghỉ ngơi, uống nước, ăn cơm hay thở sâu khi họ nói hoặc ngụ ý là mệt, kiệt sức, buồn ngủ, đuối, căng thẳng, hoặc khi giờ giấc thật sự hợp lý. Nếu họ đang vui, đang hỏi kiến thức, đang bàn việc hay tò mò chuyện gì thì cứ trả lời đúng điều họ hỏi, đừng chen câu khuyên nghỉ vào.
        - Đã khuyên nghỉ ngơi rồi thì không lặp lại ở các lượt sau, trừ khi họ lại than mệt.
        - Mỗi tin nhắn có dòng "Bối cảnh" cho biết giờ, thứ, ngày trên điện thoại của bạn ấy. Dùng nó để hiểu họ: sáng sớm thì chào dịu; gần giờ ăn mới hỏi ăn chưa nếu hợp chuyện; khuya mà họ còn thức và có vẻ mệt thì nhẹ nhàng nhắc một lần, đừng giảng đạo; ngày thường và cuối tuần cũng khác nhau. KHÔNG tự đoán họ đang đi ca hay đang ở nhà, vì bạn không biết lịch ca của họ; chỉ nói về công việc khi chính họ nhắc. Đừng đọc giờ ra như đọc đồng hồ, chỉ dùng khi tự nhiên.
        - Nét tính cách riêng của bạn (như hay hỏi uống nước, rủ vươn vai) chỉ dùng khi hợp ngữ cảnh, không phải câu cửa miệng.

        SỰ THẬT VÀ AN TOÀN:
        - Chỉ nói điều bạn chắc là đúng. Không chắc thì nói thẳng là không chắc. Không bịa số liệu, tên thuốc, tên nghiên cứu hay lời trích dẫn.
        - Kiến thức chung về sức khỏe, thuốc và nghề dược thì trả lời có hiểu biết như một đồng nghiệp giỏi. Còn liều dùng hay quyết định lâm sàng cụ thể cho một bệnh nhân thì nhắc đối chiếu dược thư hoặc hỏi dược sĩ lâm sàng, bác sĩ (một câu thôi, không giảng đạo). Không chẩn đoán bệnh cho chính người đang nhắn.
        - Không emoji, không markdown (không dấu *, #, không gạch đầu dòng), không dấu ngoặc kép, không nhắc mình là AI.
        - Nếu họ có dấu hiệu muốn tự làm hại bản thân, hãy nhắn thật tự nhiên và nhẹ nhàng, khuyên họ nói ngay với người thân hoặc người có chuyên môn.

        TÍNH CÁCH: \(companion.style)
        \(examples.isEmpty ? "" : "\nVÍ DỤ GIỌNG CỦA \(companion.name.uppercased()) (chỉ để học giọng, KHÔNG phải độ dài câu trả lời):\n\(examples)\n")
        Chỉ trả về đúng lời nhắn của \(companion.name), không ghi tên ở đầu.
        """
    }

    /// Tách ra để kiểm thử: lời nhắc hệ thống và nội dung gửi đi cho một lượt trả lời.
    static func chatPrompt(companion: HopeCompanion, history: [ChatMessage], text: String,
                           now: Date = .now, calendar: Calendar = .current) -> (system: String, user: String) {
        let past = history.suffix(12).map { ($0.fromUser ? "Bạn: " : "\(companion.name): ") + $0.text }.joined(separator: "\n")
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(800))
        let user = deviceTimeContext(now: now, calendar: calendar) + "\n"
            + (past.isEmpty ? "" : "Cuộc trò chuyện trước:\n\(past)\n") + "Bạn: \(trimmed)\n\(companion.name):"
        return (chatSystemPrompt(for: companion), user)
    }

    /// Dòng bối cảnh theo giờ trên thiết bị (giờ, thứ, ngày, buổi trong ngày). Không đoán ca làm việc.
    static func deviceTimeContext(now: Date = .now, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm, EEEE, d/M/yyyy"
        let daypart = HealingContent.daypart(for: now, calendar: calendar)
        return "Bối cảnh: bây giờ là \(formatter.string(from: now)) (\(daypart)), theo giờ trên điện thoại của bạn ấy."
    }

    /// Trả về nil khi Gemini không trả lời được, để nơi gọi dùng lời đáp viết sẵn.
    static func chat(companion: HopeCompanion, history: [ChatMessage], text: String) async -> HealingNote? {
        let prompt = chatPrompt(companion: companion, history: history, text: text)
        guard let result = await GeminiClient.shared.generate(system: prompt.system, user: prompt.user, maxOutputTokens: 2048, budget: 90, attemptTimeout: 45, preferQuality: true),
              var reply = cleaned(result.text) else { return nil }
        // Phòng trường hợp model tự ghi tên nhân vật ở đầu, và viết hoa chữ đầu câu.
        if reply.lowercased().hasPrefix(companion.name.lowercased() + ":") {
            reply = String(reply.dropFirst(companion.name.count + 1)).trimmingCharacters(in: .whitespaces)
        }
        guard reply.count >= 2 else { return nil }
        let capitalised = reply.prefix(1).uppercased() + reply.dropFirst()
        return HealingNote(text: String(capitalised.prefix(1200)), isAI: true)
    }
}

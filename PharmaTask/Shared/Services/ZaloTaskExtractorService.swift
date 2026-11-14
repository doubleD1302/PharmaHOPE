import Foundation

public struct ParsedZaloResponse: Codable {
    public struct RawTask: Codable {
        public let title: String
        public let notes: String?
        public let dueTime: String?
        public let isBeforeShiftEnd: Bool?
        public let priority: String
    }
    public let tasks: [RawTask]
}

public final class ZaloTaskExtractorService {
    public static let shared = ZaloTaskExtractorService()
    
    // UserDefaults App Group key để người dùng có thể đổi API key trong Settings app
    private let appGroupDefaults = UserDefaults(suiteName: SharedModelContainer.appGroupID)
    
    private var geminiApiKey: String {
        if let key = appGroupDefaults?.string(forKey: "GEMINI_API_KEY"), !key.isEmpty {
            return key
        }
        return ""
    }
    
    private let systemPrompt = """
    Bạn là trợ lý ảo AI cao cấp cho nhân viên nhà thuốc bán lẻ tại Việt Nam (Pharmacity, Long Châu, An Khang).
    Nhiệm vụ của bạn là đọc tin nhắn giao việc từ Trưởng ca / Dược sĩ quản lý trên nhóm Zalo nội bộ và phân tách thành danh sách công việc chuẩn hóa.
    
    TỪ LÓNG & THUẬT NGỮ ĐẶC THÙ NGÀNH DƯỢC / BÁN LẺ:
    - "Cận date": Thuốc sắp hết hạn sử dụng (dưới 6 tháng hoặc dưới 1 năm).
    - "Kiểm tồn / Check tồn": Kiểm đếm số lượng thực tế trong tủ/kệ so với phần mềm bán hàng.
    - "Tem phụ": Dán nhãn phụ tiếng Việt lên hộp thuốc nhập khẩu.
    - "Bảo quản lạnh / Tủ mát": Tủ 2 - 8°C chứa vắc xin, huyết thanh, men vi sinh, insulin.
    - "POS / Bill hủy": Xử lý sự cố hóa đơn máy tính tiền quầy.
    - "Két tiền / Kết quỹ / Chốt ca": Kiểm đếm tiền mặt, ký biên bản bàn giao và nộp tiền két.
    - "Đơn Grab / Shopee": Đóng gói hàng giao cho shipper hỏa tốc.
    - "Soạn hàng gối đầu / Nhập kho": Bốc dỡ kiện hàng từ xe trung chuyển vào kho thuốc.
    
    QUY TẮC PHÂN LOẠI MỨC ĐỘ ƯU TIÊN:
    - "high": Công việc có mốc giờ cụ thể, việc liên quan đến tài chính/tiền mặt, bảo quản thuốc lạnh hỏng hóc, hoặc tin nhắn có từ "gấp", "ngay", "khẩn", "trước ...h".
    - "medium": Các công việc kiểm kê, soạn hàng, dán tem phụ, hỗ trợ khách quen thực hiện trong suốt ca.
    - "low": Vệ sinh quầy kệ, đổ rác, gom hóa đơn, chốt sổ cuối ca.
    
    YÊU CẦU ĐẦU RA:
    Trả về ĐÚNG định dạng JSON thuần túy, TUYỆT ĐỐI KHÔNG thêm bất kỳ ghi chú ngoài hoặc thẻ markdown ```json :
    {
      "tasks": [
        {
          "title": "Hành động cụ thể, ngắn gọn dưới 45 ký tự để vừa màn hình khóa",
          "notes": "Thông tin chi tiết: số lượng, tên thuốc, vị trí tủ, lưu ý của quản lý",
          "dueTime": "HH:mm nếu có giờ hẹn chót (VD: '11:00'), ngược lại null",
          "isBeforeShiftEnd": true,
          "priority": "high" | "medium" | "low"
        }
      ]
    }
    """
    
    private init() {}
    
    /// Bóc tách văn bản thô từ tin nhắn Zalo thành danh sách TaskItem
    public func extractTasks(from rawText: String) async throws -> [TaskItem] {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count <= 200_000 else {
            throw HopeDataError.invalid("Tin nhắn quá dài. Mỗi lần hỗ trợ tối đa 200.000 ký tự.")
        }
        let apiKey = geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Chưa có Gemini API Key. Hãy nhập khóa trong Cài đặt."])
        }
        
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        
        let requestBody: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": "Phân tích tin nhắn Zalo giao việc sau đây:\n\n\(trimmed)"]]
                ]
            ],
            "generationConfig": [
                "response_mime_type": "application/json",
                "temperature": 0.1
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message: String
            switch status {
            case 401, 403: message = "API Key không hợp lệ hoặc chưa có quyền gọi Gemini."
            case 429: message = "Gemini đã hết hạn mức hoặc đang giới hạn yêu cầu. Vui lòng thử lại sau."
            default: message = "Không gọi được Gemini (HTTP \(status)). Vui lòng kiểm tra kết nối và cấu hình."
            }
            throw NSError(domain: "GeminiAPI", code: status, userInfo: [NSLocalizedDescriptionKey: message])
        }
        
        struct GeminiAPIResponse: Codable {
            struct Candidate: Codable {
                struct Content: Codable {
                    struct Part: Codable {
                        let text: String?
                    }
                    let parts: [Part]
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }
        
        let geminiResult = try JSONDecoder().decode(GeminiAPIResponse.self, from: data)
        let rawJsonString = geminiResult.candidates?.first?.content?.parts.compactMap { $0.text }.joined() ?? ""
        guard !rawJsonString.isEmpty, let jsonData = rawJsonString.data(using: .utf8) else {
            throw NSError(domain: "GeminiAPI", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không đọc được JSON từ phản hồi AI."])
        }
        
        let parsed = try JSONDecoder().decode(ParsedZaloResponse.self, from: jsonData)
        return try parsed.tasks.map { item in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let priority = TaskPriority(rawValue: item.priority),
                  item.dueTime == nil || item.dueTime?.range(of: "^([01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil else {
                throw NSError(domain: "GeminiAPI", code: -4, userInfo: [NSLocalizedDescriptionKey: "AI trả về tên việc, mức ưu tiên hoặc giờ hẹn không hợp lệ. Chưa lưu kết quả."])
            }
            return TaskItem(
                title: title,
                notes: item.notes,
                priority: priority,
                dueTime: item.dueTime
            )
        }
    }
}

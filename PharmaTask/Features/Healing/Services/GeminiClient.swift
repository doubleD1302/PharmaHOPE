import Foundation

/// Chọn model Gemini: ưu tiên bản Flash-Lite mới nhất (rẻ nhất hiện hành), rồi Flash mới nhất,
/// rồi các bí danh `-latest`. Danh sách lấy từ API nên tự cập nhật khi Google ra bản mới.
public enum GeminiModelPicker {
    struct Parsed: Equatable {
        let id: String
        let version: Double
        let isLite: Bool
        let isPreview: Bool
    }

    /// Bản dự phòng cuối cùng khi không lấy được danh sách và các bí danh đều lỗi.
    public static let seedModels = ["gemini-3.5-flash-lite", "gemini-3.8-flash", "gemini-3.6-flash"]
    public static let aliasModels = ["gemini-flash-lite-latest", "gemini-flash-latest"]

    /// Nhận `gemini-<phiên bản>-flash[-lite][-preview][-ngày]`. Loại ảnh, giọng nói, live, embedding…
    static func parse(_ rawName: String) -> Parsed? {
        let id = rawName.hasPrefix("models/") ? String(rawName.dropFirst("models/".count)) : rawName
        let parts = id.split(separator: "-").map(String.init)
        guard parts.count >= 3, parts[0] == "gemini", let version = Double(parts[1]), parts[2] == "flash" else { return nil }
        var rest = Array(parts.dropFirst(3))
        var lite = false
        if rest.first == "lite" { lite = true; rest.removeFirst() }
        var preview = false
        for token in rest {
            if token == "preview" { preview = true }
            else if token.allSatisfy(\.isNumber) { continue }
            else { return nil }
        }
        return Parsed(id: id, version: version, isLite: lite, isPreview: preview)
    }

    private static func rankedByVersion(_ items: [Parsed]) -> [Parsed] {
        items.sorted { a, b in
            if a.version != b.version { return a.version > b.version }
            if a.isPreview != b.isPreview { return !a.isPreview }
            return a.id.count < b.id.count
        }
    }

    /// Thứ tự thử: hai Flash-Lite mới nhất, hai Flash mới nhất, bí danh, bản cố định.
    /// `preferFull`: dùng cho trò chuyện cần hiểu sâu, thử Flash đầy đủ trước rồi mới tới Flash-Lite.
    public static func chain(from discovered: [String], preferred: String? = nil, preferFull: Bool = false) -> [String] {
        let parsed = discovered.compactMap(parse)
        let lite: [String] = rankedByVersion(parsed.filter { $0.isLite }).prefix(2).map { $0.id }
        let full: [String] = rankedByVersion(parsed.filter { !$0.isLite }).prefix(2).map { $0.id }
        var ordered: [String] = preferFull ? full + lite : lite + full
        ordered += preferFull ? Array(aliasModels.reversed()) : aliasModels
        ordered += seedModels
        if let preferred, !preferred.isEmpty { ordered.insert(preferred, at: 0) }
        var seen = Set<String>()
        return ordered.filter { seen.insert($0).inserted }
    }
}

public struct GeminiResult: Sendable {
    public let text: String
    public let model: String
}

/// Gọi Gemini. Không bao giờ ném lỗi: trả nil để nơi gọi dùng nội dung viết sẵn.
public actor GeminiClient {
    public static let shared = GeminiClient()

    private let base = "https://generativelanguage.googleapis.com/v1beta"
    private let session: URLSession
    private let defaults = UserDefaults.standard
    private let modelsKey = "gemini.models.v1"
    private let modelsDateKey = "gemini.models.date"
    private let lastGoodKey = "gemini.lastGoodModel"
    private let maximumAttempts = 4
    /// Tổng thời gian tối đa cho một lần xin nội dung (gồm lấy danh sách model). Quá hạn thì dùng nội dung viết sẵn.
    public static let totalBudget: TimeInterval = 15

    public init(session: URLSession = .shared) { self.session = session }

    // MARK: - Chọn model

    func discoverModels(key: String, deadline: Date = Date().addingTimeInterval(GeminiClient.totalBudget)) async -> [String] {
        if let date = defaults.object(forKey: modelsDateKey) as? Date, Date().timeIntervalSince(date) < 24 * 3600,
           let cached = defaults.stringArray(forKey: modelsKey), !cached.isEmpty { return cached }
        var names: [String] = []
        var pageToken: String?
        for _ in 0..<3 {
            let remaining = Self.timeout(upTo: 8, until: deadline)
            guard remaining >= Self.minimumAttemptTime else { break }
            var components = URLComponents(string: "\(base)/models")
            components?.queryItems = [URLQueryItem(name: "pageSize", value: "200")] + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            guard let url = components?.url else { break }
            var request = URLRequest(url: url, timeoutInterval: remaining)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let page = Self.parseModelList(data) else { break }
            names += page.names
            pageToken = page.next
            if pageToken == nil { break }
        }
        if !names.isEmpty {
            defaults.set(names, forKey: modelsKey)
            defaults.set(Date(), forKey: modelsDateKey)
        }
        return names
    }

    static func parseModelList(_ data: Data) -> (names: [String], next: String?)? {
        struct List: Decodable {
            struct Model: Decodable { let name: String; let supportedGenerationMethods: [String]? }
            let models: [Model]?
            let nextPageToken: String?
        }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else { return nil }
        let names = (list.models ?? [])
            .filter { $0.supportedGenerationMethods?.contains("generateContent") ?? false }
            .map(\.name)
        let token = list.nextPageToken?.isEmpty == false ? list.nextPageToken : nil
        return (names, token)
    }

    // MARK: - Gọi model

    /// `budget`: tổng thời gian chờ, `attemptTimeout`: chờ tối đa cho mỗi model. Mặc định 15 và 12 giây; trò chuyện cho phép chờ lâu hơn.
    public func generate(system: String, user: String, maxOutputTokens: Int = 1024,
                         budget: TimeInterval = GeminiClient.totalBudget, attemptTimeout: TimeInterval = 12,
                         preferQuality: Bool = false) async -> GeminiResult? {
        guard let key = GeminiKeyStore.load() else { return nil }
        let deadline = Date().addingTimeInterval(budget)
        let discovered = await discoverModels(key: key, deadline: deadline)
        // Trả lời sâu thì ưu tiên model mạnh và không bám theo model nhẹ từng chạy được.
        let chain = GeminiModelPicker.chain(from: discovered, preferred: preferQuality ? nil : defaults.string(forKey: lastGoodKey), preferFull: preferQuality)
        var networkFailures = 0
        for model in chain.prefix(maximumAttempts) {
            if Task.isCancelled { return nil }
            let timeout = Self.timeout(upTo: attemptTimeout, until: deadline)
            if timeout < Self.minimumAttemptTime { return nil }   // hết ngân sách thời gian
            switch await attempt(model: model, key: key, system: system, user: user, maxOutputTokens: maxOutputTokens, timeout: timeout) {
            case .success(let text):
                if !preferQuality { defaults.set(model, forKey: lastGoodKey) }
                return GeminiResult(text: text, model: model)
            case .badKey:
                return nil
            case .networkFailure:
                networkFailures += 1
                if networkFailures >= 2 { return nil }
            case .modelGone:
                if defaults.string(forKey: lastGoodKey) == model { defaults.removeObject(forKey: lastGoodKey) }
                // Chỉ khi model bị gỡ (404) mới làm mới danh sách vào lần sau; lỗi tạm thời (429, 5xx) thì giữ danh sách.
                defaults.removeObject(forKey: modelsDateKey)
            case .tryNext:
                if defaults.string(forKey: lastGoodKey) == model { defaults.removeObject(forKey: lastGoodKey) }
            }
        }
        return nil
    }


    private enum Attempt { case success(String), badKey, networkFailure, modelGone, tryNext }

    static let minimumAttemptTime: TimeInterval = 2

    /// Thời gian chờ cho một yêu cầu: tối đa `limit` giây, không vượt quá phần còn lại của ngân sách.
    static func timeout(upTo limit: TimeInterval, until deadline: Date, now: Date = Date()) -> TimeInterval {
        max(0, min(limit, deadline.timeIntervalSince(now)))
    }

    /// Chỉ gửi tham số tối thiểu (không nhiệt độ, không cấu hình thinking) để chạy được trên mọi đời Gemini.
    static func requestBody(system: String, user: String, maxOutputTokens: Int) -> [String: Any] {
        [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": user]]]],
            "generationConfig": ["maxOutputTokens": maxOutputTokens]
        ]
    }

    private func attempt(model: String, key: String, system: String, user: String, maxOutputTokens: Int, timeout: TimeInterval) async -> Attempt {
        guard let url = URL(string: "\(base)/models/\(model):generateContent"),
              let payload = try? JSONSerialization.data(withJSONObject: Self.requestBody(system: system, user: user, maxOutputTokens: maxOutputTokens))
        else { return .tryNext }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = payload
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) {
                if let text = Self.extractText(data) { return .success(text) }
                return .tryNext
            }
            if status == 401 { return .badKey }
            if status == 400 || status == 403, String(decoding: data, as: UTF8.self).contains("API_KEY") { return .badKey }
            if status == 404 { return .modelGone }
            return .tryNext // 429 (hết hạn mức), 5xx, các lỗi 400 khác
        } catch {
            return .networkFailure
        }
    }

    static func extractText(_ data: Data) -> String? {
        struct Response: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable { struct Part: Decodable { let text: String?; let thought: Bool? }; let parts: [Part]? }
                let content: Content?
            }
            let candidates: [Candidate]?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let text = (response.candidates?.first?.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

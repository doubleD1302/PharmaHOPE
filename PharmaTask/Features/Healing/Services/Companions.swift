import Foundation

/// Một tin nhắn trong cuộc trò chuyện với nhân vật.
struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let fromUser: Bool
    let text: String
    let isAI: Bool
    let date: Date
}

/// Một cặp câu mẫu để Gemini bắt chước giọng của nhân vật.
struct ChatExample: Equatable, Sendable {
    let user: String
    let reply: String
}

/// Người bạn trong vườn mà bạn có thể trò chuyện: Hope (cây non) và các con vật. Mỗi nhân vật có tính cách và cách nói riêng.
struct HopeCompanion: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// Mô tả nhân vật, đưa vào lời nhắc cho Gemini.
    let persona: String
    /// Cách nói và cách phản hồi, đưa vào lời nhắc để mỗi nhân vật trả lời một kiểu.
    let style: String
    /// Vài câu mẫu cho thấy giọng nhắn tin của nhân vật.
    let examples: [ChatExample]
    let opener: String
    let hello: [String]
    /// Lời đáp viết sẵn theo từng tình huống, dùng khi không có Gemini.
    let soft: [String]
    let tired: [String]
    let joy: [String]
    let thanks: [String]
}

enum CompanionCatalog {
    private static let hope = HopeCompanion(
        id: "Mascot", name: "Hope",
        persona: "một cây non trong khu vườn, điềm đạm, ít lời, ấm áp và biết lắng nghe",
        style: "Điềm đạm, nói ít, giọng ấm như một người bạn lớn tuổi hơn một chút. Hỏi han đơn giản, thật lòng. Hiếm khi mới nhắc đến cây cối, không dùng hình ảnh thơ mộng.",
        examples: [ChatExample(user: "Hôm nay khách đông quá", reply: "Nghe mệt thật đó. Bạn ăn gì chưa?"),
                   ChatExample(user: "Mình bị khách la", reply: "Chuyện đó khó chịu lắm. Bạn muốn kể mình nghe, hay muốn ngồi yên một chút?"),
                   ChatExample(user: "Mình ổn rồi", reply: "Ừ, vậy là tốt rồi. Cứ thong thả nha.")],
        opener: "Chào bạn. Hôm nay sao rồi?",
        hello: ["Chào bạn, mình đây.", "Bạn ghé chơi hả? Vui ghê.", "Ngồi nghỉ chút nha."],
        soft: ["Mình nghe nè. Bạn cứ kể từ từ nha.", "Ừ, mình hiểu. Rồi sao nữa?", "Bạn không cần nói hết đâu, cứ ngồi đây chút cũng được."],
        tired: ["Nghe mệt thật đó. Bạn uống nước chưa?", "Mệt thì nghỉ chút đi nha. Việc kia chờ được mà."],
        joy: ["Nghe vui ghê. Kể mình nghe thêm đi."],
        thanks: ["Không có chi đâu. Cần thì cứ ghé nha."])

    private static let rabbit = HopeCompanion(
        id: "046", name: "Thỏ",
        persona: "chú thỏ nhút nhát nhưng rất tốt bụng, hay lắng nghe",
        style: "Nhút nhát, nói nhỏ nhẹ, câu ngắn, hay mở đầu hoặc ngập ngừng bằng \"ừm…\". Lắng nghe trước, hỏi lại đúng MỘT câu hỏi nhẹ. Hay hỏi về cơ thể: uống nước chưa, ăn chưa, vai có căng không. Tuyệt đối không đùa cợt, không thúc giục, không dùng dấu chấm than.",
        examples: [ChatExample(user: "Hôm nay khách đông quá", reply: "Ừm… nghe mệt ghê. Bạn uống nước chưa?"),
                   ChatExample(user: "Mình bị khách la", reply: "Ôi… chắc bạn buồn lắm hả. Chuyện sao vậy, bạn kể mình nghe được không?"),
                   ChatExample(user: "Mình ổn rồi", reply: "Ừm, vậy thì tốt rồi. Mình vẫn ở đây nha.")],
        opener: "Ừm… chào bạn. Bạn khỏe không?",
        hello: ["Ừm… chào bạn. Mình nhảy qua chào thôi nè.", "Bạn ngồi xuống chút không?", "Ừm… bạn khỏe không?"],
        soft: ["Ừm… mình nghe nè. Bạn kể tiếp đi.", "Ừm, rồi sao nữa hả?", "Chỗ nào trong người bạn đang nặng nhất vậy?"],
        tired: ["Ừm… nghe mệt ghê. Bạn uống nước chưa?", "Ôi… vậy bạn ngồi xuống chút đi. Rồi kể mình nghe chuyện gì mệt nhất nha."],
        joy: ["Ừm, nghe vui quá. Kể mình nghe thêm đi."],
        thanks: ["Có gì đâu mà… Cần thì mình ở đây nha."])

    private static let sparrow = HopeCompanion(
        id: "051", name: "Chim sẻ",
        persona: "chú chim sẻ lanh lợi, tinh nghịch, nhiều năng lượng",
        style: "Nói nhanh, vui, tếu táo, hay mở đầu bằng \"Chiếp!\". Hay trêu bạn một cách dễ thương, dùng dấu chấm than, hay phản ứng thay bạn (\"khách gì mà dữ vậy trời!\"). Rủ bạn làm NGAY một việc nhỏ (đứng dậy, vươn vai, uống nước). Không giảng giải, không ngập ngừng.",
        examples: [ChatExample(user: "Hôm nay khách đông quá", reply: "Chiếp! Đông vậy là đắt hàng còn gì! Mà giờ đứng dậy vươn vai cái đã nha!"),
                   ChatExample(user: "Mình bị khách la", reply: "Chiếp, khách gì mà dữ vậy trời! Thôi bỏ qua đi, uống miếng nước cái nào!"),
                   ChatExample(user: "Mình ổn rồi", reply: "Chiếp! Vậy mới là bạn chứ! Giờ kể mình nghe đi, hôm nay có gì vui không?")],
        opener: "Chiếp! Hôm nay thế nào rồi bạn?",
        hello: ["Chiếp! Chào bạn! Hôm nay thế nào?", "Chiếp chiếp! Lại gặp rồi nè!", "Ê, kể mình nghe chuyện hôm nay đi!"],
        soft: ["Chiếp! Mình nghe nè, kể tiếp đi!", "Ủa rồi sao nữa? Kể đi kể đi!", "Chiếp, thôi đứng dậy đi vài bước cái cho khỏe người nha!"],
        tired: ["Chiếp! Mệt hả? Vậy nghỉ ba hơi thở thôi nha, mình đếm: một, hai, ba!", "Chiếp, thương ghê. Đứng dậy uống miếng nước đi bạn!"],
        joy: ["Chiếp! Chuyện gì vui vậy? Kể nhanh đi!"],
        thanks: ["Chiếp! Có gì đâu! Mai ghé nữa nha!"])

    /// Các con vật còn lại: tính cách ngắn gọn, cùng một bộ lời đáp dịu.
    private static let others: [String: (String, String, String)] = [
        "047": ("chú nhím con hơi nhát, cuộn tròn khi ngại, thích chỗ yên tĩnh", "Nói nhỏ và chậm, hay ngại ngùng rồi mới mở lòng.", "Mình ló đầu ra rồi nè. Bạn khỏe không?"),
        "048": ("chú hươu con nhẹ nhàng, hay ngắm cây cối", "Nói dịu và thong thả, hay nhắc những điều đẹp nhỏ quanh mình.", "Chào bạn. Ở đây nắng đang đẹp lắm."),
        "049": ("chú sóc nhanh nhẹn, hay cất hạt dẻ cho ngày mai", "Nói nhanh gọn, hay nhắc làm từng việc nhỏ một.", "Chào bạn! Mình vừa cất xong hạt dẻ. Bạn đang bận gì thế?"),
        "050": ("chú chim cổ đỏ hay hót nhỏ vào buổi sớm", "Nói ấm và đều, hay nhắc những buổi sáng mới.", "Chào bạn. Mình vừa hót một câu cho hôm nay."),
        "052": ("chú chim xanh hiền, thích đứng trên cao nhìn xa", "Nói điềm tĩnh, hay giúp bạn nhìn mọi việc từ xa hơn.", "Chào bạn. Từ trên cao nhìn xuống, bạn đang làm tốt đó."),
        "053": ("cánh bướm trắng nhẹ như gió", "Nói ngắn, mơ màng.", "Chào bạn. Mình đậu xuống một chút nhé."),
        "054": ("cánh bướm vàng vui tính, thích hoa và nắng", "Nói tươi và ngắn.", "Chào bạn! Hôm nay hoa nở đẹp lắm."),
        "055": ("chú ong chăm chỉ nhưng biết dừng lại nghỉ", "Nói gọn, hay nhắc làm từng việc một rồi nghỉ.", "Vo ve. Bạn cũng đang làm việc nhiều à? Nghỉ một chút nhé."),
        "056": ("chú bọ rùa nhỏ, may mắn và tò mò", "Nói nhỏ, tò mò.", "Chào bạn. Mình đang bò qua chiếc lá này."),
        "057": ("chú ếch vui tính, thích tiếng mưa", "Nói pha chút đùa nhẹ.", "Ộp! Chào bạn. Hôm nay trời có vẻ sắp mưa."),
        "058": ("chú chuồn chuồn lặng lẽ, bay là là mặt nước", "Nói ít và nhẹ.", "Chào bạn. Mặt nước hôm nay phẳng lắm."),
        "059": ("chú ốc sên chậm rãi, tin rằng đi chậm vẫn tới nơi", "Nói thong thả, hay khen sự kiên trì.", "Chào bạn. Mình đến hơi chậm, nhưng mình đến rồi."),
        "060": ("chú vịt con tròn trịa, hay tò mò", "Nói ngây ngô và ấm.", "Quạc! Chào bạn. Mình mới học bơi xong."),
        "061": ("chú chim nhỏ hót khẽ, hay đậu cạnh người buồn", "Nói nhẹ, hay ở cạnh bạn.", "Chào bạn. Mình đậu cạnh bạn được không?"),
        "062": ("chú sâu nhỏ đang chờ ngày thành bướm", "Nói chậm, tin rằng thay đổi cần thời gian.", "Chào bạn. Mình đang chờ một điều đẹp, bạn cũng thế à?"),
        "063": ("chú rùa điềm đạm, sống lâu và hay kể chuyện ngắn", "Nói trầm và chắc, thỉnh thoảng kể một chuyện rất ngắn.", "Chào bạn. Cứ từ từ, không việc gì phải vội."),
        "064": ("cánh bướm đêm dịu, thích ánh đèn lồng", "Nói thì thầm.", "Chào bạn. Đèn trong vườn đẹp lắm, bạn thấy không?"),
        "065": ("chú cáo con tinh nghịch nhưng tử tế", "Nói thông minh và ấm, hay hỏi han khéo.", "Chào bạn. Mình thấy bạn có vẻ đang nghĩ nhiều. Kể mình nghe nhé?")
    ]

    static let all: [HopeCompanion] = ([GardenCreature.mascot] + GardenCreature.animals).map { creature in
        switch creature.id {
        case "Mascot": return hope
        case "046": return rabbit
        case "051": return sparrow
        default:
            let info = others[creature.id]
            let opener = info?.2 ?? "Chào bạn. Mình ở đây nghe bạn."
            return HopeCompanion(
                id: creature.id, name: creature.name,
                persona: info?.0 ?? "một người bạn nhỏ trong khu vườn, hiền và ấm",
                style: info?.1 ?? "Nói nhẹ và ấm.",
                examples: [],
                opener: opener,
                hello: [opener, "Mình ở đây nè.", "Ngồi chơi chút nha."],
                soft: ["Mình nghe nè. Bạn kể tiếp đi.", "Ừ, rồi sao nữa?", "Bạn không cần nói hết đâu, cứ ngồi đây chút cũng được."],
                tired: ["Nghe mệt thật đó. Bạn nghỉ chút đi nha."],
                joy: ["Nghe vui ghê. Kể mình nghe thêm đi."],
                thanks: ["Không có chi đâu. Cần thì cứ ghé nha."])
        }
    }

    static func companion(id: String) -> HopeCompanion { all.first { $0.id == id } ?? all[0] }
}

/// Lưu lịch sử trò chuyện trên máy (UserDefaults), tối đa 60 tin mỗi nhân vật.
enum CompanionChatStore {
    static let maximumMessages = 60
    private static func key(_ id: String) -> String { "hope.chat." + id }

    static func load(_ id: String, defaults: UserDefaults = .standard) -> [ChatMessage] {
        guard let data = defaults.data(forKey: key(id)),
              let list = try? JSONDecoder().decode([ChatMessage].self, from: data) else { return [] }
        return list
    }

    static func save(_ messages: [ChatMessage], for id: String, defaults: UserDefaults = .standard) {
        let trimmed = Array(messages.suffix(maximumMessages))
        if let data = try? JSONEncoder().encode(trimmed) { defaults.set(data, forKey: key(id)) }
    }

    static func clear(_ id: String, defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key(id)) }
}

/// Lời đáp viết sẵn khi không có Gemini (không khóa, không mạng, hoặc lỗi). Mỗi nhân vật nói một kiểu.
enum CompanionReply {
    static func offline(_ companion: HopeCompanion, to text: String, tick: Int = Int(Date().timeIntervalSince1970)) -> String {
        let t = TaskText.normalized(text)
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        func pick(_ list: [String]) -> String { list[abs(tick) % max(1, list.count)] }
        if has(["cam on", "biet on"]) { return pick(companion.thanks) }
        if has(["met", "kiet", "chan", "buon", "stress", "cang", "ap luc", "qua tai", "khoc"]) { return pick(companion.tired) }
        if has(["vui", "nhe nhom", "tot "]) { return pick(companion.joy) }
        if has(["chao", "hello", "xin chao"]) { return pick(companion.hello) }
        return pick(companion.soft)
    }
}

/// Một câu trích có tác giả.
struct HopeQuote: Equatable, Sendable {
    let text: String
    let author: String
}

/// Câu trích hiển thị đầu vườn. Mọi câu lấy từ nguồn có thật (Wikiquote, tục ngữ), đã đối chiếu nguyên văn, lời Việt do mình dịch.
/// Không dùng những câu hay bị gán nhầm (ví dụ "thành công không phải là cuối cùng…" gán cho Churchill).
enum HopeQuotes {
    static let all: [HopeQuote] = [
        HopeQuote(text: "Từng thử. Từng thất bại. Không sao. Thử lại. Lại thất bại. Thất bại cho tốt hơn.", author: "Samuel Beckett"),
        HopeQuote(text: "Cuộc sống không dễ dàng với bất kỳ ai trong chúng ta. Nhưng có sao đâu? Ta phải kiên trì, và hơn hết là tin vào chính mình.", author: "Marie Curie"),
        HopeQuote(text: "Hành trình ngàn dặm bắt đầu từ một bước chân.", author: "Lão Tử"),
        HopeQuote(text: "Ngã bảy lần, đứng dậy tám lần.", author: "Tục ngữ Nhật Bản"),
        HopeQuote(text: "Đường đi khó, không khó vì ngăn sông cách núi, mà khó vì lòng người ngại núi e sông.", author: "Nguyễn Bá Học"),
        HopeQuote(text: "Không có việc gì khó, chỉ sợ lòng không bền. Đào núi và lấp biển, quyết chí ắt làm nên.", author: "Hồ Chí Minh"),
        HopeQuote(text: "Công lao thuộc về người thực sự bước vào đấu trường, người dốc hết sức, dù vấp ngã hết lần này đến lần khác.", author: "Theodore Roosevelt"),
        HopeQuote(text: "Tính cách không thể được rèn trong an nhàn và yên ắng. Chỉ qua thử thách và đau khổ, tâm hồn mới mạnh lên, tầm nhìn sáng ra, hoài bão được khơi dậy và thành công mới đến.", author: "Helen Keller"),
        HopeQuote(text: "Ta có thể gặp nhiều thất bại, nhưng đừng để mình bị đánh bại.", author: "Maya Angelou"),
        HopeQuote(text: "Tôi học được rằng can đảm không phải là không sợ hãi, mà là chiến thắng nỗi sợ.", author: "Nelson Mandela"),
        HopeQuote(text: "Mọi thứ có thể bị lấy đi khỏi con người, trừ một điều: quyền tự do cuối cùng là chọn thái độ của mình trước mọi hoàn cảnh.", author: "Viktor Frankl"),
        HopeQuote(text: "Điều làm con người xao động không phải sự việc, mà là những quan niệm họ gán cho sự việc.", author: "Epictetus"),
        HopeQuote(text: "Ai có một lý do để sống thì chịu đựng được gần như mọi cách sống.", author: "Friedrich Nietzsche"),
        HopeQuote(text: "Lạc quan là niềm tin dẫn đến thành tựu. Không điều gì làm được nếu thiếu hy vọng.", author: "Helen Keller"),
        HopeQuote(text: "Dù thế giới đầy đau khổ, nó cũng đầy những điều vượt qua đau khổ.", author: "Helen Keller"),
        HopeQuote(text: "Giữa mùa đông, tôi nhận ra trong mình có một mùa hè không gì khuất phục nổi.", author: "Albert Camus"),
        HopeQuote(text: "Có công mài sắt, có ngày nên kim.", author: "Tục ngữ Việt Nam"),
        HopeQuote(text: "Lửa thử vàng, gian nan thử sức.", author: "Tục ngữ Việt Nam"),
        HopeQuote(text: "Thất bại là mẹ thành công.", author: "Tục ngữ Việt Nam"),
        HopeQuote(text: "Còn nước còn tát.", author: "Tục ngữ Việt Nam"),
        HopeQuote(text: "Nước chảy đá mòn.", author: "Tục ngữ Việt Nam"),
        HopeQuote(text: "Sau cơn mưa trời lại sáng.", author: "Tục ngữ Việt Nam"),
        HopeQuote(text: "Có chí thì nên.", author: "Tục ngữ Việt Nam"),
        HopeQuote(text: "Kiến tha lâu cũng đầy tổ.", author: "Tục ngữ Việt Nam")
    ]

    /// Câu đầu tiên trong ngày thay đổi theo ngày; `variant` là số lần chạm để đổi câu.
    static func quote(variant: Int, date: Date = .now, calendar: Calendar = .current) -> HopeQuote {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return all[(day + max(variant, 0)) % all.count]
    }
}

import XCTest
@testable import Hope

@MainActor
final class CalendarAndCompanionTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
        c.firstWeekday = 2
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: Lịch tháng

    func testMonthGridHas42DaysStartsOnMondayAndCoversTheMonth() {
        let days = HopeCalendarMath.grid(for: date(2026, 11, 15), calendar: cal)
        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(cal.component(.weekday, from: days[0]), 2)           // thứ Hai
        XCTAssertTrue(cal.isDate(days[0], inSameDayAs: date(2026, 10, 26))) // 1/11/2026 là Chủ nhật
        XCTAssertTrue(days.contains { cal.isDate($0, inSameDayAs: date(2026, 11, 1)) })
        XCTAssertTrue(days.contains { cal.isDate($0, inSameDayAs: date(2026, 11, 30)) })
    }

    func testMonthShiftingStaysOnFirstOfMonth() {
        let next = HopeCalendarMath.shiftMonth(date(2026, 12, 31), by: 1, calendar: cal)
        XCTAssertEqual(cal.component(.month, from: next), 1)
        XCTAssertEqual(cal.component(.day, from: next), 1)
        XCTAssertEqual(cal.component(.year, from: next), 2027)
    }

    func testVisibleRangeCoversAllGridDays() {
        let month = date(2026, 11, 15)
        let range = HopeCalendarMath.visibleRange(for: month, calendar: cal)
        XCTAssertTrue(cal.isDate(range.start, inSameDayAs: date(2026, 10, 26)))
        XCTAssertGreaterThan(range.end, date(2026, 12, 6))
    }

    // MARK: Lặp ca

    func testOvernightShiftEndsNextDayWhenRepeated() throws {
        let rebased = try XCTUnwrap(ShiftRepeat.rebased(start: date(2026, 11, 18, 22), end: date(2026, 11, 19, 6), to: date(2026, 11, 25), calendar: cal))
        XCTAssertTrue(cal.isDate(rebased.start, inSameDayAs: date(2026, 11, 25)))
        XCTAssertTrue(cal.isDate(rebased.end, inSameDayAs: date(2026, 11, 26)))
        XCTAssertEqual(cal.component(.hour, from: rebased.start), 22)
        XCTAssertEqual(cal.component(.hour, from: rebased.end), 6)
    }

    func testRepeatTargetsSkipSourceDayAndRespectWeekdays() {
        // 18/11/2026 là thứ Tư; chọn thứ Tư (2) và thứ Sáu (4) trong 2 tuần.
        let days = ShiftRepeat.targetDays(from: date(2026, 11, 18), weekdays: [2, 4], weeks: 2, calendar: cal)
        XCTAssertEqual(days.count, 3)
        XCTAssertTrue(cal.isDate(days[0], inSameDayAs: date(2026, 11, 20)))
        XCTAssertTrue(cal.isDate(days[1], inSameDayAs: date(2026, 11, 25)))
        XCTAssertTrue(cal.isDate(days[2], inSameDayAs: date(2026, 11, 27)))
    }

    func testRepeatTargetsAreCappedAndRejectBadWeekdays() {
        XCTAssertTrue(ShiftRepeat.targetDays(from: date(2026, 11, 18), weekdays: [9], weeks: 4, calendar: cal).isEmpty)
        XCTAssertLessThanOrEqual(ShiftRepeat.targetDays(from: date(2026, 11, 18), weekdays: Set(0..<7), weeks: 99, calendar: cal).count, 12 * 7)
    }

    // MARK: Khóa dựng sẵn

    func testBundledKeyIgnoresEmptyAndUnexpandedValues() {
        XCTAssertNil(GeminiKeyStore.cleanBundled(""))
        XCTAssertNil(GeminiKeyStore.cleanBundled("   "))
        XCTAssertNil(GeminiKeyStore.cleanBundled("$(GEMINI_API_KEY)"))
        XCTAssertEqual(GeminiKeyStore.cleanBundled("  abc123 \n"), "abc123")
    }

    // MARK: Nhân vật và trò chuyện

    func testCatalogHasHopeAndEveryAnimalWithUniqueIDs() {
        XCTAssertEqual(CompanionCatalog.all.count, GardenCreature.animals.count + 1)
        XCTAssertEqual(Set(CompanionCatalog.all.map(\.id)).count, CompanionCatalog.all.count)
        XCTAssertEqual(CompanionCatalog.companion(id: GardenCreature.mascot.id).name, "Hope")
        XCTAssertEqual(CompanionCatalog.companion(id: "046").name, "Thỏ")
        XCTAssertEqual(CompanionCatalog.companion(id: "khong-co").id, GardenCreature.mascot.id)
        XCTAssertTrue(CompanionCatalog.all.allSatisfy { !$0.persona.isEmpty && !$0.opener.isEmpty && $0.hello.count >= 1 })
    }

    func testOfflineReplyRecognisesTiredAndThanksInEachCharactersOwnWords() {
        let rabbit = CompanionCatalog.companion(id: "046")
        let sparrow = CompanionCatalog.companion(id: "051")
        XCTAssertTrue(rabbit.tired.contains(CompanionReply.offline(rabbit, to: "Hôm nay mình mệt quá", tick: 0)))
        XCTAssertTrue(rabbit.thanks.contains(CompanionReply.offline(rabbit, to: "cảm ơn nhé", tick: 0)))
        XCTAssertTrue(sparrow.tired.contains(CompanionReply.offline(sparrow, to: "Hôm nay mình mệt quá", tick: 0)))
        XCTAssertFalse(CompanionReply.offline(rabbit, to: "xyz", tick: 7).isEmpty)
    }

    func testRabbitAndSparrowHaveDifferentPersonalitiesAndReplies() {
        let rabbit = CompanionCatalog.companion(id: "046")
        let sparrow = CompanionCatalog.companion(id: "051")
        XCTAssertNotEqual(rabbit.style, sparrow.style)
        XCTAssertTrue(rabbit.style.contains("không dùng dấu chấm than"))
        XCTAssertTrue(sparrow.style.contains("Chiếp"))
        XCTAssertNotEqual(CompanionReply.offline(rabbit, to: "mình mệt", tick: 0), CompanionReply.offline(sparrow, to: "mình mệt", tick: 0))
        // Thỏ không dùng dấu chấm than, Chim sẻ hay dùng.
        XCTAssertTrue((rabbit.soft + rabbit.tired + rabbit.joy + rabbit.thanks + rabbit.hello).allSatisfy { !$0.contains("!") })
        XCTAssertTrue(sparrow.tired.allSatisfy { $0.contains("!") })
        let prompt = HealingAI.chatPrompt(companion: sparrow, history: [], text: "xin chào")
        XCTAssertTrue(prompt.system.contains(sparrow.style))
        XCTAssertTrue(prompt.system.contains("không nhắc mình là AI"))
    }

    func testChatPromptAsksForCasualTextingWithVoiceExamples() {
        for id in ["Mascot", "046", "051"] {
            let companion = CompanionCatalog.companion(id: id)
            XCTAssertEqual(companion.examples.count, 3)
            let system = HealingAI.chatSystemPrompt(for: companion)
            XCTAssertTrue(system.contains("KHÔNG viết văn"))
            XCTAssertTrue(system.contains("ĐỘ DÀI THEO TÌNH HUỐNG"))
            XCTAssertTrue(system.contains("HỎI điều gì"))
            XCTAssertTrue(system.contains("Không bịa số liệu"))
            XCTAssertTrue(system.contains("Cấm ẩn dụ"))
            for example in companion.examples { XCTAssertTrue(system.contains(example.reply)) }
        }
    }

    func testBuiltInRepliesAreCasualNotLiterary() {
        let literary = ["rễ", "bão", "nắng gắt", "như thể", "tựa", "mùa", "gốc cây"]
        for id in ["Mascot", "046", "051"] {
            let c = CompanionCatalog.companion(id: id)
            for line in c.soft + c.tired + c.joy + c.thanks + c.hello + [c.opener] + c.examples.map(\.reply) {
                XCTAssertTrue(line.split(separator: " ").count <= 30, "Quá dài: \(line)")
                for word in literary { XCTAssertFalse(line.lowercased().contains(word), "Văn vở: \(line)") }
            }
        }
    }

    func testChatPromptKeepsLastTwelveTurnsAndTrimsTheMessage() {
        let companion = CompanionCatalog.companion(id: "051")
        let history = (0..<20).map { ChatMessage(fromUser: $0 % 2 == 0, text: "tin-\($0)-", isAI: false, date: .now) }
        let prompt = HealingAI.chatPrompt(companion: companion, history: history, text: String(repeating: "a", count: 1200))
        XCTAssertTrue(prompt.system.contains("Chim sẻ"))
        XCTAssertTrue(prompt.system.contains("Không chẩn đoán bệnh"))
        XCTAssertFalse(prompt.user.contains("tin-7-"))
        XCTAssertTrue(prompt.user.contains("tin-8-"))
        XCTAssertTrue(prompt.user.contains("tin-19-"))
        XCTAssertLessThanOrEqual(prompt.user.count, 800 + 600)
    }

    func testChatPromptCarriesDeviceTimeAndDoesNotForceRest() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
        let afternoon = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 14, minute: 35)))
        let late = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 23, minute: 50)))
        let companion = CompanionCatalog.companion(id: "046")
        let a = HealingAI.chatPrompt(companion: companion, history: [], text: "thuốc này uống lúc nào", now: afternoon, calendar: cal)
        XCTAssertTrue(a.user.hasPrefix("Bối cảnh: bây giờ là 14:35"))
        XCTAssertTrue(a.user.contains("18/11/2026"))
        XCTAssertTrue(a.user.contains("buổi chiều"))
        XCTAssertTrue(a.user.contains("Bạn: thuốc này uống lúc nào"))
        XCTAssertTrue(HealingAI.chatPrompt(companion: companion, history: [], text: "hi", now: late, calendar: cal).user.contains("đêm khuya"))
        XCTAssertTrue(a.system.contains("đừng lúc nào cũng khuyên nghỉ ngơi"))
        XCTAssertTrue(a.system.contains("KHÔNG tự đoán họ đang đi ca"))
    }

    func testChatStoreRoundTripsAndKeepsOnlyTheLatestMessages() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "hope.tests.chat"))
        suite.removePersistentDomain(forName: "hope.tests.chat")
        defer { suite.removePersistentDomain(forName: "hope.tests.chat") }
        let messages = (0..<80).map { ChatMessage(fromUser: true, text: "m\($0)", isAI: false, date: .now) }
        CompanionChatStore.save(messages, for: "046", defaults: suite)
        let loaded = CompanionChatStore.load("046", defaults: suite)
        XCTAssertEqual(loaded.count, CompanionChatStore.maximumMessages)
        XCTAssertEqual(loaded.last?.text, "m79")
        XCTAssertTrue(CompanionChatStore.load("051", defaults: suite).isEmpty)
        CompanionChatStore.clear("046", defaults: suite)
        XCTAssertTrue(CompanionChatStore.load("046", defaults: suite).isEmpty)
    }

    func testQuotesAreRealAttributedAndRotate() {
        XCTAssertGreaterThanOrEqual(HopeQuotes.all.count, 20)
        XCTAssertTrue(HopeQuotes.all.allSatisfy { !$0.text.isEmpty && !$0.author.isEmpty && $0.text.count <= 200 })
        XCTAssertEqual(Set(HopeQuotes.all.map(\.text)).count, HopeQuotes.all.count)
        // Những câu hay bị gán nhầm không được có mặt.
        XCTAssertFalse(HopeQuotes.all.contains { $0.author == "Winston Churchill" })
        let first = HopeQuotes.quote(variant: 0, date: date(2026, 11, 15), calendar: cal)
        let second = HopeQuotes.quote(variant: 1, date: date(2026, 11, 15), calendar: cal)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(HopeQuotes.quote(variant: 500, date: date(2026, 11, 15), calendar: cal).text.isEmpty)
    }

    // MARK: Thú đi trên mặt đất

    func testGroundAnimalsStayInsideTheGroundBandAndFaceTheirDirection() throws {
        for motion in [GardenMotion.hopping, .perched, .breathing, .crawling] {
            let style = try XCTUnwrap(GardenRoamer.style(for: motion))
            var roamer = GardenRoamer(x: 0.8, depth: 0.3, style: style, seed: 42, restUntil: 0)
            var sawLeft = false, sawRight = false, maxArc = 0.0
            var time = 0.0
            while time < 240 {
                maxArc = max(maxArc, roamer.update(now: time))
                XCTAssertGreaterThanOrEqual(roamer.x, GardenRoamer.xRange.lowerBound - 1e-9)
                XCTAssertLessThanOrEqual(roamer.x, GardenRoamer.xRange.upperBound + 1e-9)
                XCTAssertGreaterThanOrEqual(roamer.depth, 0)
                XCTAssertLessThanOrEqual(roamer.depth, 1)
                if roamer.facing < 0 { sawLeft = true } else { sawRight = true }
                time += 1.0 / 60.0
            }
            XCTAssertTrue(sawLeft && sawRight, "\(motion) phải quay đầu theo hướng đi")
            XCTAssertLessThanOrEqual(maxArc, 1.0)
        }
    }

    func testFlyingSpeciesDoNotRoam() {
        XCTAssertNil(GardenRoamer.style(for: .flying))
    }

    func testRoamerIsDeterministicAndCanBeToldToRest() throws {
        let style = try XCTUnwrap(GardenRoamer.style(for: .hopping))
        var a = GardenRoamer(x: 0.5, depth: 0.2, style: style, seed: 7, restUntil: 0)
        var b = GardenRoamer(x: 0.5, depth: 0.2, style: style, seed: 7, restUntil: 0)
        for step in 0..<600 {
            let now = Double(step) / 60
            XCTAssertEqual(a.update(now: now), b.update(now: now))
            XCTAssertEqual(a.x, b.x)
        }
        a.rest(until: 100)
        let frozen = a.x
        for step in 600..<1200 { a.update(now: Double(step) / 60) }
        XCTAssertEqual(a.x, frozen, accuracy: 1e-9)
    }

    // MARK: Hiệu ứng thở

    func testBreathPhasesFollowFourOneFive() {
        XCTAssertEqual(BreathingOrb.state(at: 0.5).phase, .inhale)
        XCTAssertEqual(BreathingOrb.state(at: 0.5).secondsLeft, 4)
        XCTAssertEqual(BreathingOrb.state(at: 3.9).secondsLeft, 1)
        XCTAssertEqual(BreathingOrb.state(at: 4.5).phase, .hold)
        XCTAssertEqual(BreathingOrb.state(at: 5.2).phase, .exhale)
        XCTAssertEqual(BreathingOrb.state(at: 5.2).secondsLeft, 5)
        XCTAssertEqual(BreathingOrb.state(at: 10.1).phase, .inhale)
        XCTAssertEqual(BreathingOrb.state(at: 7.5).cycle, 0.75, accuracy: 1e-9)
        XCTAssertEqual(BreathingOrb.breath(at: 4.5), 1, accuracy: 1e-9)
        XCTAssertEqual(BreathingOrb.breath(at: 0), 0, accuracy: 1e-9)
    }

    func testBreathRipplesStartAtEachPhaseAndLastThreeSeconds() {
        let early = BreathingOrb.ripples(at: 1)
        XCTAssertEqual(early.count, 1)
        XCTAssertEqual(early.first?.kind, -1)                      // hít vào: sóng thu vào
        let exhale = BreathingOrb.ripples(at: 6)
        XCTAssertTrue(exhale.contains { $0.kind == 1 })            // thở ra: sóng lan ra
        XCTAssertTrue(exhale.contains { $0.kind == 0 })            // giữ: một nhịp
        XCTAssertTrue(exhale.allSatisfy { $0.progress >= 0 && $0.progress < 1 })
        XCTAssertEqual(BreathingOrb.ripples(at: 3.9).count, 0)           // sóng hít vào đã tan sau 3 giây
        XCTAssertGreaterThanOrEqual(BreathingOrb.ripples(at: 2.9).count, 1)
    }

    func testBreathTintBlendsBetweenPhaseColours() {
        let inhale = BreathingOrb.rgb(.inhale), hold = BreathingOrb.rgb(.hold)
        let start = BreathingOrb.tint(at: 4.0)       // vừa sang pha giữ: vẫn gần màu hít vào
        let later = BreathingOrb.tint(at: 4.9)       // đã chuyển hẳn sang màu giữ
        XCTAssertEqual(start.r, inhale.r, accuracy: 0.02)
        XCTAssertEqual(later.r, hold.r, accuracy: 0.001)
        XCTAssertEqual(later.b, hold.b, accuracy: 0.001)
    }

    // MARK: Chờ và nhập chữ khi chat

    func testThinkingLabelGetsMorePatientTheLongerTheWait() {
        XCTAssertEqual(CompanionChatView.thinkingLabel(name: "Thỏ", waited: 1), "Thỏ đang suy nghĩ…")
        XCTAssertEqual(CompanionChatView.thinkingLabel(name: "Thỏ", waited: 10), "Thỏ vẫn đang nghĩ…")
        XCTAssertTrue(CompanionChatView.thinkingLabel(name: "Thỏ", waited: 30).contains("bạn đợi nhé"))
    }

    func testTypingPausesAtPunctuationAndSpeedsUpForLongReplies() {
        let normal = CompanionChatView.typingDelay(for: "a", total: 60)
        XCTAssertGreaterThan(CompanionChatView.typingDelay(for: ".", total: 60), normal + 0.2)
        XCTAssertGreaterThan(CompanionChatView.typingDelay(for: ",", total: 60), normal + 0.1)
        XCTAssertLessThan(CompanionChatView.typingDelay(for: "a", total: 600), normal)
        // Một câu dài 300 chữ vẫn xong trong khoảng sáu giây, không chờ quá lâu.
        XCTAssertLessThan(300 * CompanionChatView.typingDelay(for: "a", total: 300), 7)
    }

    func testNightStartsAtSevenInTheEvening() {
        XCTAssertTrue(HopePagerView.isNightNow(date(2026, 11, 15, 20), calendar: cal))
        XCTAssertTrue(HopePagerView.isNightNow(date(2026, 11, 15, 3), calendar: cal))
        XCTAssertFalse(HopePagerView.isNightNow(date(2026, 11, 15, 12), calendar: cal))
    }
}

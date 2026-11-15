import XCTest
import SwiftData
@testable import Hope

@MainActor
final class HealingTests: XCTestCase {
    private func context() throws -> ModelContext {
        let schema = SharedModelContainer.schema
        return ModelContext(try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]))
    }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
        return calendar
    }

    // MARK: Khu vườn

    func testStageGrowsWithRestDaysAndNeverNeedsAGoal() {
        XCTAssertEqual(GardenStage.stage(forDays: 0), .sprout)
        XCTAssertEqual(GardenStage.stage(forDays: 2), .sprout)
        XCTAssertEqual(GardenStage.stage(forDays: 3), .leafy)
        XCTAssertEqual(GardenStage.stage(forDays: 7), .leafy)
        XCTAssertEqual(GardenStage.stage(forDays: 8), .lush)
        XCTAssertEqual(GardenStage.stage(forDays: 15), .lush)
        XCTAssertEqual(GardenStage.stage(forDays: 16), .bloom)
        XCTAssertEqual(GardenStage.stage(forDays: 500), .bloom)
    }

    func testRestDaysCountsDistinctDaysNotVisits() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let visits = [HealingVisit(kind: .rest, createdAt: day1),
                      HealingVisit(kind: .journal, createdAt: day1.addingTimeInterval(60)),
                      HealingVisit(kind: .listen, createdAt: day1.addingTimeInterval(86_400 * 2))]
        XCTAssertEqual(GardenGrowth.restDays(visits, calendar: calendar), 2)
        XCTAssertEqual(GardenGrowth.restDays([], calendar: calendar), 0)
    }

    func testEveryStageHasAnImageName() {
        XCTAssertEqual(Set(GardenStage.allCases.map(\.imageName)).count, GardenStage.allCases.count)
    }

    // MARK: Nội dung

    func testEveryMoodHasTwoSuggestionsAndAnOfflineNote() {
        for mood in HopeMood.allCases {
            XCTAssertEqual(HealingContent.suggestions(for: mood).count, 2, mood.title)
            XCTAssertFalse(HealingContent.offlineNote(for: mood).isEmpty)
        }
    }

    func testOfflineNoteIsStableWithinADayAndVariantChangesIt() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = HealingContent.offlineNote(for: .tired, on: date, variant: 0, calendar: calendar)
        XCTAssertEqual(first, HealingContent.offlineNote(for: .tired, on: date, variant: 0, calendar: calendar))
        XCTAssertNotEqual(first, HealingContent.offlineNote(for: .tired, on: date, variant: 1, calendar: calendar))
    }

    func testBreathCurveIsContinuousAndCalm() {
        XCTAssertEqual(BreathingOrb.breath(at: 0), 0, accuracy: 0.001)
        XCTAssertEqual(BreathingOrb.breath(at: 2), 0.5, accuracy: 0.001)
        XCTAssertEqual(BreathingOrb.breath(at: 4), 1, accuracy: 0.001)
        XCTAssertEqual(BreathingOrb.breath(at: 4.5), 1, accuracy: 0.001)
        XCTAssertLessThan(BreathingOrb.breath(at: 7), BreathingOrb.breath(at: 6))
        XCTAssertEqual(BreathingOrb.breath(at: 10), 0, accuracy: 0.001)
        XCTAssertEqual(BreathingOrb.breath(at: 12), 0.5, accuracy: 0.001)
    }

    // MARK: Chọn model Gemini

    func testModelParserAcceptsOnlyTextFlashFamily() {
        XCTAssertEqual(GeminiModelPicker.parse("models/gemini-3.5-flash-lite")?.isLite, true)
        XCTAssertEqual(GeminiModelPicker.parse("gemini-3.8-flash")?.version, 3.8)
        XCTAssertNotNil(GeminiModelPicker.parse("gemini-2.0-flash-001"))
        XCTAssertEqual(GeminiModelPicker.parse("gemini-3.5-flash-lite-preview-09-2025")?.isPreview, true)
        XCTAssertNil(GeminiModelPicker.parse("gemini-3.8-flash-image"))
        XCTAssertNil(GeminiModelPicker.parse("gemini-3.5-flash-live-preview"))
        XCTAssertNil(GeminiModelPicker.parse("gemini-3.5-flash-tts"))
        XCTAssertNil(GeminiModelPicker.parse("gemini-pro"))
        XCTAssertNil(GeminiModelPicker.parse("text-embedding-004"))
    }

    func testModelChainPrefersNewestLiteThenNewestFlashThenAliases() {
        let discovered = ["models/gemini-2.5-flash", "models/gemini-3.5-flash-lite", "models/gemini-3.8-flash",
                          "models/gemini-3.6-flash", "models/gemini-3.5-flash-lite-preview-09-2025", "models/gemini-3.8-flash-image"]
        let chain = GeminiModelPicker.chain(from: discovered)
        XCTAssertEqual(Array(chain.prefix(4)), ["gemini-3.5-flash-lite", "gemini-3.5-flash-lite-preview-09-2025", "gemini-3.8-flash", "gemini-3.6-flash"])
        XCTAssertTrue(chain.contains("gemini-flash-latest"))
        XCTAssertEqual(chain.count, Set(chain).count)
        XCTAssertFalse(chain.contains("gemini-3.8-flash-image"))
    }

    func testModelChainStillWorksWhenDiscoveryFailsAndRespectsPreferred() {
        let fallback = GeminiModelPicker.chain(from: [])
        XCTAssertEqual(fallback.first, "gemini-flash-lite-latest")
        XCTAssertTrue(fallback.contains("gemini-3.5-flash-lite"))
        let preferred = GeminiModelPicker.chain(from: ["models/gemini-3.5-flash-lite"], preferred: "gemini-3.6-flash")
        XCTAssertEqual(preferred.first, "gemini-3.6-flash")
        XCTAssertEqual(preferred.count, Set(preferred).count)
    }

    func testModelListKeepsOnlyGenerateContentModels() throws {
        let json = #"{"models":[{"name":"models/gemini-3.5-flash-lite","supportedGenerationMethods":["generateContent","countTokens"]},{"name":"models/text-embedding-004","supportedGenerationMethods":["embedContent"]}],"nextPageToken":"abc"}"#
        let page = try XCTUnwrap(GeminiClient.parseModelList(Data(json.utf8)))
        XCTAssertEqual(page.names, ["models/gemini-3.5-flash-lite"])
        XCTAssertEqual(page.next, "abc")
        XCTAssertNil(GeminiClient.parseModelList(Data("{}".utf8))?.next)
    }

    func testResponseTextSkipsThinkingParts() {
        let json = #"{"candidates":[{"content":{"parts":[{"text":"đang suy nghĩ","thought":true},{"text":"  Xin chào bạn.  "}]}}]}"#
        XCTAssertEqual(GeminiClient.extractText(Data(json.utf8)), "Xin chào bạn.")
        XCTAssertNil(GeminiClient.extractText(Data(#"{"candidates":[]}"#.utf8)))
    }

    func testRequestUsesOnlyMinimalParametersSoAnyGeminiGenerationAcceptsIt() throws {
        let body = GeminiClient.requestBody(system: "s", user: "u", maxOutputTokens: 300)
        let config = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual(Set(config.keys), ["maxOutputTokens"])
    }

    // MARK: Xử lý chữ AI

    func testParseLinesStripsBulletsAndNumbering() {
        let raw = "1. Thả lỏng hai vai xuống\n- Nhìn ra xa một điểm\n\n• Cảm nhận bàn chân chạm sàn\nok"
        XCTAssertEqual(HealingAI.parseLines(raw, maximum: 10),
                       ["Thả lỏng hai vai xuống", "Nhìn ra xa một điểm", "Cảm nhận bàn chân chạm sàn"])
        XCTAssertEqual(HealingAI.parseLines(raw, maximum: 2).count, 2)
    }

    func testCleanedRemovesDecorationAndRejectsEmpty() {
        XCTAssertEqual(HealingAI.cleaned("\"**Bạn đã làm tốt.**\""), "Bạn đã làm tốt.")
        XCTAssertNil(HealingAI.cleaned("  \n "))
    }

    // MARK: Ghi dữ liệu

    func testJournalRequiresTextAndRecordsAVisit() throws {
        let context = try context()
        XCTAssertThrowsError(try HealingStore.saveJournal(kind: .free, prompt: "p", text: "  \n", context: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JournalEntry>()), 0)
        let entry = try HealingStore.saveJournal(kind: .gratitude, prompt: "Một điều nhỏ…", text: "  Mình đã kịp ăn trưa.  ", context: context)
        XCTAssertEqual(entry.text, "Mình đã kịp ăn trưa.")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<HealingVisit>()), 1)
        XCTAssertThrowsError(try HealingStore.saveJournal(kind: .free, prompt: "p", text: String(repeating: "a", count: 10_001), context: context))
    }

    func testEditingAndDeletingJournalEntry() throws {
        let context = try context()
        let entry = try HealingStore.saveJournal(kind: .free, prompt: "p", text: "Bản đầu", context: context)
        try HealingStore.update(entry, text: "Bản sửa", context: context)
        XCTAssertEqual(entry.text, "Bản sửa")
        XCTAssertThrowsError(try HealingStore.update(entry, text: " ", context: context))
        XCTAssertEqual(entry.text, "Bản sửa")
        try HealingStore.delete(entry, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JournalEntry>()), 0)
    }

    func testMoodCheckInAlsoCountsAsAVisit() throws {
        let context = try context()
        try HealingStore.recordMood(.tense, context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MoodCheckIn>()).first?.mood, .tense)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HealingVisit>()).first?.kind, .checkIn)
    }

    func testCompletedTodayIgnoresYesterdayDeletedAndOpenTasks() {
        let now = Date()
        let today = TaskItem(title: "Hôm nay", isCompleted: true, createdAt: now)
        let yesterday = TaskItem(title: "Hôm qua", isCompleted: true, createdAt: now.addingTimeInterval(-86_400 * 2))
        let deleted = TaskItem(title: "Đã xóa", isCompleted: true, createdAt: now); deleted.deletedAt = now
        let open = TaskItem(title: "Chưa xong")
        let result = HealingStore.completedToday([yesterday, open, deleted, today], now: now)
        XCTAssertEqual(result.map(\.title), ["Hôm nay"])
    }

    func testSchemaNoLongerContainsAIImportDrafts() {
        let names = SharedModelContainer.schema.entities.map(\.name)
        XCTAssertFalse(names.contains("PendingTaskImport"))
        XCTAssertTrue(["MoodCheckIn", "JournalEntry", "HealingVisit"].allSatisfy(names.contains))
    }

    // MARK: Ngân sách thời gian Gemini

    func testRequestTimeoutNeverExceedsRemainingBudget() {
        let now = Date()
        XCTAssertEqual(GeminiClient.timeout(upTo: 12, until: now.addingTimeInterval(30), now: now), 12, accuracy: 0.001)
        XCTAssertEqual(GeminiClient.timeout(upTo: 12, until: now.addingTimeInterval(5), now: now), 5, accuracy: 0.001)
        XCTAssertEqual(GeminiClient.timeout(upTo: 12, until: now.addingTimeInterval(-3), now: now), 0)
        XCTAssertLessThanOrEqual(GeminiClient.totalBudget, 15)
    }

    func testStoreProblemFlagIsOffWhenDatabaseOpens() {
        XCTAssertFalse(SharedModelContainer.isRunningOnTemporaryStore)
    }
}

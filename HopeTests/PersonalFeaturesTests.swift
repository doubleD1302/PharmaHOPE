import XCTest
import SwiftData
@testable import Hope

@MainActor
final class PersonalFeaturesTests: XCTestCase {
    private func context() throws -> ModelContext {
        let schema = SharedModelContainer.schema
        return ModelContext(try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]))
    }
    private func shift(_ name: String = "Ca sáng", start: Date = .now, hours: Double = 8) -> ShiftConfig {
        ShiftConfig(name: name, startTime: start, endTime: start.addingTimeInterval(hours * 3600))
    }

    func testDeleteUndoPreservesIdentityAndHidesFromShift() throws {
        let context = try context()
        let task = TaskItem(title: "Kiểm quỹ", shiftId: "shift")
        context.insert(task); try context.save()
        let id = task.id
        try TaskCommands.delete(task, context: context)
        XCTAssertTrue(try ShiftTaskSync.tasks(in: context, shiftID: "shift").isEmpty)
        try TaskCommands.restore(task, context: context)
        XCTAssertEqual(try ShiftTaskSync.tasks(in: context, shiftID: "shift").map(\.id), [id])
    }
    func testEditingValidatesBeforeChangingData() throws {
        let context = try context()
        let task = TaskItem(title: "Tên cũ")
        context.insert(task); try context.save()
        XCTAssertThrowsError(try TaskCommands.update(task, title: " \n", notes: "", priority: .high,
            dueAt: nil, reminderEnabled: true, leadMinutes: 10, context: context))
        XCTAssertEqual(task.title, "Tên cũ")
        try TaskCommands.update(task, title: "Đối soát quỹ", notes: "Quầy số một", priority: .high,
            dueAt: .now.addingTimeInterval(3600), reminderEnabled: true, leadMinutes: 15, context: context)
        XCTAssertTrue(task.searchText.contains("doi soat quy"))
        XCTAssertNotNil(task.dueAt)
    }
    func testCompletionIsIdempotentAndReopenClearsCompletionDate() throws {
        let context = try context()
        let task = TaskItem(title: "Việc")
        context.insert(task)
        try TaskCommands.complete(task, completed: true, context: context)
        let first = task.completedAt
        try TaskCommands.complete(task, completed: true, context: context)
        XCTAssertEqual(task.completedAt, first)
        try TaskCommands.complete(task, completed: false, context: context)
        XCTAssertNil(task.completedAt)
    }
    func testChecklistInstancesHaveIndependentCompletionAndAreNotReapplied() throws {
        let context = try context()
        let template = RoutineTemplate(title: "Kiểm quỹ", type: .morning)
        let first = shift(); let second = shift()
        context.insert(template); context.insert(first); context.insert(second)
        XCTAssertEqual(try RoutineChecklistService.apply(to: first, context: context), 1)
        try context.save()
        let firstTask = try XCTUnwrap(ShiftTaskSync.tasks(in: context, shiftID: first.id).first)
        try TaskCommands.complete(firstTask, completed: true, context: context)
        XCTAssertEqual(try RoutineChecklistService.apply(to: second, context: context), 1)
        try context.save()
        let secondTask = try XCTUnwrap(ShiftTaskSync.tasks(in: context, shiftID: second.id).first)
        XCTAssertFalse(secondTask.isCompleted); XCTAssertNotEqual(firstTask.id, secondTask.id)
        try TaskCommands.delete(firstTask, context: context)
        XCTAssertEqual(try RoutineChecklistService.apply(to: first, context: context), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 2)
    }
    func testNightDeadlineResolvesToFollowingDate() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 22))!
        let shift = shift("Ca đêm", start: start)
        let due = TaskText.deadline("01:30", shift: shift, fallback: start, calendar: calendar)!
        XCTAssertEqual(calendar.component(.day, from: due), 15)
        XCTAssertEqual(calendar.component(.hour, from: due), 1)
        XCTAssertNil(TaskText.deadline("25:00", shift: shift, fallback: start, calendar: calendar))
    }
    func testSnoozeBeyondShiftEndIsRejected() throws {
        let context = try context()
        let now = Date()
        let shift = shift(start: now, hours: 0.1)
        let task = TaskItem(title: "Việc", shiftId: shift.id); task.dueAt = now.addingTimeInterval(60)
        context.insert(shift); context.insert(task)
        XCTAssertThrowsError(try TaskCommands.snooze(task, minutes: 10, shift: shift, context: context, now: now))
        XCTAssertNil(task.snoozedUntil)
    }
    func testReminderPlanStopsAtShiftEndAndDoesNotRepeatForever() {
        let now = Date()
        let task = TaskItem(title: "Có hạn", shiftId: "shift"); task.dueAt = now.addingTimeInterval(3600)
        let end = now.addingTimeInterval(3700)
        let plan = TaskNotificationPlan.make(tasks: [task], shiftEnd: end, now: now)
        XCTAssertTrue(plan.allSatisfy { $0.date <= end && $0.date > now })
        XCTAssertFalse(plan.contains { $0.id.hasSuffix("overdue") })
        XCTAssertTrue(TaskNotificationPlan.make(tasks: [task], shiftEnd: now.addingTimeInterval(-1), now: now).isEmpty)
    }
    func testSnoozeSuppressesOriginalDeadlineAndCompletedDeletedDisabledHaveNoTaskEvents() {
        let now = Date()
        let task = TaskItem(title: "Hoãn"); task.dueAt = now.addingTimeInterval(60); task.snoozedUntil = now.addingTimeInterval(600)
        let complete = TaskItem(title: "Xong", isCompleted: true); complete.dueAt = task.dueAt
        let deleted = TaskItem(title: "Xóa"); deleted.deletedAt = now; deleted.dueAt = task.dueAt
        let disabled = TaskItem(title: "Tắt"); disabled.reminderEnabled = false; disabled.dueAt = task.dueAt
        let plan = TaskNotificationPlan.make(tasks: [task, complete, deleted, disabled], shiftEnd: nil, now: now)
        XCTAssertEqual(plan.count, 1); XCTAssertTrue(plan[0].id.hasSuffix("snooze"))
    }
    func testNotificationQueueKeepsNearestSixtyEvents() {
        let now = Date()
        let tasks = (1...100).map { index -> TaskItem in
            let task = TaskItem(title: "Việc \(index)"); task.dueAt = now.addingTimeInterval(Double(index) * 3600)
            return task
        }
        let plan = TaskNotificationPlan.make(tasks: tasks, shiftEnd: nil, now: now)
        XCTAssertEqual(plan.count, 60)
        XCTAssertEqual(plan.map(\.date), plan.map(\.date).sorted())
    }
    func testSnoozingEarlyDoesNotEraseFutureDeadline() {
        let now = Date()
        let task = TaskItem(title: "Hạn vẫn còn ở phía trước")
        task.dueAt = now.addingTimeInterval(3600); task.snoozedUntil = now.addingTimeInterval(600)
        let plan = TaskNotificationPlan.make(tasks: [task], shiftEnd: nil, now: now)
        XCTAssertTrue(plan.contains { $0.id.hasSuffix("snooze") })
        XCTAssertTrue(plan.contains { $0.id.hasSuffix("due") && $0.date == task.dueAt })
    }
    func testHistorySearchHandlesVietnameseAndDeletedFilter() throws {
        let context = try context()
        let now = Date()
        let task = TaskItem(title: "Đối soát quỹ", createdAt: now, shiftId: "ca"); task.dueAt = now.addingTimeInterval(-60)
        context.insert(task); try context.save()
        func query(_ state: Int) -> FetchDescriptor<TaskItem> {
            TaskSearchQuery.descriptor(search: "doi soat quy", state: state, priority: "", shiftID: "ca",
                start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(3600), now: now)
        }
        XCTAssertEqual(try context.fetch(query(3)).map(\.id), [task.id])
        try TaskCommands.delete(task, context: context)
        XCTAssertTrue(try context.fetch(query(0)).isEmpty)
        XCTAssertEqual(try context.fetch(query(4)).map(\.id), [task.id])
    }
    func testBackupRoundTripAndRepeatedMergeDoNotDuplicateData() throws {
        let source = try context()
        let shift = shift(); source.insert(shift)
        let task = TaskItem(title: "Việc có dấu: quỹ", shiftId: shift.id); task.sourceText = "Tin nhắn gốc"
        source.insert(task); source.insert(RoutineTemplate(title: "Mẫu", type: .night)); try source.save()
        let archive = try HopeBackup.decode(HopeBackupService.snapshot(context: source).encoded())
        let target = try context()
        _ = try HopeBackupService.merge(archive, context: target, updateLibraryPreference: false)
        _ = try HopeBackupService.merge(archive, context: target, updateLibraryPreference: false)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<TaskItem>()), 1)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<RoutineTemplate>()), 1)
        XCTAssertFalse(try XCTUnwrap(target.fetch(FetchDescriptor<ShiftConfig>()).first).isActive)
        XCTAssertEqual(try XCTUnwrap(target.fetch(FetchDescriptor<TaskItem>()).first).sourceText, "Tin nhắn gốc")
    }
    func testInvalidBackupCannotPartiallyInsertRows() throws {
        let source = try context(); source.insert(TaskItem(title: "Có thật")); try source.save()
        var archive = try HopeBackupService.snapshot(context: source)
        archive.tasks[0].priorityRaw = "invalid"
        let target = try context()
        XCTAssertThrowsError(try HopeBackupService.merge(archive, context: target, updateLibraryPreference: false))
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<TaskItem>()), 0)
        archive.schemaVersion = 999
        XCTAssertThrowsError(try archive.validate())
    }
    func testBackupKeepsNewerLocalDeletion() throws {
        let source = try context(); let old = TaskItem(id: "same", title: "Bản cũ"); old.updatedAt = Date(timeIntervalSince1970: 1_000)
        source.insert(old); try source.save()
        let archive = try HopeBackupService.snapshot(context: source)
        let target = try context(); let local = TaskItem(id: "same", title: "Bản mới")
        local.deletedAt = .now; local.updatedAt = .now; target.insert(local); try target.save()
        _ = try HopeBackupService.merge(archive, context: target, updateLibraryPreference: false)
        XCTAssertEqual(local.title, "Bản mới"); XCTAssertNotNil(local.deletedAt)
    }
    func testOldBackupWithRemovedImportsKeyStillDecodes() throws {
        let json = #"{"app":"Hope","schemaVersion":1,"exportedAt":0,"tasks":[],"shifts":[],"routines":[],"imports":[{"id":"x"}]}"#
        let archive = try HopeBackup.decode(Data(json.utf8))
        XCTAssertTrue(archive.tasks.isEmpty)
    }
    func testBackupCarriesGardenDataAndMergesWithoutDuplicates() throws {
        let source = try context()
        let mood = MoodCheckIn(mood: .tired); let visit = HealingVisit(kind: .rest, minutes: 5)
        let entry = JournalEntry(kind: .free, prompt: "Hôm nay", text: "Một ngày dài")
        source.insert(mood); source.insert(visit); source.insert(entry); try source.save()
        let archive = try HopeBackup.decode(HopeBackupService.snapshot(context: source).encoded())
        XCTAssertEqual(archive.moods?.count, 1); XCTAssertEqual(archive.journal?.first?.text, "Một ngày dài"); XCTAssertEqual(archive.visits?.first?.minutes, 5)
        let target = try context()
        _ = try HopeBackupService.merge(archive, context: target, updateLibraryPreference: false)
        _ = try HopeBackupService.merge(archive, context: target, updateLibraryPreference: false)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<MoodCheckIn>()), 1)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<JournalEntry>()), 1)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<HealingVisit>()), 1)
        XCTAssertEqual(try XCTUnwrap(target.fetch(FetchDescriptor<JournalEntry>()).first).id, entry.id)
    }
    func testBackupCanLeaveGardenDataOut() throws {
        let source = try context(); source.insert(JournalEntry(kind: .free, prompt: "", text: "Riêng tư")); try source.save()
        let archive = try HopeBackupService.snapshot(context: source, includeGarden: false)
        XCTAssertNil(archive.journal)
        XCTAssertFalse(String(decoding: try archive.encoded(), as: UTF8.self).contains("Riêng tư"))
    }
    func testInvalidGardenRecordsAreRejectedBeforeAnyInsert() throws {
        let source = try context(); source.insert(MoodCheckIn(mood: .okay)); try source.save()
        var archive = try HopeBackupService.snapshot(context: source)
        archive.moods?[0].moodRaw = "khong-co"
        let target = try context()
        XCTAssertThrowsError(try HopeBackupService.merge(archive, context: target, updateLibraryPreference: false))
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<MoodCheckIn>()), 0)
    }
    func testOldBackupWithoutGardenKeysStillDecodes() throws {
        let json = #"{"app":"Hope","schemaVersion":1,"exportedAt":0,"tasks":[],"shifts":[],"routines":[]}"#
        let archive = try HopeBackup.decode(Data(json.utf8))
        XCTAssertNil(archive.journal)
    }
}

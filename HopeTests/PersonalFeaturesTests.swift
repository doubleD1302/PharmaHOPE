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
    func testAIStageDoesNotCreateTasksAndCommitKeepsSelectedEdits() throws {
        let context = try context()
        let pending = try TaskImportService.stage(tasks: [TaskItem(title: "AI một"), TaskItem(title: "AI hai")],
            source: "Nguồn giữ nguyên dấu: quỹ, dược sĩ", label: "Test", shiftID: nil, context: context)
        let batch = pending.id
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 0)
        var drafts = try pending.drafts()
        drafts[0].title = "Tên đã duyệt"; drafts[1].isSelected = false
        XCTAssertEqual(try TaskImportService.commit(pending, drafts: drafts, shiftID: nil, context: context), 1)
        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<TaskItem>()).first)
        XCTAssertEqual(saved.title, "Tên đã duyệt")
        XCTAssertEqual(saved.importBatchID, batch)
        XCTAssertEqual(saved.sourceText, "Nguồn giữ nguyên dấu: quỹ, dược sĩ")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PendingTaskImport>()), 0)
    }
    func testInvalidAISelectionLeavesDraftAndCreatesNoPartialTasks() throws {
        let context = try context()
        let pending = try TaskImportService.stage(tasks: [TaskItem(title: "Hợp lệ"), TaskItem(title: "Sửa sau")],
            source: "nguồn", label: "Test", shiftID: nil, context: context)
        var drafts = try pending.drafts(); drafts[1].dueTime = "25:80"
        XCTAssertThrowsError(try TaskImportService.commit(pending, drafts: drafts, shiftID: nil, context: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PendingTaskImport>()), 1)
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
    func testRestoringOldDraftDoesNotReplayAlreadyApprovedBatch() throws {
        let context = try context()
        let pending = try TaskImportService.stage(tasks: [TaskItem(title: "Một việc")], source: "Nguồn", label: "Test", shiftID: nil, context: context)
        let oldArchive = try HopeBackupService.snapshot(context: context)
        _ = try TaskImportService.commit(pending, drafts: pending.drafts(), shiftID: nil, context: context)
        _ = try HopeBackupService.merge(oldArchive, context: context, updateLibraryPreference: false)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PendingTaskImport>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 1)
    }
}

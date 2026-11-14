import XCTest
import SwiftData
@testable import Hope

@MainActor
final class ShiftTaskSyncTests: XCTestCase {
    private func context() throws -> ModelContext {
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    func testTasksDoNotIncludePreviousShift() throws {
        let context = try context()
        context.insert(TaskItem(title: "Ca cũ", isCompleted: true, shiftId: "old"))
        context.insert(TaskItem(title: "Ca mới", shiftId: "new"))
        try context.save()
        XCTAssertEqual(try ShiftTaskSync.tasks(in: context, shiftID: "new").map(\.title), ["Ca mới"])
    }

    func testInboxExcludesAssignedTasks() throws {
        let context = try context()
        context.insert(TaskItem(title: "Chưa chọn ca"))
        context.insert(TaskItem(title: "Đã gắn ca", shiftId: "assigned"))
        try context.save()
        XCTAssertEqual(try ShiftTaskSync.tasks(in: context, shiftID: nil).map(\.title), ["Chưa chọn ca"])
    }

    func testUrgentTasksSortBeforeRoutineAndEarlierDeadlineFirst() throws {
        let context = try context()
        context.insert(TaskItem(title: "Thường", priority: .medium, shiftId: "shift"))
        context.insert(TaskItem(title: "Gấp muộn", priority: .high, dueTime: "15:00", shiftId: "shift"))
        context.insert(TaskItem(title: "Gấp sớm", priority: .high, dueTime: "10:00", shiftId: "shift"))
        try context.save()
        XCTAssertEqual(try ShiftTaskSync.tasks(in: context, shiftID: "shift").map(\.title), ["Gấp sớm", "Gấp muộn", "Thường"])
    }

    func testActivityCountsAndPendingTasksAgree() {
        let shift = ShiftConfig(name: "Ca thử", startTime: .now, endTime: .now.addingTimeInterval(3600))
        let tasks = [TaskItem(title: "Xong", isCompleted: true), TaskItem(title: "Cần làm")]
        let state = ShiftTaskSync.state(shift: shift, tasks: tasks)
        XCTAssertEqual(state.totalCount, 2)
        XCTAssertEqual(state.completedCount, 1)
        XCTAssertEqual(state.pendingTasks.map(\.title), ["Cần làm"])
    }

    func testSampleScheduleDoesNotSilentlyStartShift() {
        XCTAssertTrue(ShiftConfig.defaultShifts().allSatisfy { !$0.isActive })
    }
}

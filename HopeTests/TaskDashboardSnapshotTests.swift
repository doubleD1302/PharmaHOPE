import XCTest
@testable import Hope

final class TaskDashboardSnapshotTests: XCTestCase {
    func testOnlyPendingUrgentTasksContributeToUrgentCount() {
        let snapshot = TaskDashboardSnapshot(tasks: [
            TaskItem(title: "Gấp đã xong", priority: .high, isCompleted: true),
            TaskItem(title: "Gấp đang chờ", priority: .high),
            TaskItem(title: "Việc thường", priority: .medium)
        ])
        XCTAssertEqual(snapshot.urgentCount, 1)
        XCTAssertEqual(snapshot.pending.count, 2)
        XCTAssertEqual(snapshot.completed.count, 1)
        XCTAssertEqual(snapshot.progress, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testEmptySnapshotHasFiniteZeroProgress() {
        let snapshot = TaskDashboardSnapshot(tasks: [])
        XCTAssertEqual(snapshot.total, 0)
        XCTAssertEqual(snapshot.progress, 0)
        XCTAssertTrue(snapshot.progress.isFinite)
    }

    func testDeadlineAndPriorityOrderIsDeterministic() {
        let sameTime = Date(timeIntervalSince1970: 1_000)
        let snapshot = TaskDashboardSnapshot(tasks: [
            TaskItem(id: "z", title: "Cuối ca", priority: .low, dueTime: "08:00"),
            TaskItem(id: "b", title: "Gấp B", priority: .high, dueTime: "09:00", createdAt: sameTime),
            TaskItem(id: "a", title: "Gấp A", priority: .high, dueTime: "09:00", createdAt: sameTime),
            TaskItem(id: "c", title: "Gấp chưa hẹn", priority: .high)
        ])
        XCTAssertEqual(snapshot.pending.map(\.id), ["a", "b", "c", "z"])
    }
}

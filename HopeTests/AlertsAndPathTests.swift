import XCTest
@testable import Hope

@MainActor
final class AlertsAndPathTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
        c.firstWeekday = 2
        return c
    }
    /// Mặc định là ngày 16/11/2026; `date(14, 30)` là 14:30 ngày đó, `date(14, day: 30)` là 14:00 ngày 30.
    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 16) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    private func task(_ title: String, due: Date?, lead: Int = 10, snoozed: Date? = nil, done: Bool = false, shiftID: String? = nil, reminder: Bool = true) -> TaskItem {
        let item = TaskItem(title: title, shiftId: shiftID)
        item.dueAt = due; item.reminderLeadMinutes = lead; item.snoozedUntil = snoozed; item.isCompleted = done; item.reminderEnabled = reminder
        return item
    }
    private func kinds(_ alerts: [HopeAlert]) -> [HopeAlertKind] { alerts.map(\.kind) }
    private func make(_ tasks: [TaskItem] = [], shifts: [ShiftConfig] = [], visits: [HealingVisit] = [], now: Date) -> [HopeAlert] {
        HopeAlertEngine.make(tasks: tasks, shifts: shifts, visits: visits, now: now, calendar: cal)
    }

    // MARK: Việc đến hạn, quá hạn

    func testTaskAlertsFollowDueTime() {
        let now = date(10)
        XCTAssertEqual(kinds(make([task("a", due: date(10, 5))], now: now)).filter { $0 != .rest }, [.taskSoon])
        XCTAssertEqual(kinds(make([task("a", due: date(9, 59))], now: now)).filter { $0 != .rest }, [.taskDue])
        let late = make([task("a", due: date(9, 30))], now: now).first { $0.kind == .taskLate }
        XCTAssertNotNil(late)
        XCTAssertTrue(late?.body.contains("quá hạn 30 phút") == true)
        XCTAssertTrue(make([task("a", due: date(11))], now: now).isEmpty)
        XCTAssertTrue(make([task("a", due: date(10, 5), lead: 0)], now: now).isEmpty)
    }

    func testOverdueStaysUntilTheTaskIsDone() {
        let overdue = task("a", due: date(8))
        XCTAssertTrue(kinds(make([overdue], now: date(13))).contains(.taskLate))
        overdue.isCompleted = true
        XCTAssertTrue(make([overdue], now: date(13)).isEmpty)
    }

    func testCompletedDeletedOrSilentTasksProduceNothing() {
        let deleted = task("a", due: date(9)); deleted.deletedAt = date(8)
        XCTAssertTrue(make([task("a", due: date(9), done: true), deleted, task("b", due: date(9), reminder: false)], now: date(10)).isEmpty)
    }

    func testSnoozedTaskStaysQuietThenRemindsOnce() {
        let snoozed = task("a", due: date(9, 50), snoozed: date(10, 10))
        XCTAssertTrue(make([snoozed], now: date(10)).isEmpty)
        let after = make([snoozed], now: date(10, 11))
        XCTAssertEqual(kinds(after), [.taskSnooze])
        XCTAssertEqual(after.first?.taskID, snoozed.id)
    }

    // MARK: Ca trực

    func testShiftAlertsBeforeStartAndWhenNotStarted() {
        let shift = ShiftConfig(name: "Ca Chiều", startTime: date(14), endTime: date(22), isActive: false, targetDate: date(0))
        XCTAssertEqual(kinds(make(shifts: [shift], now: date(13, 40))).filter { $0 == .shiftSoon }.count, 1)
        XCTAssertEqual(kinds(make(shifts: [shift], now: date(14, 20))).filter { $0 == .shiftStart }.count, 1)
        XCTAssertFalse(kinds(make(shifts: [shift], now: date(12))).contains(.shiftSoon))
        XCTAssertFalse(kinds(make(shifts: [shift], now: date(16))).contains(.shiftStart))   // quá 90 phút kể từ giờ bắt đầu
    }

    func testOffDaysNeverAlert() {
        let off = ShiftConfig(name: "Nghỉ", startTime: date(14), endTime: date(14), isActive: false, targetDate: date(0))
        XCTAssertFalse(kinds(make(shifts: [off], now: date(13, 50))).contains(.shiftSoon))
    }

    func testActiveShiftWarnsBeforeAndAfterTheEndWhileWorkRemains() {
        let shift = ShiftConfig(name: "Ca Chiều", startTime: date(14), endTime: date(22), isActive: true, targetDate: date(0))
        let pending = task("a", due: nil, shiftID: shift.id)
        XCTAssertTrue(make([pending], shifts: [shift], now: date(21, 40)).contains { $0.id.hasSuffix(":end30") })
        XCTAssertTrue(make([pending], shifts: [shift], now: date(21, 50)).contains { $0.id.hasSuffix(":end15") })
        XCTAssertTrue(make([pending], shifts: [shift], now: date(22, 30)).contains { $0.id.hasSuffix(":ended") })
        XCTAssertFalse(make(shifts: [shift], now: date(21, 50)).contains { $0.kind == .shiftEnd })   // hết việc thì không báo
    }

    // MARK: Nhắc nhẹ trong ngày

    func testRestAndCloseDayNudgesAppearOncePerDayAndStopAfterTheVisit() {
        XCTAssertTrue(kinds(make(now: date(15))).contains(.rest))
        XCTAssertFalse(kinds(make(now: date(10))).contains(.rest))
        XCTAssertFalse(kinds(make(visits: [HealingVisit(kind: .rest, minutes: 1, createdAt: date(14, 30))], now: date(15))).contains(.rest))
        XCTAssertTrue(kinds(make(visits: [HealingVisit(kind: .rest, minutes: 1, createdAt: date(14, 30))], now: date(21, 30))).contains(.closeDay))
        XCTAssertFalse(kinds(make(visits: [HealingVisit(kind: .closeDay, createdAt: date(21, 10))], now: date(21, 30))).contains(.closeDay))
    }

    func testMostUrgentAlertsComeFirstAndKeysAreStable() {
        let alerts = make([task("soon", due: date(10, 5)), task("late", due: date(8))], now: date(10))
        XCTAssertEqual(alerts.first?.kind, .taskLate)
        let again = make([task("soon", due: date(10, 5)), task("late", due: date(8))], now: date(10))
        XCTAssertEqual(alerts.map(\.kind), again.map(\.kind))
        XCTAssertEqual(Set(alerts.map(\.id)).count, alerts.count)
    }

    func testReadAndSeenStateRemembersKeysAndExpiresOldOnes() throws {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "hope.tests.alerts"))
        suite.removePersistentDomain(forName: "hope.tests.alerts")
        defer { suite.removePersistentDomain(forName: "hope.tests.alerts") }
        HopeAlertState.markRead(["a", "b"], suite)
        XCTAssertEqual(HopeAlertState.readKeys(suite), ["a", "b"])
        let start = date(9)
        XCTAssertEqual(Set(HopeAlertState.newlySeen(["x", "y"], now: start, suite)), ["x", "y"])
        XCTAssertTrue(HopeAlertState.newlySeen(["x", "y"], now: start.addingTimeInterval(60), suite).isEmpty)
        XCTAssertEqual(HopeAlertState.newlySeen(["x"], now: start.addingTimeInterval(15 * 86_400), suite), ["x"])   // quá 14 ngày: báo lại
    }

    // MARK: Thông báo hệ thống cho ca

    func testShiftStartNotificationsAreThirtyMinutesBeforeAndAtStart() {
        let now = date(12)
        let shift = ShiftConfig(name: "Ca Chiều", startTime: date(14), endTime: date(22), isActive: false, targetDate: date(0))
        let plan = ShiftNotificationPlan.make(shifts: [shift], now: now)
        XCTAssertEqual(plan.map(\.id), ["hope.shiftstart.\(shift.id).30", "hope.shiftstart.\(shift.id).0"])
        XCTAssertEqual(plan[0].date, date(13, 30))
        XCTAssertEqual(plan[1].date, date(14))
        // Chỉ còn 20 phút: bỏ thông báo 30 phút trước.
        XCTAssertEqual(ShiftNotificationPlan.make(shifts: [shift], now: date(13, 40)).map(\.id), ["hope.shiftstart.\(shift.id).0"])
        // Ca đang chạy, ngày nghỉ, hoặc quá 7 ngày: không có thông báo.
        let active = ShiftConfig(name: "Ca Sáng", startTime: date(14), endTime: date(22), isActive: true, targetDate: date(0))
        let off = ShiftConfig(name: "Nghỉ", startTime: date(14), endTime: date(14), isActive: false, targetDate: date(0))
        let far = ShiftConfig(name: "Ca Xa", startTime: date(14, day: 30), endTime: date(22, day: 30), isActive: false, targetDate: date(0, day: 30))
        XCTAssertTrue(ShiftNotificationPlan.make(shifts: [active, off, far], now: now).isEmpty)
    }

    // MARK: Chuông có giai điệu

    func testEveryBellMelodyIsFiveToNineSecondsLongAndAscendingInTime() {
        for kind in BellMelody.Kind.allCases {
            let notes = BellMelody.notes(for: kind)
            XCTAssertGreaterThanOrEqual(notes.count, 7)
            XCTAssertEqual(notes.map(\.time), notes.map(\.time).sorted())
            let seconds = BellMelody.duration(of: kind)
            XCTAssertTrue((5...9).contains(seconds), "\(kind) dài \(seconds) giây")
            XCTAssertTrue(notes.allSatisfy { $0.frequency > 300 && $0.frequency < 2000 && $0.ring > 1 })
        }
        // Mỗi loại một giai điệu khác nhau.
        XCTAssertNotEqual(BellMelody.notes(for: .info).map(\.frequency), BellMelody.notes(for: .due).map(\.frequency))
        XCTAssertNotEqual(BellMelody.notes(for: .due).map(\.frequency), BellMelody.notes(for: .urgent).map(\.frequency))
    }

    func testBellWavIsAValidMonoPCMFileThatDoesNotClip() throws {
        let data = BellMelody.wavData(for: .info, sampleRate: 22_050)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")
        let samples = data.count - 44
        XCTAssertEqual(samples % 2, 0)
        XCTAssertGreaterThan(Double(samples / 2) / 22_050, 5)
        XCTAssertLessThan(Double(samples / 2) / 22_050, 9)
        var peak = 0
        data.dropFirst(44).withUnsafeBytes { raw in
            for value in raw.bindMemory(to: Int16.self) { peak = max(peak, Int(value.magnitude)) }
        }
        XCTAssertGreaterThan(peak, 10_000)
        XCTAssertLessThanOrEqual(peak, 32_000)
    }

    func testNotificationSoundKindFollowsTheNotificationID() {
        XCTAssertEqual(BellMelody.kind(forNotificationID: "hope.task.abc.before"), .info)
        XCTAssertEqual(BellMelody.kind(forNotificationID: "hope.task.abc.due"), .due)
        XCTAssertEqual(BellMelody.kind(forNotificationID: "hope.task.abc.snooze"), .due)
        XCTAssertEqual(BellMelody.kind(forNotificationID: "hope.task.abc.overdue"), .urgent)
        XCTAssertEqual(BellMelody.kind(forNotificationID: "hope.clockout.15"), .urgent)
        XCTAssertEqual(BellMelody.kind(forNotificationID: "hope.shiftstart.s1.30"), .info)
        XCTAssertEqual(BellMelody.kind(forNotificationID: "hope.shiftstart.s1.0"), .due)
    }

    // MARK: Lối mòn của thú

    func testPathContextProjectsOnlyOntoTheStonePathInsideTheStage() throws {
        // Điện thoại dọc: nút điều khiển nằm phía trên, sân khấu chiếm phần dưới trang nơi lối mòn nằm.
        let ctx = try XCTUnwrap(GardenPathContext(screen: CGSize(width: 390, height: 844), frame: CGRect(x: 20, y: 330, width: 350, height: 390)))
        XCTAssertGreaterThan(ctx.yNear, ctx.yFar)
        var visible = 0, hidden = 0
        for xi in 0...10 {
            for di in 0...10 {
                let x = 0.1 + 0.8 * Double(xi) / 10, depth = Double(di) / 10
                guard let hit = ctx.project(x: x, depth: depth) else { hidden += 1; continue }
                visible += 1
                let imageX = (Double(hit.screen.x) - Double(ctx.origin.x)) / ctx.scale
                let path = GardenPath.at(y: hit.imageY)
                XCTAssertLessThanOrEqual(abs(imageX - path.cx), path.hw + 1e-6, "ra ngoài lối mòn")
                XCTAssertGreaterThanOrEqual(Double(hit.screen.y), Double(ctx.frame.minY) - 20)
                XCTAssertLessThanOrEqual(Double(hit.screen.y), Double(ctx.frame.maxY))
                XCTAssertGreaterThanOrEqual(Double(hit.screen.x), Double(ctx.frame.minX) + 30)
                XCTAssertLessThanOrEqual(Double(hit.screen.x), Double(ctx.frame.maxX) - 30)
            }
        }
        XCTAssertGreaterThan(visible, 20)
        XCTAssertGreaterThan(hidden, 0, "màn hình hẹp: đoạn lối mòn nằm ngoài màn hình phải bị loại")
    }

    func testPathContextConvertsScreenPointsToSceneCoordinates() throws {
        let ctx = try XCTUnwrap(GardenPathContext(screen: CGSize(width: 1200, height: 800), frame: CGRect(x: 20, y: 100, width: 600, height: 500)))
        let p = ctx.scenePoint(fromScreen: CGPoint(x: 120, y: 600))
        XCTAssertEqual(p.x, 100, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0, accuracy: 1e-9)
        XCTAssertNil(GardenPathContext(screen: .zero, frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
    }

    func testRoamerOnTheRealPathStaysOnStonesAndMovesBothWays() throws {
        let ctx = try XCTUnwrap(GardenPathContext(screen: CGSize(width: 1000, height: 700), frame: CGRect(x: 0, y: 120, width: 1000, height: 420)))
        let style = try XCTUnwrap(GardenRoamer.style(for: .hopping))
        var roamer = GardenRoamer(x: 0.5, depth: 0.45, style: style, seed: 11, restUntil: 0)
        let project: GardenRoamer.Projection = { x, depth in ctx.project(x: x, depth: depth)?.screen }
        var minY = Double.infinity, maxY = -Double.infinity, sawLeft = false, sawRight = false
        var time = 0.0
        while time < 300 {
            roamer.update(now: time, project: project)
            let hit = try XCTUnwrap(ctx.project(x: roamer.x, depth: roamer.depth, enforceBounds: false))
            let imageX = (Double(hit.screen.x) - Double(ctx.origin.x)) / ctx.scale
            let path = GardenPath.at(y: hit.imageY)
            XCTAssertLessThanOrEqual(abs(imageX - path.cx), path.hw + 1e-6)
            minY = min(minY, Double(hit.screen.y)); maxY = max(maxY, Double(hit.screen.y))
            if roamer.facing < 0 { sawLeft = true } else { sawRight = true }
            time += 1.0 / 30
        }
        XCTAssertGreaterThan(maxY - minY, 40, "phải đi lên xuống dọc lối mòn, không chỉ đi ngang")
        XCTAssertTrue(sawLeft && sawRight)
    }

    func testPerspectiveShrinksTheFarEndOfThePath() {
        XCTAssertEqual(GardenPath.perspective(imageY: 400), 0.62, accuracy: 1e-9)
        XCTAssertEqual(GardenPath.perspective(imageY: 660), 1, accuracy: 1e-9)
        XCTAssertLessThan(GardenPath.perspective(imageY: 450), GardenPath.perspective(imageY: 600))
    }
}

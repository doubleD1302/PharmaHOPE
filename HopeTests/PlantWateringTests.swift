import XCTest
@testable import Hope

final class PlantWateringTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testFirstWateringOfTheDayIsReady() {
        XCTAssertEqual(PlantWatering.status(log: [], now: date(15, 9), calendar: calendar), .ready(todayCount: 0))
    }

    func testSecondWateringNeedsFourHours() {
        let log = [date(15, 8)]
        XCTAssertEqual(PlantWatering.status(log: log, now: date(15, 11), calendar: calendar),
                       .tooSoon(todayCount: 1, wait: 3600))
        XCTAssertEqual(PlantWatering.status(log: log, now: date(15, 12), calendar: calendar), .ready(todayCount: 1))
    }

    func testThreeWateringsFillTheDayAndNextDayStartsFresh() {
        let log = [date(15, 6), date(15, 10), date(15, 14)]
        XCTAssertEqual(PlantWatering.status(log: log, now: date(15, 20), calendar: calendar), .dayFull)
        XCTAssertEqual(PlantWatering.status(log: log, now: date(16, 20), calendar: calendar), .ready(todayCount: 0))
    }

    func testGapAlsoAppliesAcrossMidnight() {
        let log = [date(15, 22)]
        XCTAssertEqual(PlantWatering.status(log: log, now: date(16, 0, 30), calendar: calendar),
                       .tooSoon(todayCount: 0, wait: 1.5 * 3600))
    }

    func testClockMovedBackwardsNeverWaitsLongerThanTheGap() {
        guard case .tooSoon(_, let wait) = PlantWatering.status(log: [date(15, 12)], now: date(15, 8), calendar: calendar) else {
            return XCTFail("expected tooSoon")
        }
        XCTAssertLessThanOrEqual(wait, PlantWatering.gap)
    }

    func testLogRoundTripAndPruning() {
        let now = date(15, 12)
        let old = date(10, 12)
        let log = PlantWatering.recording(now, in: [old, date(14, 12)])
        XCTAssertEqual(log, [date(14, 12), now])
        XCTAssertEqual(PlantWatering.parse(PlantWatering.encode(log)), log)
        XCTAssertEqual(PlantWatering.parse("abc,,"), [])
    }

    func testWaitTextAndMessages() {
        XCTAssertEqual(PlantWatering.waitText(45 * 60), "45 phút")
        XCTAssertEqual(PlantWatering.waitText(3 * 3600 + 12 * 60), "3 giờ 12 phút")
        XCTAssertEqual(PlantWatering.waitText(2 * 3600), "2 giờ")
        XCTAssertNil(PlantWatering.blockedMessage(.ready(todayCount: 0)))
        XCTAssertNotNil(PlantWatering.blockedMessage(.dayFull))
        XCTAssertTrue(PlantWatering.blockedMessage(.tooSoon(todayCount: 1, wait: 3600))?.contains("1 giờ") ?? false)
    }
}

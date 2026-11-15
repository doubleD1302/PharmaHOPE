import XCTest
@testable import Hope

final class GardenMotionTests: XCTestCase {
    func testTracksAreContinuousAtLoopBoundary() {
        let track = GardenRig.Track(property: "rotation", amplitude: 0.5, frequency: 1,
                                    phase: 0, idleFactor: 0.1, kind: "sine")
        XCTAssertEqual(track.value(at: 1 - 0.000001, idle: false),
                       track.value(at: 1 + 0.000001, idle: false), accuracy: 0.00001)
    }

    @MainActor
    func testEveryRigExistsAndReducedMotionResetsJoints() throws {
        for creature in GardenCreature.animals + [.mascot] {
            let rig = try XCTUnwrap(GardenRig.load(id: creature.id), creature.id)
            XCTAssertGreaterThan(rig.nodes.filter { !$0.tracks.isEmpty }.count, 2)
            XCTAssertFalse(rig.nodes.filter { $0.id == "body" }.flatMap(\.tracks)
                .contains { $0.property == "scaleX" || $0.property == "scaleY" })
            let node = GardenRigNode(rig: rig)
            node.sample(time: 2.37, idle: false, reduced: false, greeting: 0.4)
            node.sample(time: 17, idle: false, reduced: true, greeting: 0.5)
            for joint in rig.nodes {
                let child = try XCTUnwrap(node.childNode(withName: "//" + joint.id))
                XCTAssertEqual(child.position.x, joint.x, accuracy: 0.0001)
                XCTAssertEqual(child.position.y, joint.y, accuracy: 0.0001)
                XCTAssertEqual(child.zRotation, joint.rotation, accuracy: 0.0001)
                XCTAssertEqual(child.xScale, 1)
                XCTAssertEqual(child.yScale, 1)
            }
        }
    }

    func testClockDoesNotJumpAfterBackgroundOrLongFrame() {
        var clock = GardenAnimationClock()
        clock.advance(to: 1)
        clock.advance(to: 1.02)
        XCTAssertEqual(clock.elapsed, 0.02, accuracy: 0.0001)
        clock.resetFrame()
        clock.advance(to: 900)
        XCTAssertEqual(clock.elapsed, 0.02, accuracy: 0.0001)
        clock.advance(to: 1000)
        XCTAssertEqual(clock.elapsed, 0.07, accuracy: 0.0001)
    }

    func testClockMatchesAcrossNormalFrameRates() {
        func elapsed(fps: Int) -> Double {
            var clock = GardenAnimationClock()
            for frame in 0...(fps * 10) { clock.advance(to: Double(frame) / Double(fps)) }
            return clock.elapsed
        }
        XCTAssertEqual(elapsed(fps: 30), elapsed(fps: 60), accuracy: 0.00001)
        XCTAssertEqual(elapsed(fps: 60), elapsed(fps: 120), accuracy: 0.00001)
    }
}

import XCTest
import SpriteKit
@testable import Hope

/// Rig phiên bản 2: bộ phận vẽ tay cắt từ một atlas, gắn vào khớp.
final class PaintedRigTests: XCTestCase {
    @MainActor
    private func rabbit() throws -> GardenRig { try XCTUnwrap(GardenRig.load(id: "046")) }

    @MainActor
    func testRabbitUsesAValidPaintedAtlas() throws {
        let rig = try rabbit()
        XCTAssertEqual(rig.version, 2)
        let atlasName = try XCTUnwrap(rig.atlas)
        let size = try XCTUnwrap(rig.atlasSize)
        let image = try XCTUnwrap(UIImage(named: atlasName))
        XCTAssertEqual(Double(image.size.width * image.scale), size[0], accuracy: 0.5)
        XCTAssertEqual(Double(image.size.height * image.scale), size[1], accuracy: 0.5)
        let sprites = rig.nodes.compactMap(\.sprite)
        XCTAssertGreaterThanOrEqual(sprites.count, 12)
        for sprite in sprites {
            XCTAssertTrue(sprite.isValid)
            XCTAssertGreaterThanOrEqual(sprite.rect[0], 0)
            XCTAssertGreaterThanOrEqual(sprite.rect[1], 0)
            XCTAssertLessThanOrEqual(sprite.rect[0] + sprite.rect[2], size[0])
            XCTAssertLessThanOrEqual(sprite.rect[1] + sprite.rect[3], size[1])
            XCTAssertTrue((0...1).contains(sprite.anchor[0]) && (0...1).contains(sprite.anchor[1]))
            XCTAssertGreaterThan(sprite.size[0], 0)
            XCTAssertGreaterThan(sprite.size[1], 0)
        }
    }

    @MainActor
    func testRabbitHierarchyIsConsistent() throws {
        let rig = try rabbit()
        let ids = Set(rig.nodes.map(\.id))
        XCTAssertEqual(ids.count, rig.nodes.count)
        XCTAssertEqual(rig.nodes.filter { $0.parent == nil }.map(\.id), ["body"])
        for joint in rig.nodes {
            if let parent = joint.parent { XCTAssertTrue(ids.contains(parent), joint.id) }
        }
    }

    @MainActor
    func testRabbitIsSpritesOnlyAndSmallEnoughForSixtyFramesPerSecond() throws {
        let rig = try rabbit()
        let node = GardenRigNode(rig: rig)
        var sprites = 0, shapes = 0
        var stack: [SKNode] = [node]
        while let current = stack.popLast() {
            if current is SKSpriteNode { sprites += 1 }
            if current is SKShapeNode { shapes += 1 }
            stack.append(contentsOf: current.children)
        }
        XCTAssertEqual(shapes, 0, "SKShapeNode chậm: ảnh thật không được dùng hình vector")
        XCTAssertEqual(sprites, rig.nodes.compactMap(\.sprite).count)
        XCTAssertLessThanOrEqual(rig.nodes.count, 24)
    }

    /// Mọi loài đã chuyển sang ảnh vẽ tay phải qua cùng một bộ kiểm tra.
    @MainActor
    func testEveryPaintedCreatureIsValidSpritesOnlyAndBlinksSafely() throws {
        for id in ["046", "051"] {
            let rig = try XCTUnwrap(GardenRig.load(id: id), id)
            XCTAssertEqual(rig.version, 2, id)
            let size = try XCTUnwrap(rig.atlasSize, id)
            let image = try XCTUnwrap(UIImage(named: try XCTUnwrap(rig.atlas)), id)
            XCTAssertEqual(Double(image.size.width * image.scale), size[0], accuracy: 0.5, id)
            XCTAssertEqual(Double(image.size.height * image.scale), size[1], accuracy: 0.5, id)
            let ids = Set(rig.nodes.map(\.id))
            XCTAssertEqual(ids.count, rig.nodes.count, id)
            XCTAssertEqual(rig.nodes.filter { $0.parent == nil }.map(\.id), ["body"], id)
            for joint in rig.nodes {
                if let parent = joint.parent { XCTAssertTrue(ids.contains(parent), "\(id) \(joint.id)") }
                if let sprite = joint.sprite {
                    XCTAssertTrue(sprite.isValid, "\(id) \(joint.id)")
                    XCTAssertLessThanOrEqual(sprite.rect[0] + sprite.rect[2], size[0], "\(id) \(joint.id)")
                    XCTAssertLessThanOrEqual(sprite.rect[1] + sprite.rect[3], size[1], "\(id) \(joint.id)")
                }
            }
            let node = GardenRigNode(rig: rig)
            var shapes = 0
            var stack: [SKNode] = [node]
            while let current = stack.popLast() {
                if current is SKShapeNode { shapes += 1 }
                stack.append(contentsOf: current.children)
            }
            XCTAssertEqual(shapes, 0, id)
            // Mí mắt chỉ hiện khi nháy: lấy tần số từ chính rig.
            let lid = try XCTUnwrap(rig.nodes.first { $0.id == "eyelid" }, id)
            let blink = try XCTUnwrap(lid.tracks.first { $0.property == "alpha" }, id)
            let lidNode = try XCTUnwrap(node.childNode(withName: "//eyelid"), id)
            node.sample(time: 0, idle: false, reduced: false, greeting: 0)
            XCTAssertEqual(lidNode.alpha, 0, accuracy: 0.01, id)
            node.sample(time: 0.9 / blink.frequency, idle: false, reduced: false, greeting: 0)
            XCTAssertGreaterThan(lidNode.alpha, 0.95, id)
            // Mí mắt chỉ là mảnh nhỏ quanh mắt, không phải cả đầu.
            let head = try XCTUnwrap(rig.nodes.first { $0.id == "head" }?.sprite, id)
            let lidSprite = try XCTUnwrap(lid.sprite, id)
            XCTAssertLessThan(lidSprite.size[0], head.size[0] * 0.75, "\(id): mí mắt không được to gần bằng đầu")
        }
    }

    func testPulseTrackPeaksAtNinetyPercentOfThePeriodAndRespectsWidth() {
        let blink = GardenRig.Track(property: "alpha", amplitude: 1, frequency: 1, phase: 0, idleFactor: 1, kind: "blink")
        XCTAssertEqual(blink.value(at: 0.9, idle: false), 1, accuracy: 0.0001)
        XCTAssertEqual(blink.value(at: 0.5, idle: false), 0, accuracy: 0.0001)
        let wide = GardenRig.Track(property: "y", amplitude: 6, frequency: 1, phase: 0, idleFactor: 0, kind: "blink", width: 0.1)
        XCTAssertEqual(wide.value(at: 0.9, idle: false), 6, accuracy: 0.0001)
        XCTAssertGreaterThan(wide.value(at: 0.95, idle: false), blink.value(at: 0.95, idle: false) * 6)
        XCTAssertEqual(wide.value(at: 0.9, idle: true), 0, accuracy: 0.0001, "nghỉ ngơi thì không nhảy")
    }

    @MainActor
    func testEyelidOnlyShowsWhileBlinking() throws {
        let rig = try rabbit()
        let node = GardenRigNode(rig: rig)
        let lid = try XCTUnwrap(node.childNode(withName: "//eyelid"))
        node.sample(time: 0, idle: false, reduced: false, greeting: 0)
        XCTAssertEqual(lid.alpha, 0, accuracy: 0.01)
        node.sample(time: 0.9 / 0.22, idle: false, reduced: false, greeting: 0)
        XCTAssertGreaterThan(lid.alpha, 0.95)
        node.sample(time: 0.9 / 0.22, idle: false, reduced: true, greeting: 0)
        XCTAssertEqual(lid.alpha, 0, "Giảm chuyển động: giữ mắt mở")
    }

    @MainActor
    func testRabbitHopsOnlyWhenNotResting() throws {
        let rig = try rabbit()
        let node = GardenRigNode(rig: rig)
        let body = try XCTUnwrap(node.childNode(withName: "//body"))
        let base = try XCTUnwrap(rig.nodes.first { $0.id == "body" }).y
        node.sample(time: 4.5, idle: false, reduced: false, greeting: 0)   // đỉnh cú nhảy: chu kỳ 5 giây, đỉnh ở 90%
        XCTAssertGreaterThan(body.position.y - base, 4)
        node.sample(time: 4.5, idle: true, reduced: false, greeting: 0)
        XCTAssertLessThan(body.position.y - base, 1.5)
    }
}

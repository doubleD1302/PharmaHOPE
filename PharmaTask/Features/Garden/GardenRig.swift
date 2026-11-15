import SpriteKit

struct GardenRig: Decodable {
    struct Point: Decodable { let x: Double; let y: Double }
    struct Bounds: Decodable { let width: Double; let height: Double }
    struct Shape: Decodable {
        let kind: String
        let width: Double
        let height: Double
        let points: [Point]
        let fill: String
        let stroke: String
        let lineWidth: Double
    }
    struct Track: Decodable {
        let property: String
        let amplitude: Double
        let frequency: Double
        let phase: Double
        let idleFactor: Double
        let kind: String
        /// Độ rộng xung của "blink" (tỉ lệ chu kỳ). Mặc định 0.025: nháy mắt; lớn hơn dùng cho cú nhảy.
        var width: Double? = nil

        func value(at time: Double, idle: Bool) -> Double {
            let phase = time * frequency + self.phase / (2 * .pi)
            let value: Double
            switch kind {
            case "blink":
                let fraction = phase - floor(phase)
                value = amplitude * exp(-pow((fraction - 0.9) / max(0.005, width ?? 0.025), 2))
            case "fold", "hop": value = amplitude * (0.5 - 0.5 * cos(phase * 2 * .pi))
            default: value = amplitude * sin(phase * 2 * .pi)
            }
            return value * (idle ? idleFactor : 1)
        }
    }
    /// Bộ phận vẽ tay cắt từ atlas (rig phiên bản 2). `rect` là pixel trong atlas, gốc ở góc trên trái;
    /// `anchor` là điểm xoay theo tỉ lệ, gốc ở góc dưới trái; `size` là kích thước hiển thị tính bằng điểm.
    struct Sprite: Decodable {
        let rect: [Double]
        let anchor: [Double]
        let size: [Double]
        var isValid: Bool { rect.count == 4 && anchor.count == 2 && size.count == 2 && rect[2] > 0 && rect[3] > 0 }
    }
    struct Joint: Decodable {
        let id: String
        let parent: String?
        let x: Double
        let y: Double
        let z: Double
        let rotation: Double
        let shape: Shape?
        let tracks: [Track]
        /// Bộ phận ảnh gắn vào khớp (rig phiên bản 2). Không có thì dùng `shape` vector.
        var sprite: Sprite? = nil
        /// Độ trong suốt gốc (mặc định 1). Mí mắt bắt đầu ở 0 và chỉ hiện khi nháy.
        var alpha: Double? = nil
    }
    let version: Int
    let id: String
    let name: String
    let family: String
    let bounds: Bounds
    let nodes: [Joint]
    /// Tên ảnh atlas trong bundle và kích thước pixel của nó (chỉ rig phiên bản 2).
    var atlas: String? = nil
    var atlasSize: [Double]? = nil

    static func load(id: String) -> GardenRig? {
        guard let url = Bundle.main.url(forResource: "CreatureRig" + id, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rig = try? JSONDecoder().decode(Self.self, from: data),
              rig.version == 1 || rig.version == 2,
              Set(rig.nodes.map(\.id)).count == rig.nodes.count else { return nil }
        if rig.nodes.contains(where: { $0.sprite != nil }) {
            // Rig dùng ảnh phải có atlas thật và số liệu hợp lệ, nếu không báo "chưa tải được" thay vì vẽ thiếu.
            guard let atlas = rig.atlas, UIImage(named: atlas) != nil,
                  let size = rig.atlasSize, size.count == 2,
                  rig.nodes.allSatisfy({ $0.sprite?.isValid ?? true }) else { return nil }
        }
        return rig
    }
}

@MainActor
final class GardenRigNode: SKNode {
    private struct Binding {
        let joint: GardenRig.Joint
        let node: SKNode
    }
    let rig: GardenRig
    private var bindings: [Binding] = []

    init(rig: GardenRig) {
        self.rig = rig
        super.init()
        var nodes: [String: SKNode] = [:]
        // Mọi bộ phận cắt từ cùng một texture nên SpriteKit gộp thành rất ít lần vẽ.
        let atlasTexture = rig.atlas.map { SKTexture(imageNamed: $0) }
        for joint in rig.nodes {
            let node = SKNode()
            node.name = joint.id
            node.zPosition = joint.z
            if let shape = joint.shape { node.addChild(Self.draw(shape)) }
            if let sprite = joint.sprite, sprite.isValid, let atlas = atlasTexture, let size = rig.atlasSize, size.count == 2 {
                node.addChild(Self.makeSprite(sprite, atlas: atlas, atlasSize: size))
            }
            nodes[joint.id] = node
            bindings.append(Binding(joint: joint, node: node))
        }
        for joint in rig.nodes {
            guard let node = nodes[joint.id] else { continue }
            if let parent = joint.parent, let parentNode = nodes[parent] { parentNode.addChild(node) }
            else { addChild(node) }
        }
        sample(time: 0, idle: true, reduced: true, greeting: 0)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Paths are created once above. Per render tick, change only joint transforms.
    // There are no frame images, frame textures or animated whole-body scales.
    func sample(time: Double, idle: Bool, reduced: Bool, greeting: Double) {
        for binding in bindings {
            let joint = binding.joint
            var x = joint.x, y = joint.y, rotation = joint.rotation
            var scaleX = 1.0, scaleY = 1.0
            var alpha = joint.alpha ?? 1.0
            if !reduced {
                for track in joint.tracks {
                    let value = track.value(at: time, idle: idle)
                    switch track.property {
                    case "x": x += value
                    case "y": y += value
                    case "rotation": rotation += value
                    case "scaleX": scaleX += value
                    case "scaleY": scaleY += value
                    case "alpha": alpha += value
                    default: break
                    }
                }
                if joint.id == "head" { rotation += sin(.pi * greeting) * 0.15 }
            }
            binding.node.position = CGPoint(x: x, y: y)
            binding.node.zRotation = rotation
            binding.node.xScale = max(0.05, scaleX)
            binding.node.yScale = max(0.05, scaleY)
            binding.node.alpha = CGFloat(min(1, max(0, alpha)))
        }
    }

    private static func makeSprite(_ sprite: GardenRig.Sprite, atlas: SKTexture, atlasSize: [Double]) -> SKSpriteNode {
        let r = sprite.rect
        // SKTexture(rect:in:) dùng toạ độ chuẩn hoá có gốc ở góc dưới trái.
        let rect = CGRect(x: r[0] / atlasSize[0], y: 1 - (r[1] + r[3]) / atlasSize[1],
                          width: r[2] / atlasSize[0], height: r[3] / atlasSize[1])
        let texture = SKTexture(rect: rect, in: atlas)
        texture.filteringMode = .linear
        let node = SKSpriteNode(texture: texture, size: CGSize(width: sprite.size[0], height: sprite.size[1]))
        node.anchorPoint = CGPoint(x: sprite.anchor[0], y: sprite.anchor[1])
        return node
    }

    private static func draw(_ shape: GardenRig.Shape) -> SKShapeNode {
        let path = CGMutablePath()
        if shape.kind == "ellipse" {
            path.addEllipse(in: CGRect(x: -shape.width / 2, y: -shape.height / 2,
                                       width: shape.width, height: shape.height))
        } else if let first = shape.points.first {
            path.move(to: CGPoint(x: first.x, y: first.y))
            for point in shape.points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
            path.closeSubpath()
        }
        let node = SKShapeNode(path: path)
        node.fillColor = color(shape.fill)
        node.strokeColor = color(shape.stroke)
        node.lineWidth = shape.lineWidth
        node.isAntialiased = true
        return node
    }

    private static func color(_ hex: String) -> UIColor {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

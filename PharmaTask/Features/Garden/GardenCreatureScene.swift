import SpriteKit

@MainActor
final class GardenCreatureScene: SKScene {
    private struct Actor {
        let creature: GardenCreature
        let node: GardenRigNode
        var reactionStarted: Double?
        /// Chỉ con vật đi lại được (không phải Hope, không phải loài bay): luôn ở trên mặt đất.
        var roamer: GardenRoamer?
        var arc = 0.0
        /// Bóng đổ mềm dưới chân, nằm trên mặt đất (không nhảy theo con vật).
        let shadow = SKSpriteNode(texture: GardenCreatureScene.shadowTexture)
    }
    private var actors: [Actor] = []
    private var clock = GardenAnimationClock()
    private var reduced = false
    var resting = false
    var onGreeting: ((String) -> Void)?
    /// Lối mòn trên màn hình do giao diện cung cấp. Chưa có thì dùng bố cục cũ (không đi lên xuống).
    var pathContext: GardenPathContext? { didSet { applyPoses() } }

    /// Bóng đổ hình elip mờ dần ra ngoài, vẽ một lần.
    static let shadowTexture: SKTexture = {
        let size = CGSize(width: 64, height: 24)
        let image = UIGraphicsImageRenderer(size: size).image { renderer in
            let colors = [UIColor(red: 0.09, green: 0.13, blue: 0.05, alpha: 0.55).cgColor,
                          UIColor(red: 0.09, green: 0.13, blue: 0.05, alpha: 0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            let context = renderer.cgContext
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: 1, y: size.height / size.width)
            context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: size.width / 2, options: [])
        }
        return SKTexture(image: image)
    }()
    private(set) var unavailable = false

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
    }
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func install(_ creature: GardenCreature) {
        removeAllChildren()
        actors.removeAll()
        unavailable = false
        for definition in [GardenCreature.mascot, creature] {
            guard let rig = GardenRig.load(id: definition.id) else { unavailable = true; continue }
            let node = GardenRigNode(rig: rig)
            node.name = definition.id
            addChild(node)
            var actor = Actor(creature: definition, node: node)
            if definition.id != GardenCreature.mascot.id, let style = GardenRoamer.style(for: definition.motion) {
                let seed = definition.id.unicodeScalars.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1.value) }
                actor.roamer = GardenRoamer(x: 0.5, depth: 0.45, style: style, seed: seed)
            }
            actor.shadow.zPosition = -5
            addChild(actor.shadow)
            actors.append(actor)
        }
        layoutActors()
        clock.resetFrame()
    }
    func configure(reduced: Bool, paused: Bool) {
        self.reduced = reduced
        clock.resetFrame()
        isPaused = paused
        applyPoses()
    }
    override func didChangeSize(_ oldSize: CGSize) { layoutActors() }
    private func layoutActors() {
        for actor in actors {
            // A fixed layout scale only; no animated whole-image scaling.
            actor.node.setScale(min(size.width * 0.43, 210) / actor.node.rig.bounds.width)
        }
        applyPoses()
    }
    override func update(_ currentTime: TimeInterval) {
        clock.advance(to: currentTime)
        for index in actors.indices where actors[index].roamer != nil {
            if reduced || resting {
                // Giảm chuyển động hoặc đang nghỉ: đứng yên tại chỗ.
                actors[index].roamer?.rest(until: clock.elapsed + 1)
                actors[index].arc = 0
            } else {
                let context = pathContext
                let project: GardenRoamer.Projection? = context.map { ctx in { x, depth in ctx.project(x: x, depth: depth)?.screen } }
                actors[index].arc = actors[index].roamer?.update(now: clock.elapsed, project: project) ?? 0
            }
        }
        applyPoses()
    }
    private func applyPoses() {
        for (index, actor) in actors.enumerated() {
            let time = clock.elapsed + Double(index) * 1.7
            let response = actor.reactionStarted.map { max(0, min(1, (clock.elapsed - $0) / 0.8)) } ?? 0
            let mascotY = size.height * 0.16
            if let roamer = actor.roamer, let ctx = pathContext, let placed = ctx.project(x: roamer.x, depth: roamer.depth, enforceBounds: false) {
                // Đi trên lối mòn: xa thì nhỏ hơn và nằm sau Hope, bóng đổ nằm dưới chân.
                let foot = ctx.scenePoint(fromScreen: placed.screen)
                let perspective = GardenPath.perspective(imageY: placed.imageY)
                let width = roamer.style.bodyWidth * ctx.scale * perspective
                let base = width / actor.node.rig.bounds.width
                actor.node.xScale = base * roamer.facing
                actor.node.yScale = base
                actor.node.position = CGPoint(x: foot.x, y: foot.y + actor.arc * roamer.style.height * ctx.scale * perspective)
                actor.node.zPosition = foot.y > mascotY ? -1 : 1
                actor.shadow.position = CGPoint(x: foot.x, y: foot.y - 1)
                actor.shadow.size = CGSize(width: width * 0.62 * (1 - 0.25 * actor.arc), height: width * 0.62 * 0.24 * (1 - 0.25 * actor.arc))
                actor.shadow.alpha = 0.9 - 0.45 * actor.arc
            } else if let roamer = actor.roamer {
                // Chưa có thông tin lối mòn: bố cục cũ trên dải cỏ phía dưới.
                let base = min(size.width * 0.43, 210) / actor.node.rig.bounds.width
                let depthScale = 1 - 0.18 * roamer.depth
                actor.node.xScale = base * depthScale * roamer.facing
                actor.node.yScale = base * depthScale
                actor.node.position = CGPoint(x: size.width * (0.12 + 0.76 * roamer.x), y: size.height * (0.10 + 0.12 * roamer.depth))
                actor.node.zPosition = roamer.depth > 0.5 ? -1 : 1
                actor.shadow.position = actor.node.position
                actor.shadow.size = CGSize(width: base * depthScale * 70, height: base * depthScale * 17)
                actor.shadow.alpha = 0.8
            } else {
                actor.node.position = CGPoint(x: size.width * (index == 0 ? 0.28 : 0.72), y: mascotY)
                let width = actor.node.rig.bounds.width * actor.node.xScale
                actor.shadow.position = CGPoint(x: actor.node.position.x, y: mascotY - 1)
                actor.shadow.size = CGSize(width: abs(width) * 0.5, height: abs(width) * 0.5 * 0.24)
                actor.shadow.alpha = 0.8
            }
            actor.node.sample(time: time, idle: resting, reduced: reduced, greeting: response)
        }
    }
    func greet(id: String) {
        guard let index = actors.firstIndex(where: { $0.creature.id == id }) else { return }
        if actors[index].reactionStarted.map({ clock.elapsed - $0 >= 0.8 }) ?? true {
            actors[index].reactionStarted = clock.elapsed
        }
        actors[index].roamer?.rest(until: clock.elapsed + 4.5)
        onGreeting?(actors[index].creature.name)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        if let actor = actors.reversed().first(where: {
            $0.node.calculateAccumulatedFrame().insetBy(dx: -12, dy: -12).contains(point)
        }) { greet(id: actor.creature.id) }
    }
}

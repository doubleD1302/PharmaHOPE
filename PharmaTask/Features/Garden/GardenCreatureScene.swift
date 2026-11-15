import SpriteKit

@MainActor
final class GardenCreatureScene: SKScene {
    private struct Actor {
        let creature: GardenCreature
        let node: GardenRigNode
        var reactionStarted: Double?
    }
    private var actors: [Actor] = []
    private var clock = GardenAnimationClock()
    private var reduced = false
    var resting = false
    var onGreeting: ((String) -> Void)?
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
            actors.append(Actor(creature: definition, node: node))
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
        applyPoses()
    }
    private func applyPoses() {
        for (index, actor) in actors.enumerated() {
            let time = clock.elapsed + Double(index) * 1.7
            let response = actor.reactionStarted.map { max(0, min(1, (clock.elapsed - $0) / 0.8)) } ?? 0
            actor.node.position = CGPoint(x: size.width * (index == 0 ? 0.28 : 0.72), y: size.height * 0.16)
            actor.node.sample(time: time, idle: resting, reduced: reduced, greeting: response)
        }
    }
    func greet(id: String) {
        guard let index = actors.firstIndex(where: { $0.creature.id == id }) else { return }
        if actors[index].reactionStarted.map({ clock.elapsed - $0 >= 0.8 }) ?? true {
            actors[index].reactionStarted = clock.elapsed
        }
        onGreeting?(actors[index].creature.name)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        if let actor = actors.reversed().first(where: {
            $0.node.calculateAccumulatedFrame().insetBy(dx: -12, dy: -12).contains(point)
        }) { greet(id: actor.creature.id) }
    }
}

import Foundation

/// Bộ sinh số giả ngẫu nhiên có hạt giống, để chuyển động của thú lặp lại được khi kiểm thử.
struct GardenRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> Double {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
    mutating func value(in range: ClosedRange<Double>) -> Double { range.lowerBound + next() * (range.upperBound - range.lowerBound) }
}

/// Thú đi lại trên mặt đất: nhảy từng bước ngắn về phía một điểm đến, đứng nghỉ một lúc rồi chọn điểm khác.
/// `x` chạy ngang (0 đến 1), `depth` chỉ lên cao một dải hẹp trên mặt cỏ (0 gần, 1 xa), không bao giờ rời mặt đất.
struct GardenRoamer {
    struct Style: Equatable {
        var step: Double
        var hopDuration: Double
        var pause: ClosedRange<Double>
        var rest: ClosedRange<Double>
        var height: Double   // độ cao của mỗi bước nhảy, tính theo đơn vị ảnh nền
        var bodyWidth: Double // bề rộng thân khi ở gần nhất, tính theo đơn vị ảnh nền (1200 đơn vị ngang)
    }

    /// Đổi (x, depth) thành điểm trên màn hình; nil nghĩa là chỗ đó không đi được.
    typealias Projection = (_ x: Double, _ depth: Double) -> CGPoint?

    private struct Hop { let start: Double; let fromX: Double; let fromDepth: Double; let toX: Double; let toDepth: Double }
    private enum Mode { case idle(until: Double), walking }

    static let xRange: ClosedRange<Double> = 0.1...0.9
    private(set) var x: Double
    private(set) var depth: Double
    /// 1 nhìn sang phải, -1 nhìn sang trái.
    private(set) var facing: Double
    let style: Style
    private var mode: Mode
    private var target: (x: Double, depth: Double)
    private var hop: Hop?
    private var nextHop = 0.0
    private var random: GardenRandom

    init(x: Double, depth: Double, facing: Double = 1, style: Style, seed: UInt64, restUntil: Double = 1.5) {
        self.x = min(max(x, Self.xRange.lowerBound), Self.xRange.upperBound)
        self.depth = min(max(depth, 0), 1)
        self.facing = facing
        self.style = style
        self.mode = .idle(until: restUntil)
        self.target = (self.x, self.depth)
        self.random = GardenRandom(seed: seed)
    }

    /// Kiểu chuyển động theo loài. Loài bay giữ nguyên chỗ (trả về nil).
    static func style(for motion: GardenMotion) -> Style? {
        switch motion {
        case .hopping: return Style(step: 0.05, hopDuration: 0.55, pause: 0.45...1.1, rest: 2.5...6, height: 11, bodyWidth: 100)
        case .perched: return Style(step: 0.034, hopDuration: 0.3, pause: 0.1...0.35, rest: 1.2...4, height: 6, bodyWidth: 68)
        case .breathing: return Style(step: 0.02, hopDuration: 0.8, pause: 0.6...1.4, rest: 3...8, height: 2.5, bodyWidth: 90)
        case .crawling: return Style(step: 0.012, hopDuration: 1.0, pause: 0.2...0.6, rest: 3...8, height: 1.2, bodyWidth: 70)
        case .flying: return nil
        }
    }

    /// Dừng đứng yên đến thời điểm `time` (ví dụ khi bạn chạm vào để chào).
    mutating func rest(until time: Double) {
        hop = nil
        mode = .idle(until: time)
    }

    /// Cập nhật theo thời gian; trả về độ nâng của bước nhảy hiện tại, từ 0 đến 1.
    @discardableResult
    mutating func update(now: Double, project: Projection? = nil) -> Double {
        // Không có phép chiếu (ví dụ khi kiểm thử): mọi vị trí đều đi được và hướng nhìn theo trục x.
        let projection: Projection = project ?? { x, depth in CGPoint(x: x, y: depth) }
        // Vị trí hiện tại không còn đi được (đổi cỡ màn hình, xoay máy): đặt lại vào một chỗ đi được.
        if hop == nil, projection(x, depth) == nil {
            for _ in 0..<60 {
                let nx = Self.xRange.lowerBound + random.next() * (Self.xRange.upperBound - Self.xRange.lowerBound)
                let nd = random.next()
                if projection(nx, nd) != nil {
                    x = nx; depth = nd; target = (nx, nd)
                    mode = .idle(until: now + 0.3)
                    return 0
                }
            }
        }
        switch mode {
        case .idle(let until):
            guard now >= until else { return 0 }
            // Chọn điểm đến đi được và đủ xa; không có thì nghỉ thêm một lúc rồi thử lại.
            for _ in 0..<30 {
                let destination = Self.xRange.lowerBound + random.next() * (Self.xRange.upperBound - Self.xRange.lowerBound)
                let destinationDepth = random.next()
                guard abs(destination - x) >= 0.12 || abs(destinationDepth - depth) >= 0.12,
                      projection(destination, destinationDepth) != nil else { continue }
                target = (destination, destinationDepth)
                mode = .walking
                hop = nil
                nextHop = now
                return 0
            }
            mode = .idle(until: now + 1)
            return 0
        case .walking:
            if hop == nil {
                guard now >= nextHop else { return 0 }
                let dx = target.x - x
                let dd = target.depth - depth
                if abs(dx) <= style.step * 0.6 && abs(dd) < 0.08 {
                    mode = .idle(until: now + random.value(in: style.rest))
                    return 0
                }
                let sx = (dx < 0 ? -1.0 : 1.0) * min(abs(dx), style.step)
                let sd = (dd < 0 ? -1.0 : 1.0) * min(abs(dd), style.step * 1.6)
                let nextX = x + sx, nextDepth = min(1, max(0, depth + sd))
                guard let from = projection(x, depth), let to = projection(nextX, nextDepth) else {
                    mode = .idle(until: now + 1)   // bước kế tiếp rời khỏi lối mòn hoặc màn hình: dừng lại
                    return 0
                }
                if abs(to.x - from.x) > 0.5 { facing = to.x > from.x ? 1 : -1 }
                hop = Hop(start: now, fromX: x, fromDepth: depth, toX: nextX, toDepth: nextDepth)
            }
            guard let current = hop else { return 0 }
            let u = min(1, (now - current.start) / style.hopDuration)
            let e = u < 0.5 ? 2 * u * u : 1 - pow(-2 * u + 2, 2) / 2
            x = current.fromX + (current.toX - current.fromX) * e
            depth = current.fromDepth + (current.toDepth - current.fromDepth) * e
            let arc = sin(Double.pi * u)
            if u >= 1 {
                x = current.toX
                depth = current.toDepth
                hop = nil
                nextHop = now + random.value(in: style.pause)
            }
            return arc
        }
    }
}

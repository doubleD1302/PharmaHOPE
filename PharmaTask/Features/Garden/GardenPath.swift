import CoreGraphics

/// Lối mòn lát đá trong bức tranh nền vườn, mô tả bằng toạ độ ảnh 1200x675 (cùng tỉ lệ với ảnh nền 1500x844).
/// Thú chỉ đi trong phạm vi lối mòn này: ngang theo bề rộng đá, lên xuống dọc theo đường mòn.
enum GardenPath {
    static let imageSize = CGSize(width: 1200, height: 675)

    /// (y, tâm x, nửa bề rộng) của lối mòn tại từng độ cao trong ảnh.
    static let samples: [(y: Double, cx: Double, hw: Double)] = [
        (400, 888, 55), (430, 850, 90), (465, 765, 125), (510, 665, 135), (565, 520, 190), (620, 460, 240), (665, 445, 255)
    ]

    static func at(y: Double) -> (cx: Double, hw: Double) {
        guard let first = samples.first, let last = samples.last else { return (0, 0) }
        if y <= first.y { return (first.cx, first.hw) }
        for index in 1..<samples.count where y <= samples[index].y {
            let a = samples[index - 1], b = samples[index]
            let u = (y - a.y) / (b.y - a.y)
            return (a.cx + (b.cx - a.cx) * u, a.hw + (b.hw - a.hw) * u)
        }
        return (last.cx, last.hw)
    }

    /// Xa thì nhỏ hơn: từ 0,62 (xa nhất) đến 1 (gần nhất).
    static func perspective(imageY: Double) -> Double {
        0.62 + 0.38 * min(1, max(0, (imageY - 400) / 260))
    }
}

/// Phép chiếu từ lối mòn trong ảnh lên màn hình, theo đúng cách ảnh nền được phủ kín màn hình (aspect fill, căn giữa),
/// cộng với khung sân khấu của cảnh để biết đoạn lối mòn nào đi được (không chui xuống dưới nút, không ra ngoài màn hình).
struct GardenPathContext: Equatable {
    let screen: CGSize
    /// Khung sân khấu trên màn hình, gốc ở góc trên trái (x tính trong trang, y tính toàn màn hình).
    let frame: CGRect
    let scale: Double
    let origin: CGPoint
    let yNear: Double
    let yFar: Double

    init?(screen: CGSize, frame: CGRect) {
        guard screen.width > 0, screen.height > 0, frame.width > 0, frame.height > 0 else { return nil }
        let s = max(Double(screen.width) / Double(GardenPath.imageSize.width), Double(screen.height) / Double(GardenPath.imageSize.height))
        let ox = (Double(screen.width) - Double(GardenPath.imageSize.width) * s) / 2
        let oy = (Double(screen.height) - Double(GardenPath.imageSize.height) * s) / 2
        self.screen = screen
        self.frame = frame
        self.scale = s
        self.origin = CGPoint(x: ox, y: oy)
        let near = min(655, (Double(frame.maxY) - 12 - oy) / s)
        self.yNear = near
        self.yFar = min(near - 40, max(405, (Double(frame.minY) + 12 - oy) / s))
    }

    /// Điểm trên màn hình của vị trí (x ngang 0 đến 1 trên bề rộng lối mòn, depth 0 gần đến 1 xa) và độ cao tương ứng trong ảnh.
    /// Trả về nil nếu điểm ra ngoài khung nhìn khi `enforceBounds` bật.
    func project(x: Double, depth: Double, enforceBounds: Bool = true) -> (screen: CGPoint, imageY: Double)? {
        let y = yNear - depth * (yNear - yFar)
        let p = GardenPath.at(y: y)
        let imageX = p.cx + (x - 0.5) * 2 * p.hw * 0.78
        let point = CGPoint(x: origin.x + imageX * scale, y: origin.y + y * scale)
        if enforceBounds && (point.x < frame.minX + 30 || point.x > frame.maxX - 30) { return nil }
        return (point, y)
    }

    /// Đổi điểm trên màn hình sang toạ độ của cảnh SpriteKit (gốc ở góc dưới trái, y hướng lên).
    func scenePoint(fromScreen point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - frame.minX, y: frame.height - (point.y - frame.minY))
    }
}

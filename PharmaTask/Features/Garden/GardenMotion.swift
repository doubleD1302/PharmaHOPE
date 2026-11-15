import Foundation

enum GardenMotion: String, CaseIterable {
    case breathing, hopping, flying, crawling, perched

}

struct GardenCreature: Identifiable, Equatable {
    let id: String
    let name: String
    let motion: GardenMotion
    var resource: String { "HopeCreature" + id }

    static let mascot = GardenCreature(id: "Mascot", name: "Bạn đồng hành Hope", motion: .breathing)
    static let animals: [GardenCreature] = [
        .init(id: "046", name: "Thỏ", motion: .hopping),
        .init(id: "047", name: "Nhím", motion: .breathing),
        .init(id: "048", name: "Hươu con", motion: .breathing),
        .init(id: "049", name: "Sóc", motion: .hopping),
        .init(id: "050", name: "Chim cổ đỏ", motion: .perched),
        .init(id: "051", name: "Chim sẻ", motion: .perched),
        .init(id: "052", name: "Chim xanh", motion: .perched),
        .init(id: "053", name: "Bướm trắng", motion: .flying),
        .init(id: "054", name: "Bướm vàng", motion: .flying),
        .init(id: "055", name: "Ong", motion: .flying),
        .init(id: "056", name: "Bọ rùa", motion: .crawling),
        .init(id: "057", name: "Ếch", motion: .hopping),
        .init(id: "058", name: "Chuồn chuồn", motion: .flying),
        .init(id: "059", name: "Ốc sên", motion: .crawling),
        .init(id: "060", name: "Vịt con", motion: .breathing),
        .init(id: "061", name: "Chim nhỏ", motion: .perched),
        .init(id: "062", name: "Sâu", motion: .crawling),
        .init(id: "063", name: "Rùa", motion: .crawling),
        .init(id: "064", name: "Bướm đêm", motion: .flying),
        .init(id: "065", name: "Cáo con", motion: .breathing)
    ]
}

struct GardenAnimationClock {
    private(set) var elapsed = 0.0
    private var previous: TimeInterval?

    mutating func resetFrame() { previous = nil }

    mutating func advance(to time: TimeInterval) {
        if let previous { elapsed += min(1.0 / 20, max(0, time - previous)) }
        previous = time
    }
}

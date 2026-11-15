import Foundation

/// Luật tưới cây: mỗi ngày tối đa 3 lần, hai lần liền nhau cách ít nhất 4 giờ.
/// Nhật ký tưới là danh sách mốc thời gian lưu thành chuỗi (giây từ 1970, ngăn bằng dấu phẩy) để đặt được trong `@AppStorage`.
enum PlantWatering {
    static let perDay = 3
    static let gap: TimeInterval = 4 * 3600

    enum Status: Equatable {
        /// Tưới được; `todayCount` là số lần đã tưới hôm nay (trước lần này).
        case ready(todayCount: Int)
        /// Mới tưới xong, còn phải chờ `wait` giây.
        case tooSoon(todayCount: Int, wait: TimeInterval)
        /// Hôm nay đã đủ số lần.
        case dayFull
    }

    static func parse(_ raw: String) -> [Date] {
        raw.split(separator: ",").compactMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }.sorted()
    }

    static func encode(_ dates: [Date]) -> String {
        dates.map { String(Int($0.timeIntervalSince1970)) }.joined(separator: ",")
    }

    static func status(log: [Date], now: Date = .now, calendar: Calendar = .current) -> Status {
        let today = log.filter { calendar.isDate($0, inSameDayAs: now) }.count
        if today >= perDay { return .dayFull }
        if let last = log.max() {
            let elapsed = now.timeIntervalSince(last)
            // Đồng hồ máy bị chỉnh lùi (elapsed âm) thì cũng chỉ chờ tối đa một khoảng cách.
            if elapsed < gap { return .tooSoon(todayCount: today, wait: min(gap, gap - elapsed)) }
        }
        return .ready(todayCount: today)
    }

    /// Thêm một lần tưới và bỏ các mốc đã quá ba ngày (không còn ảnh hưởng luật).
    static func recording(_ now: Date, in log: [Date]) -> [Date] {
        (log.filter { now.timeIntervalSince($0) < 3 * 86_400 } + [now]).sorted()
    }

    /// "3 giờ 12 phút", "45 phút".
    static func waitText(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded(.up)))
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) phút" }
        return rest == 0 ? "\(hours) giờ" : "\(hours) giờ \(rest) phút"
    }

    /// Lời nhắn khi chưa tưới được.
    static func blockedMessage(_ status: Status) -> String? {
        switch status {
        case .ready: return nil
        case .dayFull: return "Hôm nay cây đã được tưới đủ \(perDay) lần rồi. Mai tưới tiếp nhé."
        case .tooSoon(let count, let wait): return "Cây vừa được tưới rồi (hôm nay \(count)/\(perDay)). Tưới tiếp được sau \(waitText(wait))."
        }
    }
}

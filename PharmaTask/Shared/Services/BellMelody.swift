import Foundation

/// Chuông có giai điệu (âm sắc chuông thủy tinh), tổng hợp bằng mã và ghi thành tệp WAV.
/// Tệp được đặt trong Library/Sounds để thông báo hệ thống dùng làm âm báo (tối đa 30 giây), đồng thời app phát lại khi đang mở.
/// Ba đoạn nhạc dài khoảng 5 đến 7 giây, cùng giai điệu với bản web:
///  - info: câu ru nhẹ đi lên rồi xuống (sắp đến hạn, sắp đến ca, nhắc nhẹ);
///  - due: khúc hiệu vui sáng rải hợp âm Đô trưởng (đến hạn, đến giờ nhắc lại);
///  - urgent: motif dồn dập trên thang La thứ, lặp hai lần (quá hạn, sắp hết ca).
public enum BellMelody {
    public enum Kind: String, CaseIterable, Sendable {
        case info, due, urgent
        public var fileName: String { "hope-bell-\(rawValue).wav" }
    }

    public struct Note: Equatable, Sendable {
        public let time: Double       // giây
        public let frequency: Double  // Hz
        public let ring: Double       // độ ngân, giây
    }

    private static let e5 = 659.25, g5 = 783.99, a5 = 880.0, b5 = 987.77, c5 = 523.25, c6 = 1046.5, e6 = 1318.5, g6 = 1568.0

    public static func notes(for kind: Kind) -> [Note] {
        let table: [(Double, Double, Double)]
        switch kind {
        case .info:
            table = [(0, e5, 1.8), (0.5, g5, 1.8), (1, a5, 1.8), (1.5, c6, 2.6), (2.5, a5, 1.8), (3, g5, 1.8), (3.5, e5, 3.4)]
        case .due:
            table = [(0, c5, 1.6), (0.28, e5, 1.6), (0.56, g5, 1.6), (0.84, c6, 2.2), (1.6, g5, 1.6), (1.9, c6, 1.6), (2.2, e6, 2.6),
                     (3.6, c5, 1.6), (3.88, e5, 1.6), (4.16, g5, 1.6), (4.44, c6, 1.8), (4.84, e6, 1.8), (5.24, g6, 3.2)]
        case .urgent:
            table = [(0, a5, 1.4), (0.26, e5, 1.4), (0.52, a5, 1.4), (0.78, c6, 2), (1.3, b5, 1.4), (1.56, a5, 1.4), (1.82, e5, 2.2),
                     (3.1, a5, 1.4), (3.36, e5, 1.4), (3.62, a5, 1.4), (3.88, c6, 2), (4.4, e6, 1.4), (4.66, c6, 1.4), (4.92, a5, 3.2)]
        }
        return table.map { Note(time: $0.0, frequency: $0.1, ring: $0.2) }
    }

    /// Độ dài của cả đoạn nhạc, tính đến hết tiếng ngân cuối.
    public static func duration(of kind: Kind) -> Double {
        notes(for: kind).map { $0.time + $0.ring }.max() ?? 0
    }

    /// Âm sắc chuông: nốt chính, hai họa âm không nguyên (2,76 và 5,4 lần) tắt nhanh, và một tiếng ngân trầm (nửa tần số).
    private static let partials: [(multiple: Double, amplitude: Double, ringFactor: Double)] = [(1, 1, 1), (2.76, 0.26, 0.55), (5.4, 0.09, 0.3), (0.5, 0.18, 1)]

    /// Tạo mẫu âm thanh mono, giá trị trong khoảng -1 đến 1, đã chuẩn hoá đỉnh về 0,8.
    public static func samples(for kind: Kind, sampleRate: Double = 44_100) -> [Float] {
        let notes = notes(for: kind)
        let length = Int((duration(of: kind) + 0.2) * sampleRate)
        var buffer = [Float](repeating: 0, count: length)
        let attack = 0.008
        for note in notes {
            for part in partials {
                let frequency = note.frequency * part.multiple
                let duration = note.ring * part.ringFactor
                let peak = 0.2 * part.amplitude
                let start = Int(note.time * sampleRate)
                let count = min(length - start, Int((duration + 0.05) * sampleRate))
                guard count > 0 else { continue }
                let decay = log(0.0001 / peak) / (duration - attack)   // tắt dần theo hàm mũ đến gần 0
                let omega = 2 * Double.pi * frequency / sampleRate
                for i in 0..<count {
                    let t = Double(i) / sampleRate
                    let envelope = t < attack ? peak * (t / attack) : (t < duration ? peak * exp(decay * (t - attack)) : 0)
                    buffer[start + i] += Float(envelope * sin(omega * Double(i)))
                }
            }
        }
        let loudest = buffer.reduce(0) { max($0, abs($1)) }
        if loudest > 0 {
            let gain = 0.8 / loudest
            for i in buffer.indices { buffer[i] *= gain }
        }
        return buffer
    }

    /// Tệp WAV PCM 16 bit mono.
    public static func wavData(for kind: Kind, sampleRate: Int = 44_100) -> Data {
        let samples = samples(for: kind, sampleRate: Double(sampleRate))
        var data = Data()
        func append32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append32(36 + byteCount); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append32(16); append16(1); append16(1)
        append32(UInt32(sampleRate)); append32(UInt32(sampleRate * 2)); append16(2); append16(16)
        data.append(contentsOf: Array("data".utf8)); append32(byteCount)
        for sample in samples { append16(UInt16(bitPattern: Int16(max(-1, min(1, sample)) * 32_000))) }
        return data
    }

    /// Thư mục Library/Sounds, nơi iOS tìm âm thanh tuỳ chỉnh của thông báo.
    public static var soundsDirectory: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Sounds", isDirectory: true)
    }

    /// Ghi ba tệp chuông nếu chưa có. Gọi một lần lúc mở app, trên luồng nền.
    @discardableResult
    public static func installSounds() -> Bool {
        guard let directory = soundsDirectory else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for kind in Kind.allCases {
                let url = directory.appendingPathComponent(kind.fileName)
                if FileManager.default.fileExists(atPath: url.path) { continue }
                try wavData(for: kind).write(to: url, options: .atomic)
            }
            return true
        } catch { return false }
    }

    /// Loại chuông cho một thông báo đã lên lịch, theo mã nhận dạng của nó.
    public static func kind(forNotificationID id: String) -> Kind {
        if id.hasSuffix(".overdue") || id.hasPrefix("hope.clockout.") { return .urgent }
        if id.hasSuffix(".due") || id.hasSuffix(".snooze") || id.hasSuffix(".0") { return .due }
        return .info
    }
}

import AVFoundation
import Observation

public enum AmbientScene: String, CaseIterable, Identifiable, Sendable {
    case rain, leaves, stream, cafe
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .rain: return "Mưa"
        case .leaves: return "Lá cây"
        case .stream: return "Suối"
        case .cafe: return "Quán cà phê"
        }
    }
    public var detail: String {
        switch self {
        case .rain: return "Mưa nhỏ đều trên mái hiên"
        case .leaves: return "Gió lay lá, lúc lặng lúc rì rào"
        case .stream: return "Dòng nước chảy qua đá"
        case .cafe: return "Tiếng người xa xa, ấm và mờ"
        }
    }
    public var symbol: String {
        switch self {
        case .rain: return "cloud.rain"
        case .leaves: return "leaf"
        case .stream: return "drop"
        case .cafe: return "cup.and.saucer"
        }
    }
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// Bộ tạo âm thanh trực tiếp trên máy: không cần tải tệp nên luôn nghe được khi không có mạng.
/// Âm lượng tăng giảm mềm để không bao giờ bật hay tắt đột ngột.
final class AmbientSynth: @unchecked Sendable {
    // Các biến này được ghi từ luồng chính và đọc ở luồng âm thanh; giá trị đơn giản nên chấp nhận được.
    var sceneIndex = 0
    var targetGain: Float = 0
    private var gain: Float = 0
    private var voices = [Voice(seed: 0x1234ABCD), Voice(seed: 0x9E3779B9)]
    private var time: Float = 0
    private let sampleRate: Float

    init(sampleRate: Float) { self.sampleRate = sampleRate }

    struct Voice {
        var seed: UInt32
        var b0: Float = 0, b1: Float = 0, b2: Float = 0
        var brown: Float = 0
        var lpFast: Float = 0, lpMid: Float = 0, lpSlow: Float = 0, lpBubble: Float = 0
        var drop: Float = 0, ping: Float = 0, pingPhase: Float = 0, pingFreq: Float = 0

        init(seed: UInt32) { self.seed = seed }

        mutating func white() -> Float {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            return Float(seed) / Float(UInt32.max) * 2 - 1
        }
        mutating func chance(_ perSample: Float) -> Bool {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            return Float(seed) / Float(UInt32.max) < perSample
        }
        mutating func pink(_ w: Float) -> Float {
            b0 = 0.99765 * b0 + w * 0.0990460
            b1 = 0.96300 * b1 + w * 0.2965164
            b2 = 0.57000 * b2 + w * 1.0526913
            return (b0 + b1 + b2 + w * 0.1848) * 0.11
        }

        mutating func next(scene: Int, t: Float, sampleRate: Float) -> Float {
            let w = white()
            switch scene {
            case 0: // mưa: nhiễu hồng sáng cùng giọt nhỏ ngẫu nhiên
                lpFast += 0.45 * (w - lpFast)
                var s = pink(w) * 0.55 + lpFast * 0.30
                if chance(1.0 / 5200) { drop = 0.5 + 0.5 * abs(white()) }
                s += drop * white() * 0.22
                drop *= 0.9955
                return s * (0.92 + 0.08 * sin(2 * .pi * 0.11 * t))
            case 1: // lá cây: nhiễu hồng bỏ trầm, lúc dâng lúc lặng như gió
                let p = pink(w)
                lpMid += 0.06 * (p - lpMid)
                let hp = p - lpMid
                let g1 = 0.5 + 0.5 * sin(2 * .pi * 0.063 * t)
                let g2 = 0.5 + 0.5 * sin(2 * .pi * 0.137 * t + 1.3)
                let gust = 0.18 + 0.82 * (g1 * g2)
                return hp * 1.7 * gust
            case 2: // suối: nhiễu lọc thấp, sủi bọt lăn tăn
                lpFast += 0.22 * (w - lpFast)
                lpBubble += 0.0025 * (white() - lpBubble)
                let bubble = max(-0.3, min(0.3, lpBubble * 28))
                return (lpFast * 0.9 + pink(w) * 0.35) * (0.78 + bubble)
            default: // quán cà phê: tiếng ồn nâu trầm ấm và vài tiếng chạm cốc xa
                brown = (brown + 0.02 * w) / 1.02
                lpSlow += 0.10 * (brown * 3.3 - lpSlow)
                var s = lpSlow * (0.8 + 0.2 * sin(2 * .pi * 0.21 * t))
                if chance(1.0 / 90_000) { ping = 0.35; pingPhase = 0; pingFreq = 2300 + 900 * abs(white()) }
                if ping > 0.0005 {
                    s += sin(pingPhase) * ping * 0.12
                    pingPhase += 2 * .pi * pingFreq / sampleRate
                    ping *= 0.9993
                }
                return s
            }
        }
    }

    func render(into left: UnsafeMutablePointer<Float>?, right: UnsafeMutablePointer<Float>?, frames: Int) {
        for frame in 0..<frames {
            gain += (targetGain - gain) * 0.00012 // khoảng hai giây để lên hoặc xuống hẳn
            time += 1 / sampleRate
            if time > 100_000 { time = 0 }
            let l = voices[0].next(scene: sceneIndex, t: time, sampleRate: sampleRate) * gain
            let r = voices[1].next(scene: sceneIndex, t: time, sampleRate: sampleRate) * gain
            left?[frame] = max(-1, min(1, l))
            right?[frame] = max(-1, min(1, r))
        }
    }
}

@MainActor
@Observable
public final class AmbientSoundEngine {
    public static let shared = AmbientSoundEngine()

    public private(set) var isPlaying = false
    public private(set) var scene: AmbientScene = .rain
    public private(set) var volume: Double = 0.7
    public private(set) var timerEndsAt: Date?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var synth: AmbientSynth?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    private init() {}

    public func play(_ scene: AmbientScene) {
        stopTask?.cancel()
        self.scene = scene
        if engine == nil && !startEngine() { return }
        synth?.sceneIndex = scene.index
        isPlaying = true
        applyVolume()
    }

    public func setVolume(_ value: Double) {
        volume = min(max(value, 0), 1)
        applyVolume()
    }

    public func toggle() { isPlaying ? stop() : play(scene) }

    public func select(_ scene: AmbientScene) {
        self.scene = scene
        if isPlaying { synth?.sceneIndex = scene.index }
    }

    /// Làm nhỏ dần rồi tắt hẳn để không bị giật.
    public func stop() {
        timerTask?.cancel(); timerEndsAt = nil
        synth?.targetGain = 0
        isPlaying = false
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled, let self else { return }
            self.shutdownEngine()
        }
    }

    public func setTimer(minutes: Int?) {
        timerTask?.cancel()
        guard let minutes, minutes > 0 else { timerEndsAt = nil; return }
        let end = Date().addingTimeInterval(Double(minutes) * 60)
        timerEndsAt = end
        timerTask = Task { [weak self] in
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard !Task.isCancelled, let self else { return }
            self.stop()
        }
    }

    private func applyVolume() {
        guard isPlaying else { return }
        synth?.targetGain = Float(volume) * 0.55
    }

    private func startEngine() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let engine = AVAudioEngine()
            let sampleRate = Float(session.sampleRate > 0 ? session.sampleRate : 44_100)
            let synth = AmbientSynth(sampleRate: sampleRate)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 2) else { return false }
            let node = AVAudioSourceNode(format: format) { [synth] _, _, frameCount, audioBufferList -> OSStatus in
                let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
                let left = buffers.count > 0 ? buffers[0].mData?.assumingMemoryBound(to: Float.self) : nil
                let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
                synth.render(into: left, right: right, frames: Int(frameCount))
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            synth.sceneIndex = scene.index
            synth.targetGain = Float(volume) * 0.55
            try engine.start()
            self.engine = engine; self.synth = synth
            observeInterruptions()
            return true
        } catch {
            shutdownEngine()
            return false
        }
    }

    private func shutdownEngine() {
        engine?.stop()
        engine = nil; synth = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in self?.stop() }
        }
    }
}

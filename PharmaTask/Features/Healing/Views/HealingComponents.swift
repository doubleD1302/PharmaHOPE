import SwiftUI

extension Color {
    /// Màu cố định (không đổi theo sáng/tối) cho các cảnh vườn và phiên nghỉ.
    static func healing(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255,
              opacity: opacity)
    }
}

/// Số giả ngẫu nhiên ổn định theo chỉ số: các hạt luôn ở cùng vị trí giữa các khung hình.
func healingHash(_ n: Double) -> Double {
    let x = sin(n * 127.1 + 311.7) * 43_758.5453
    return x - floor(x)
}

func healingFrac(_ x: Double) -> Double { x - floor(x) }

/// Đường cong mượt 0→1 cho nhịp thở và chuyển cảnh.
func healingEase(_ x: Double) -> Double {
    let clamped = min(max(x, 0), 1)
    return 0.5 - 0.5 * cos(.pi * clamped)
}

/// Nhấn xuống rất nhẹ, nảy lại chậm. Dùng cho mọi nút trong tab Vườn.
struct SoftPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

/// Hiện dần từ dưới lên, có thể xếp so le theo `delay`.
struct SoftAppear: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.85).delay(delay)
                withAnimation(animation) { shown = true }
            }
    }
}

extension View {
    func softAppear(delay: Double = 0) -> some View { modifier(SoftAppear(delay: delay)) }
}

/// Bầu trời sao lấp lánh chậm. `level` 0...1 là độ hiện.
struct StarField: View {
    var level: Double
    var count = 26
    var paused = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: paused)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                guard level > 0.01 else { return }
                for i in 0..<count {
                    let h = Double(i)
                    let x = healingHash(h * 1.7) * size.width
                    let y = healingHash(h * 3.1) * size.height
                    let twinkle = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * (0.5 + healingHash(h * 5.3)) + h * 2.1))
                    let radius = 0.7 + healingHash(h * 7.9) * 1.1
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(level * twinkle * 0.9)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct HealingCardTitle: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(HopeTheme.ink)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(HopeTheme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

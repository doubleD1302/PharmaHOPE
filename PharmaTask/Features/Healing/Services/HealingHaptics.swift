import UIKit

/// Haptic rất nhẹ, chỉ ở các thời điểm chuyển nhịp. Tắt được trong tab Vườn.
@MainActor
public enum HealingHaptics {
    public static let preferenceKey = "healing.haptics"

    public static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }

    public static func soft() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare(); generator.impactOccurred(intensity: 0.6)
    }

    public static func settle() {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare(); generator.notificationOccurred(.success)
    }
}

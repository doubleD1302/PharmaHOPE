import SwiftUI

public struct ProCheckbox: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isChecked: Bool
    var isUrgent: Bool
    var onToggle: () -> Void
    
    public init(isChecked: Bool, isUrgent: Bool = false, onToggle: @escaping () -> Void) {
        self.isChecked = isChecked
        self.isUrgent = isUrgent
        self.onToggle = onToggle
    }
    
    public var body: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isChecked ? HopeTheme.accent : (isUrgent ? HopeTheme.urgentSurface : HopeTheme.surface))
                    .frame(width: 20, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                isChecked ? HopeTheme.accent : (isUrgent ? HopeTheme.urgent : HopeTheme.secondary),
                                lineWidth: 1.5
                            )
                    )
                
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(HopeTheme.onAccent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isChecked ? "Đã hoàn thành" : "Chưa hoàn thành")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isChecked)
    }
}

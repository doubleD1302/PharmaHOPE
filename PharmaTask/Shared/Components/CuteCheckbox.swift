import SwiftUI

public struct CuteCheckbox: View {
    var isChecked: Bool
    var isUrgent: Bool
    var onToggle: () -> Void
    public init(isChecked: Bool, isUrgent: Bool = false, onToggle: @escaping () -> Void) {
        self.isChecked = isChecked; self.isUrgent = isUrgent; self.onToggle = onToggle
    }
    public var body: some View {
        ProCheckbox(isChecked: isChecked, isUrgent: isUrgent, onToggle: onToggle)
    }
}

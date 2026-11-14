import SwiftUI

public struct HopeBrandMark: View {
    public var size: CGFloat
    public init(size: CGFloat = 36) { self.size = size }
    public var body: some View {
        Image("HopeMark").resizable().scaledToFit().frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

public struct HopeIllustration: View {
    public var name: String
    public var width: CGFloat
    public init(_ name: String, width: CGFloat = 120) { self.name = name; self.width = width }
    public var body: some View {
        Image(name).resizable().scaledToFit().frame(width: width)
            .accessibilityHidden(true)
    }
}

public struct HopeCard: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .padding(20)
            .background(HopeTheme.surface, in: RoundedRectangle(cornerRadius: HopeTheme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HopeTheme.cardRadius, style: .continuous)
                .strokeBorder(HopeTheme.border.opacity(0.7), lineWidth: 1))
    }
}

public extension View {
    func hopeCard() -> some View { modifier(HopeCard()) }
}

public struct HopePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16)
            .foregroundStyle(HopeTheme.onAccent)
            .background(HopeTheme.accent, in: RoundedRectangle(cornerRadius: HopeTheme.controlRadius, style: .continuous))
            .opacity(!isEnabled ? 0.45 : (configuration.isPressed ? 0.82 : 1))
    }
}

public struct HopeSectionHeading: View {
    let title: String
    let count: Int?
    public init(_ title: String, count: Int? = nil) { self.title = title; self.count = count }
    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(HopeTheme.ink)
            if let count = count {
                Text(count.formatted()).font(.subheadline.monospacedDigit()).foregroundStyle(HopeTheme.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

public struct HopePriorityTag: View {
    let priority: TaskPriority
    public init(_ priority: TaskPriority) { self.priority = priority }
    public var body: some View {
        Text(priority == .high ? "Ưu tiên" : (priority == .low ? "Cuối ca" : "Trong ca"))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(priority == .high ? HopeTheme.urgent : HopeTheme.secondary)
            .background(priority == .high ? HopeTheme.urgentSurface : HopeTheme.surfaceMuted, in: Capsule())
    }
}

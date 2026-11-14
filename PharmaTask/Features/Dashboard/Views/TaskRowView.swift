import SwiftUI

/// One button per row: a single action and a full-width, accessible hit area.
public struct TaskRowView: View {
    @Bindable var task: TaskItem
    var onToggle: () -> Void
    public init(task: TaskItem, onToggle: @escaping () -> Void) { self.task = task; self.onToggle = onToggle }

    public var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2.weight(.light))
                    .foregroundStyle(task.isCompleted ? HopeTheme.accent : HopeTheme.secondary)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title)
                        .font(.body.weight(task.isCompleted ? .regular : .medium))
                        .strikethrough(task.isCompleted, color: HopeTheme.secondary)
                        .foregroundStyle(task.isCompleted ? HopeTheme.secondary : HopeTheme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let notes = task.notes, !notes.isEmpty {
                        Text(notes).font(.subheadline).foregroundStyle(HopeTheme.secondary)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    if !task.isCompleted {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { metadata }
                            VStack(alignment: .leading, spacing: 8) { metadata }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(HopeTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(HopeTheme.border.opacity(0.75), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(task.isCompleted ? "Đã hoàn thành" : "Chưa hoàn thành")
        .accessibilityHint(task.isCompleted ? "Chạm để mở lại công việc" : "Chạm để xác nhận hoàn thành")
    }

    @ViewBuilder private var metadata: some View {
        HopePriorityTag(task.priority)
        TaskDeadlineLabel(task: task)
    }
}

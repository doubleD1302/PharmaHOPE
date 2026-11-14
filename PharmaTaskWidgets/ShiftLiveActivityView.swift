import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

public struct ShiftLiveActivityView: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftActivityAttributes.self) { context in
            HopeLiveCard(state: context.state, endTime: context.attributes.shiftEndTime)
                .activityBackgroundTint(HopeTheme.surface)
                .activitySystemActionForegroundColor(HopeTheme.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Hope", systemImage: "leaf.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(HopeTheme.mint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.shiftEndTime, style: .time)
                        .font(.caption.monospacedDigit()).foregroundStyle(HopeTheme.apricot)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let task = context.state.pendingTasks.first {
                        Button(intent: CompleteTaskIntent(taskID: task.id)) {
                            Label(task.title, systemImage: "circle")
                                .font(.subheadline).lineLimit(2).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint("Đánh dấu hoàn thành công việc")
                    } else {
                        Label("Đã xong mọi việc", systemImage: "checkmark.circle")
                            .font(.subheadline).foregroundStyle(HopeTheme.mint)
                    }
                }
            } compactLeading: {
                Image(systemName: "leaf.fill").foregroundStyle(HopeTheme.mint)
            } compactTrailing: {
                Text("\(max(0, context.state.totalCount - context.state.completedCount))")
                    .font(.caption2.monospacedDigit()).foregroundStyle(HopeTheme.mint)
                    .accessibilityLabel("Việc chưa hoàn thành")
            } minimal: {
                Image(systemName: "leaf.fill").foregroundStyle(HopeTheme.mint)
            }
        }
    }
}

private struct HopeLiveCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let state: ShiftActivityAttributes.ContentState
    let endTime: Date
    private var progress: Double {
        guard state.totalCount > 0 else { return 0 }
        return min(1, max(0, Double(state.completedCount) / Double(state.totalCount)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HopeBrandMark(size: 24)
                Text(state.shiftName).font(.caption.weight(.semibold)).foregroundStyle(HopeTheme.ink)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Text(endTime, style: .time).font(.caption2.monospacedDigit()).foregroundStyle(HopeTheme.secondary)
                    .fixedSize()
            }
            HStack(spacing: 12) {
                ProgressView(value: progress).tint(HopeTheme.accent)
                    .accessibilityLabel("Tiến độ ca")
                Text("\(state.completedCount)/\(state.totalCount)")
                    .font(.caption2.monospacedDigit()).foregroundStyle(HopeTheme.secondary).fixedSize()
            }
            if state.pendingTasks.isEmpty {
                Label("Đã hoàn thành mọi việc.", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(HopeTheme.accent)
            } else {
                ForEach(state.pendingTasks.prefix(typeSize.isAccessibilitySize ? 1 : 2), id: \.id) { task in
                    Button(intent: CompleteTaskIntent(taskID: task.id)) {
                        HStack(spacing: 9) {
                            Image(systemName: "circle").font(.body).foregroundStyle(HopeTheme.accent)
                            Text(task.title).font(.caption.weight(.medium)).foregroundStyle(HopeTheme.ink)
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            if task.priority == "high" {
                                Circle().fill(HopeTheme.urgent).frame(width: 5, height: 5)
                                    .accessibilityLabel("Ưu tiên")
                            }
                        }
                        .frame(minHeight: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityHint("Đánh dấu hoàn thành công việc")
                }
            }
        }.padding(16)
    }
}

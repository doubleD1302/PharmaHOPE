import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

struct WidgetTaskItem: Identifiable {
    let id: String
    let title: String
    let priority: String
}

struct TaskTimelineEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTaskItem]
    let totalCount: Int
    let completedCount: Int
    var shiftName: String = "Ca của bạn"
    var failed = false
    var pendingCount: Int { max(0, totalCount - completedCount) }
    var emptyMessage: String {
        if failed { return "Mở Hope để kiểm tra dữ liệu." }
        return totalCount == 0 ? "Thêm việc cho ca trong Hope." : "Đã hoàn thành mọi việc."
    }
}

struct TaskTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskTimelineEntry {
        TaskTimelineEntry(date: .now, tasks: [
            WidgetTaskItem(id: "sample-1", title: "Kiểm đếm quỹ đầu ca", priority: "high"),
            WidgetTaskItem(id: "sample-2", title: "Ghi nhiệt độ tủ thuốc", priority: "medium")
        ], totalCount: 5, completedCount: 3, shiftName: "Ca Sáng")
    }
    func getSnapshot(in context: Context, completion: @escaping (TaskTimelineEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : fetchEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskTimelineEntry>) -> Void) {
        let date = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [fetchEntry()], policy: .after(date)))
    }

    private func fetchEntry() -> TaskTimelineEntry {
        do {
            let context = ModelContext(SharedModelContainer.shared)
            var shiftQuery = FetchDescriptor<ShiftConfig>(predicate: #Predicate { $0.isActive },
                sortBy: [SortDescriptor(\ShiftConfig.startTime, order: .reverse)])
            shiftQuery.fetchLimit = 1
            let shift = try context.fetch(shiftQuery).first
            let shiftID = shift?.id
            let tasks = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.shiftId == shiftID && $0.deletedAt == nil }))
            let snapshot = TaskDashboardSnapshot(tasks: tasks)
            return TaskTimelineEntry(date: .now, tasks: snapshot.pending.prefix(3).map {
                WidgetTaskItem(id: $0.id, title: $0.title, priority: $0.priorityRaw)
            }, totalCount: snapshot.total, completedCount: snapshot.completed.count,
               shiftName: shift?.name ?? "Việc chưa gắn ca")
        } catch {
            return TaskTimelineEntry(date: .now, tasks: [], totalCount: 0, completedCount: 0, failed: true)
        }
    }
}

struct PharmaTaskLockScreenWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var typeSize
    let entry: TaskTimelineEntry
    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "leaf.fill").font(.caption)
                    Text("\(entry.completedCount)/\(entry.totalCount)").font(.caption2.monospacedDigit())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hope: \(entry.completedCount) trên \(entry.totalCount) việc hoàn thành")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Label("Hope", systemImage: "leaf.fill").font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(entry.completedCount)/\(entry.totalCount)").font(.caption2.monospacedDigit())
                }
                if entry.tasks.isEmpty {
                    Text(entry.emptyMessage).font(.caption).lineLimit(2)
                } else {
                    ForEach(entry.tasks.prefix(typeSize.isAccessibilitySize ? 1 : 2)) { task in
                        Text(task.title).font(.caption2).lineLimit(1)
                    }
                }
            }
        case .systemMedium:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    HopeBrandMark(size: 26)
                    Text(entry.shiftName).font(.subheadline.weight(.semibold)).foregroundStyle(HopeTheme.ink).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(entry.pendingCount) việc").font(.caption).foregroundStyle(HopeTheme.secondary).fixedSize()
                }
                if entry.tasks.isEmpty {
                    Text(entry.emptyMessage).font(.subheadline).foregroundStyle(HopeTheme.secondary)
                        .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    ForEach(entry.tasks.prefix(typeSize.isAccessibilitySize ? 1 : 2)) { task in
                        Button(intent: CompleteTaskIntent(taskID: task.id)) {
                            HStack(spacing: 9) {
                                Image(systemName: "circle").foregroundStyle(HopeTheme.accent)
                                Text(task.title).foregroundStyle(HopeTheme.ink).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if task.priority == "high" { Circle().fill(HopeTheme.urgent).frame(width: 5, height: 5) }
                            }
                            .font(.subheadline).frame(minHeight: 30).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint("Đánh dấu hoàn thành công việc")
                    }
                }
            }
        default:
            Text("Hope").font(.headline)
        }
    }
}

public struct PharmaTaskLockScreenWidget: Widget {
    let kind = "PharmaTaskLockScreenWidget"
    public init() {}
    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskTimelineProvider()) { entry in
            PharmaTaskLockScreenWidgetEntryView(entry: entry)
                .containerBackground(HopeTheme.surface, for: .widget)
        }
        .configurationDisplayName("Hope · Ca của bạn")
        .description("Xem và hoàn thành những việc đang chờ trong ca trực.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .systemMedium])
    }
}

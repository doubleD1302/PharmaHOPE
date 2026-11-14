#if DEBUG
import SwiftUI
import SwiftData

@MainActor
enum HopePreviewData {
    static let container: ModelContainer = {
        let schema = SharedModelContainer.schema
        let container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let shift = ShiftConfig(name: "Ca Chiều – Bàn giao cuối ngày", startTime: .now,
                                endTime: .now.addingTimeInterval(8 * 3600), isActive: true)
        container.mainContext.insert(shift)
        let tasks = [
            TaskItem(title: "Kiểm đếm quỹ đầu ca và ký biên bản bàn giao", notes: "Đối soát tiền mặt tại quầy số 1 và quầy số 2.", priority: .high, dueTime: "18:30", shiftId: shift.id),
            TaskItem(title: "Đo và ghi nhiệt độ, độ ẩm tủ thuốc", notes: "Kiểm tra đầy đủ dấu tiếng Việt: ă â ê ô ơ ư đ, Nguyễn, dưỡng, quỹ, kiểm kê.", priority: .medium, shiftId: shift.id),
            TaskItem(title: "Vệ sinh khay đếm thuốc", notes: "Đã ghi nhận hoàn thành.", isCompleted: true, shiftId: shift.id)
        ]
        for task in tasks { container.mainContext.insert(task) }
        try! container.mainContext.save()
        return container
    }()
}

/// Actual SwiftUI previews, separate from the desktop web simulator.
@MainActor
struct HopeDashboardPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .previewDevice(PreviewDevice(rawValue: "iPhone SE (3rd generation)"))
                .previewDisplayName("iPhone nhỏ – tiếng Việt")
            ContentView()
                .previewDevice(PreviewDevice(rawValue: "iPhone 15"))
                .previewDisplayName("iPhone – mặc định")
            ContentView()
                .preferredColorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone 15"))
                .previewDisplayName("iPhone – giao diện tối")
            ContentView()
                .environment(\.dynamicTypeSize, .accessibility2)
                .previewDevice(PreviewDevice(rawValue: "iPhone 15"))
                .previewDisplayName("iPhone – chữ trợ năng")
        }
        .environment(\.locale, Locale(identifier: "vi_VN"))
        .modelContainer(HopePreviewData.container)
    }
}

@MainActor
struct HopeSchedulePreviews: PreviewProvider {
    static var previews: some View {
        Group {
            ShiftManagementView().previewDisplayName("Lịch ca – sáng")
            ShiftManagementView().preferredColorScheme(.dark).previewDisplayName("Lịch ca – tối")
            ShiftManagementView().environment(\.dynamicTypeSize, .accessibility2)
                .previewDisplayName("Lịch ca – chữ trợ năng")
        }
        .previewDevice(PreviewDevice(rawValue: "iPhone 15"))
        .environment(\.locale, Locale(identifier: "vi_VN"))
        .modelContainer(HopePreviewData.container)
    }
}

struct HopeSettingsPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            SettingsView().previewDisplayName("Cài đặt – sáng")
            SettingsView().preferredColorScheme(.dark).previewDisplayName("Cài đặt – tối")
        }
        .previewDevice(PreviewDevice(rawValue: "iPhone 15"))
        .environment(\.locale, Locale(identifier: "vi_VN"))
    }
}
#endif

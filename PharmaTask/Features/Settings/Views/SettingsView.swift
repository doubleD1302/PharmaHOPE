import SwiftUI
import UIKit
import UserNotifications

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("GEMINI_API_KEY", store: UserDefaults(suiteName: SharedModelContainer.appGroupID))
    private var apiKey = ""
    @State private var draftKey = ""
    @State private var notificationsAllowed = false
    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        HopeBrandMark(size: 60)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Hope").font(.title2.weight(.semibold)).foregroundStyle(HopeTheme.ink)
                            Text("Gọn công việc. Nhẹ ca trực.")
                                .font(.subheadline).foregroundStyle(HopeTheme.secondary)
                        }
                    }.padding(.vertical, 12)
                }.listRowBackground(HopeTheme.surface)

                Section {
                    Label(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Chưa kết nối Gemini" : "Đã thêm khóa Gemini",
                          systemImage: "sparkles")
                        .foregroundStyle(HopeTheme.accent)
                    SecureField("Gemini API Key", text: $draftKey)
                        .font(.body).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Khóa API Gemini cá nhân")
                } header: { Text("Trợ lý cho ca làm") } footer: {
                    Text("Khi bạn chọn bóc tách, nội dung tin nhắn được gửi đến Gemini. Chỉ chọn những thông tin bạn muốn chia sẻ.")
                }
                .listRowBackground(HopeTheme.surface)

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Từ tin nhắn thành đầu việc", systemImage: "text.viewfinder")
                            .font(.headline).foregroundStyle(HopeTheme.ink)
                        Text("Sao chép nội dung Zalo, quay về Hope và chọn Gọn việc từ Zalo. Bạn cũng có thể gửi văn bản hoặc ảnh qua menu Chia sẻ. Duyệt và sửa bản nháp trước khi lưu công việc.")
                            .font(.subheadline).foregroundStyle(HopeTheme.secondary)
                        Divider()
                        Label("Thêm vào Phím tắt", systemImage: "square.stack.3d.up")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(HopeTheme.ink)
                        Text("Gán Bóc tách việc Zalo vào Chạm vào mặt lưng trong Trợ năng để mở nhanh khi cần.")
                            .font(.subheadline).foregroundStyle(HopeTheme.secondary)
                    }.padding(.vertical, 6)
                } header: { Text("Một chút tiện hơn") }
                .listRowBackground(HopeTheme.surface)

                Section {
                    NavigationLink { RoutineLibraryView() } label: { Label("Checklist theo loại ca", systemImage: "checklist") }
                    NavigationLink { ImportInboxView() } label: { Label("Bản nháp AI chờ duyệt", systemImage: "tray") }
                    NavigationLink { BackupView() } label: { Label("Sao lưu và khôi phục", systemImage: "externaldrive") }
                } header: { Text("Dữ liệu của bạn") }
                .listRowBackground(HopeTheme.surface)

                Section {
                    Label(notificationsAllowed ? "Thông báo đã được cho phép" : "Thông báo chưa được cho phép", systemImage: "bell")
                    Button("Mở cài đặt thông báo trên iPhone") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } header: { Text("Nhắc công việc") } footer: {
                    Text("Đặt hạn trong phần chỉnh sửa việc. Nhấn giữ việc hoặc mở thông báo để hoãn 10–15 phút. iPhone cần cho phép thông báo để hiển thị lời nhắc.")
                }
                .listRowBackground(HopeTheme.surface)

                Section {
                    LabeledContent("Phiên bản", value: version)
                    LabeledContent("Lưu công việc", value: "Trên thiết bị")
                    Label("Chữ theo cài đặt iPhone", systemImage: "textformat.size")
                    Label("Giao diện sáng và tối", systemImage: "circle.lefthalf.filled")
                } header: { Text("Về Hope") }
                .foregroundStyle(HopeTheme.ink).listRowBackground(HopeTheme.surface)
            }
            .scrollContentBackground(.hidden).background(HopeTheme.background)
            .navigationTitle("Cài đặt").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        apiKey = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
            .tint(HopeTheme.accent)
            .onAppear { draftKey = apiKey }
            .task { await updateNotificationPermission() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await updateNotificationPermission() } }
            }
        }
        .presentationDragIndicator(.visible)
    }
    private func updateNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

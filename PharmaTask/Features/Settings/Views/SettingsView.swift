import SwiftUI
import UIKit
import UserNotifications

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasKey = GeminiKeyStore.hasUserKey
    @State private var draftKey = ""
    @State private var keySaveFailed = false
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
                    Label(hasKey ? "Đã thêm khóa Gemini của bạn" : (GeminiKeyStore.usesBundledKey ? "Hope đã kết nối Gemini sẵn, bạn không cần cài đặt" : "Chưa kết nối Gemini"), systemImage: "sparkles")
                        .foregroundStyle(HopeTheme.accent)
                    SecureField(hasKey ? "Nhập khóa mới để thay thế" : (GeminiKeyStore.usesBundledKey ? "Khóa riêng (không bắt buộc)" : "Gemini API Key"), text: $draftKey)
                        .font(.body).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Khóa API Gemini cá nhân")
                    if hasKey {
                        Button("Xóa khóa khỏi máy", role: .destructive) {
                            GeminiKeyStore.remove(); hasKey = false; draftKey = ""
                        }
                    }
                } header: { Text("Lời nhắn cho khu vườn") } footer: {
                    Text("Khóa riêng (nếu bạn nhập) được lưu trong Keychain của iPhone và được dùng thay cho khóa dựng sẵn. Hope dùng Gemini cho lời nhắn, câu trích của vườn, lời nhắc nghỉ, câu mở đầu nhật ký, thư tuần và trò chuyện với các nhân vật. Mặc định chỉ cảm xúc bạn chọn, buổi trong ngày hoặc số lượng việc được gửi đi, không gửi tên việc. Bài nhật ký chỉ được gửi khi bạn tự bấm nghe lời đáp và đồng ý. Tin nhắn bạn gõ khi trò chuyện với nhân vật được gửi đi sau khi bạn đồng ý một lần. Không có khóa hoặc không có mạng, Hope dùng nội dung viết sẵn.")
                }
                .listRowBackground(HopeTheme.surface)

                Section {
                    NavigationLink { RoutineLibraryView() } label: { Label("Checklist theo loại ca", systemImage: "checklist") }
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
                        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !key.isEmpty && !GeminiKeyStore.save(key) {
                            keySaveFailed = true
                            return
                        }
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
            .tint(HopeTheme.accent)
            .alert("Chưa lưu được khóa", isPresented: $keySaveFailed) {
                Button("Đóng", role: .cancel) {}
            } message: { Text("iPhone không cho lưu khóa vào Keychain lúc này. Hãy thử lại sau.") }
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

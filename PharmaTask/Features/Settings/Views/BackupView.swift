import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HopeBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw HopeDataError.invalid("Không đọc được tệp.") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor
struct BackupView: View {
    @Environment(\.modelContext) private var context
    @State private var exporting = false
    @State private var importing = false
    @State private var document: HopeBackupDocument?
    @State private var preview: HopeBackup?
    @State private var includeGarden = true
    @State private var busy = false
    @State private var message: String?
    @State private var viewModel = ShiftDashboardViewModel()
    var body: some View {
        Form {
            Section {
                Button(action: export) { Label("Xuất bản sao lưu JSON", systemImage: "square.and.arrow.up") }.disabled(busy)
                Button { importing = true } label: { Label("Chọn tệp để khôi phục", systemImage: "square.and.arrow.down") }.disabled(busy)
            } footer: {
                Text("Tệp chứa công việc, ca và checklist; không xuất khóa API trong Cài đặt. Bạn tự chọn nơi lưu trong Tệp. Tệp không được mã hoá: nếu bật mục dưới đây, nhật ký sẽ nằm nguyên văn trong tệp.")
            }
            Section {
                Toggle("Kèm cảm xúc, nhật ký và lượt ghé vườn", isOn: $includeGarden).disabled(busy)
            }
            if busy { Section { ProgressView("Đang xử lý dữ liệu…") } }
            if let archive = preview {
                Section("Nội dung tệp đã kiểm tra") {
                    LabeledContent("Công việc", value: archive.tasks.count.formatted())
                    LabeledContent("Ca trực", value: archive.shifts.count.formatted())
                    LabeledContent("Mẫu checklist", value: archive.routines.count.formatted())
                    LabeledContent("Cảm xúc đã chọn", value: (archive.moods?.count ?? 0).formatted())
                    LabeledContent("Bài nhật ký", value: (archive.journal?.count ?? 0).formatted())
                    LabeledContent("Lượt ghé vườn", value: (archive.visits?.count ?? 0).formatted())
                    Text("Khôi phục bằng cách ghép theo ID, giữ bản mới hơn trên máy. Ca được thêm từ tệp sẽ chưa bắt đầu.")
                        .font(.subheadline).foregroundStyle(HopeTheme.secondary)
                    Button("Khôi phục từ tệp này", action: restore).disabled(busy)
                    Button("Hủy chọn tệp", role: .cancel) { preview = nil }.disabled(busy)
                }
            }
            if let message = message { Section { Text(message) } }
        }
        .navigationTitle("Sao lưu và khôi phục").navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: filename) { result in
            switch result {
            case .success: message = "Đã xuất bản sao lưu."
            case .failure(let error): message = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                busy = true; preview = nil
                Task {
                    defer { busy = false }
                    do { preview = try await Task.detached { try HopeBackup.readFile(url) }.value; message = nil }
                    catch { message = error.localizedDescription }
                }
            case .failure(let error): message = error.localizedDescription
            }
        }
        .alert("Hope", isPresented: $viewModel.showAlert) { Button("Đóng", role: .cancel) {} } message: { Text(viewModel.alertMessage ?? "") }
    }
    private var filename: String {
        let date = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return String(format: "Hope-%04d-%02d-%02d", date.year ?? 0, date.month ?? 0, date.day ?? 0)
    }
    private func export() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let archive = try HopeBackupService.snapshot(context: context, includeGarden: includeGarden)
                let data = try await Task.detached { try archive.encoded() }.value
                document = HopeBackupDocument(data: data); exporting = true; message = nil
            } catch { message = error.localizedDescription }
        }
    }
    private func restore() {
        guard let archive = preview else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try HopeBackupService.merge(archive, context: context)
            preview = nil
            message = "Đã thêm \(result.inserted), cập nhật \(result.updated), giữ nguyên \(result.kept) bản ghi."
            viewModel.refresh(context: context)
        } catch { message = error.localizedDescription }
    }
}

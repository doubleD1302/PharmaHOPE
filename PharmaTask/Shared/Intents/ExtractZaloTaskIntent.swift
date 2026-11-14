import AppIntents
import SwiftData
import ActivityKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct ExtractZaloTaskIntent: AppIntent {
    // Widget buttons have no input parameters; open the app to read the clipboard.
    public static var openAppWhenRun: Bool = true
    public static var title: LocalizedStringResource = "Bóc tách việc Zalo (Hope)"
    public static var description = IntentDescription("Tạo bản nháp từ tin nhắn hoặc ảnh Zalo để bạn duyệt trong Hope trước khi lưu công việc.")
    
    @Parameter(title: "Văn bản Zalo", description: "Đoạn tin nhắn sao chép từ Zalo")
    public var inputText: String?
    
    @Parameter(title: "Ảnh chụp màn hình", description: "Ảnh chụp màn hình ứng dụng Zalo", supportedTypeIdentifiers: ["public.image"])
    public var inputImage: IntentFile?
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var textToProcess = (inputText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        #if canImport(UIKit)
        if textToProcess.isEmpty, let fileData = inputImage?.data, let uiImage = UIImage(data: fileData) {
            do {
                textToProcess = try await VisionOCRService.shared.recognizeVietnameseText(from: uiImage)
            } catch {
                return .result(value: "Lỗi nhận dạng ảnh OCR: \(error.localizedDescription)")
            }
        }
        #endif

        #if canImport(UIKit)
        if textToProcess.isEmpty, inputImage == nil {
            textToProcess = UIPasteboard.general.string ?? ""
        }
        #endif
        
        guard !textToProcess.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .result(value: "Không tìm thấy nội dung văn bản hoặc ảnh để phân tích.")
        }
        
        do {
            let context = SharedModelContainer.shared.mainContext
            let activeShift = try ShiftTaskSync.activeShift(in: context)
            let extractedTasks = try await ZaloTaskExtractorService.shared.extractTasks(from: textToProcess)
            guard !extractedTasks.isEmpty else {
                return .result(value: "AI không tìm thấy đầu việc nào trong tin nhắn này.")
            }
            
            _ = try TaskImportService.stage(tasks: extractedTasks, source: textToProcess, label: "Phím tắt Zalo", shiftID: activeShift?.id, context: context)
            
            return .result(value: "Đã tạo \(extractedTasks.count) việc nháp. Mở Hope → Chờ duyệt AI để kiểm tra và lưu.")
        } catch {
            return .result(value: "Lỗi bóc tách AI: \(error.localizedDescription)")
        }
    }
}

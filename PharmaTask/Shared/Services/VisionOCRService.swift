import Foundation
import Vision
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

public final class VisionOCRService {
    public static let shared = VisionOCRService()
    
    private init() {}
    
    #if canImport(UIKit)
    /// Trích xuất văn bản từ ảnh chụp màn hình Zalo hoặc ảnh tài liệu
    public func recognizeVietnameseText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw NSError(
                domain: "VisionOCRService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Ảnh không hợp lệ (Không tìm thấy CGImage)."]
            )
        }
        let orientation: CGImagePropertyOrientation
        switch image.imageOrientation {
        case .up: orientation = .up
        case .down: orientation = .down
        case .left: orientation = .left
        case .right: orientation = .right
        case .upMirrored: orientation = .upMirrored
        case .downMirrored: orientation = .downMirrored
        case .leftMirrored: orientation = .leftMirrored
        case .rightMirrored: orientation = .rightMirrored
        @unknown default: orientation = .up
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            // Vision is synchronous work. Keep it off the main actor, and resume exactly once.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    let supported = try request.supportedRecognitionLanguages()
                    request.recognitionLanguages = ["vi-VN", "en-US"].filter { supported.contains($0) }
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                    try handler.perform([request])
                    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    #endif
}

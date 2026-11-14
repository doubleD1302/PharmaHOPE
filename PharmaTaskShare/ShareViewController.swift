import UIKit
import Social
import UniformTypeIdentifiers
import SwiftData

class ShareViewController: UIViewController {

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Hope\nĐang bóc tách tin nhắn Zalo…"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        return label
    }()

    private let spinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        return spinner
    }()

    private let containerBox: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 16
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.15
        view.layer.shadowRadius = 10
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        setupUI()
        processSharedContent()
    }

    private func setupUI() {
        view.addSubview(containerBox)
        containerBox.addSubview(spinner)
        containerBox.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            containerBox.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerBox.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerBox.widthAnchor.constraint(equalToConstant: 280),
            containerBox.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),

            spinner.centerXAnchor.constraint(equalTo: containerBox.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: containerBox.topAnchor, constant: 32),

            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: containerBox.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: containerBox.trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: containerBox.bottomAnchor, constant: -24)
        ])
    }

    private func processSharedContent() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) ??
                providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
            finishSharing(message: "Không tìm thấy nội dung chia sẻ.")
            return
        }

        // Trường hợp 1: Nhận Text chia sẻ từ Zalo
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] (data, error) in
                if let text = data as? String {
                    Task { @MainActor in
                        await self?.parseAndSaveTasks(from: text)
                    }
                } else {
                    self?.finishSharing(message: "Không đọc được văn bản.")
                }
            }
        }
        // Trường hợp 2: Nhận Ảnh chụp màn hình chia sẻ từ Zalo
        else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] (data, error) in
                var uiImage: UIImage?
                if let image = data as? UIImage {
                    uiImage = image
                } else if let imageData = data as? Data {
                    uiImage = UIImage(data: imageData)
                } else if let url = data as? URL, let fileData = try? Data(contentsOf: url) {
                    uiImage = UIImage(data: fileData)
                }

                guard let finalImage = uiImage else {
                    self?.finishSharing(message: "Không mở được ảnh.")
                    return
                }

                Task { @MainActor in
                    do {
                        let text = try await VisionOCRService.shared.recognizeVietnameseText(from: finalImage)
                        await self?.parseAndSaveTasks(from: text)
                    } catch {
                        self?.finishSharing(message: "Lỗi nhận dạng ảnh: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            finishSharing(message: "Định dạng không được hỗ trợ.")
        }
    }

    @MainActor
    private func parseAndSaveTasks(from text: String) async {
        do {
            let context = SharedModelContainer.shared.mainContext
            let activeShift = try ShiftTaskSync.activeShift(in: context)
            let tasks = try await ZaloTaskExtractorService.shared.extractTasks(from: text)
            guard !tasks.isEmpty else {
                finishSharing(message: "Không tìm thấy công việc trong nội dung chia sẻ.")
                return
            }

            _ = try TaskImportService.stage(tasks: tasks, source: text, label: "Menu Chia sẻ", shiftID: activeShift?.id, context: context)

            spinner.stopAnimating()
            statusLabel.text = "Đã tạo \(tasks.count) việc nháp.\nMở Hope để duyệt trước khi lưu."
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        } catch {
            finishSharing(message: "Lỗi AI: \(error.localizedDescription)")
        }
    }

    private func finishSharing(message: String) {
        DispatchQueue.main.async {
            self.spinner.stopAnimating()
            self.statusLabel.text = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        }
    }
}

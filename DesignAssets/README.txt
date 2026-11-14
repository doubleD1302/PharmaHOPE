HOPE / QUIET CARE
Thiết kế giao diện iOS - 14/11/2026

Thiết kế
- Xanh ngọc trầm, nền ngà, xanh lá non và màu mơ.
- Font hệ thống iOS, kiểu chữ ngữ nghĩa hỗ trợ Dynamic Type; không tải font ngoài.
- Thẻ bo 20-28 pt; khoảng cách theo thang 4/8/12/16/20/24/32 pt.
- Màu sáng/tối dùng token ngữ nghĩa; các cặp chữ chính được kiểm tra bằng validate_design.py.
- Chỉ dùng biểu tượng hệ thống cho thao tác; minh họa trang trí không tham gia VoiceOver.

Asset do dự án thiết kế
- hope-symbol.svg: nhận diện viên thuốc và chiếc lá; dùng làm logo và app icon.
- hope-shift.svg: minh họa ca trực.
- hope-inbox.svg: trạng thái chưa có công việc.
- tokens.json: màu, khoảng cách, góc bo và quy ước chữ; có thể tham khảo khi triển khai Android.
- iOS sử dụng PDF vector trong Shared/Resources/HopeAssets.xcassets.
- App icon PNG 1024x1024 có nền kín, không bo góc sẵn; iOS tự áp dụng mask.
- PDF/SVG gốc nhỏ, không cần ảnh nền lớn, font tải ngoài hoặc animation trang trí liên tục.

Thay đổi trong app native
- Hôm nay: thẻ ca, tiến độ, lối tắt bóc tách Zalo, việc ưu tiên, nhóm hoàn thành có thể thu gọn, ô thêm việc theo bàn phím.
- Lịch ca: chọn ngày, chuyển tuần, số liệu theo tuần, ca qua đêm, menu sửa/kết thúc, form nhập ca rộng hơn.
- Cài đặt: thông tin Hope, cấu hình Gemini, hướng dẫn thao tác, kiểu chữ và màu theo hệ thống.
- Widget/Live Activity: cùng nhận diện, màu và thứ tự công việc; cả hàng là vùng bấm hoàn thành.
- Share Extension: nhận diện Hope, chữ theo hệ thống và chiều cao theo nội dung.
- HopeDashboardPreviews.swift có bản sáng/tối, iPhone nhỏ, chữ trợ năng, lịch ca và cài đặt.

Tối ưu cấu trúc đã thực hiện
- Dashboard dùng Query lọc shiftId tại cơ sở dữ liệu, không tải toàn bộ công việc của các ca cũ.
- Lịch chỉ Query các ca trong tuần đang xem.
- TaskDashboardSnapshot phân nhóm một lần cho mỗi lần render, sắp xếp ổn định theo ưu tiên/giờ/ID.
- LazyVStack dựng hàng khi cần; nhóm đã hoàn thành mặc định thu gọn.
- ViewModel gộp yêu cầu làm mới liên tiếp và khởi tạo Live Activity tuần tự.
- Giảm các hiệu ứng nền/đổ bóng; chuyển động mở nhóm tôn trọng Reduce Motion.
- Chưa đo FPS, bộ nhớ hoặc thời gian trên thiết bị. Đây là thay đổi cấu trúc, chưa phải số liệu benchmark.

Tái tạo asset
1. Cài Python reportlab, svglib và Node @resvg/resvg-js vào môi trường công cụ riêng.
2. Đặt HOPE_RESVG_MODULE thành đường dẫn module @resvg/resvg-js nếu không cài trong module search path.
3. Chạy python DesignAssets/build_assets.py trong thư mục PharmaTask.
4. make_reference.py xuất bảng tham chiếu SVG/PNG vào ../review/redesign.
5. validate_design.py kiểm tra gói asset, cú pháp Swift bằng tree-sitter, đường dẫn XcodeGen và tương phản token.

Kiểm chứng
- Static grammar, gói vector, icon kín nền, tham chiếu resource và tương phản màu: đã chạy, xem validation.json.
- 8 XCTest có sẵn trong HopeTests; chưa chạy vì môi trường này không có Xcode/Apple SDK.
- Bảng design-reference.png là tài liệu mỹ thuật, KHÔNG phải screenshot của app native.
- Cần build scheme Hope trên Mac và kiểm tra native: iPhone SE/15, sáng/tối, cỡ chữ trợ năng, bàn phím, VoiceOver và widget.
- Không thay đổi giao diện desktop của bản web test trong đợt thiết kế này.

Nguồn hướng dẫn nền tảng đã đối chiếu
https://developer.apple.com/design/human-interface-guidelines/layout
https://developer.apple.com/design/human-interface-guidelines/accessibility
https://developer.apple.com/videos/play/wwdc2024/10074/
https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities

Trước đợt thay đổi này, mã native đã được sao lưu tại:
C:\Users\chann\.codex\tmp\hope-redesign-20261114-173504

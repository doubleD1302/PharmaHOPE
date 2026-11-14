# Hope

Ứng dụng quản lý công việc và ca trực nhà thuốc. Bản native sử dụng SwiftUI, SwiftData và yêu cầu iOS 17 trở lên. Thư mục `../PharmaTask_Simulator` là bản mô phỏng web, không kết nối trực tiếp Zalo và không gọi Gemini.

Giao diện native đã chuyển sang bộ thiết kế Hope / Quiet Care: nền ngà, xanh ngọc, màu sáng/tối, asset vector và font hệ thống. Xem `DesignAssets/README.txt` cùng `../review/redesign/design-reference.png`. Ảnh này là tài liệu thiết kế, chưa phải ảnh render từ app iOS. Các Native Preview nằm trong `HopeDashboardPreviews.swift`.

## Tính năng dùng cá nhân

- Nhấn giữ việc → Chỉnh sửa để đổi tên, ghi chú, ưu tiên, ngày/giờ hạn và nhắc trước hạn. Xóa có Hoàn tác; tab Tra cứu → bộ lọc Đã xóa cho phép khôi phục lại.
- Zalo/Shortcuts/Chia sẻ chỉ tạo bản nháp. Mở thẻ Chờ duyệt AI hoặc Cài đặt → Bản nháp AI chờ duyệt, so sánh tin nhắn gốc, sửa/bỏ chọn từng dòng rồi lưu. Để sau giữ lại chỉnh sửa của bản nháp.
- Cài đặt → Checklist theo loại ca để thêm, sửa, tắt, xóa và sắp thứ tự mẫu. Chọn loại checklist trong form ca. Mẫu được sao chép khi bắt đầu ca lần đầu; mỗi ca có trạng thái hoàn thành riêng.
- Nhắc trước hạn, đúng hạn và một lần sau 15 phút quá hạn. Nhấn giữ việc hoặc dùng nút trong thông báo để hoãn 10/15 phút. Việc trong ca ngừng được nhắc sau giờ kết thúc; việc chưa gắn ca nhắc độc lập. Lịch ưu tiên tối đa 60 sự kiện gần nhất, không lặp vô hạn.
- Tab Tra cứu tìm không phân biệt hoa/thường và dấu tiếng Việt, lọc trạng thái/ưu tiên/ca/khoảng ngày tạo việc. Việc quá hạn cập nhật theo phút khi xem.
- Cài đặt → Sao lưu và khôi phục xuất/nhập JSON qua ứng dụng Tệp. Xem nội dung trước khi nhập; ghép theo ID và giữ bản có `updatedAt` mới hơn, không xóa dữ liệu ngoài tệp. Ca được thêm từ bản sao lưu chưa tự bắt đầu. Cấu hình API Key không được xuất.

Định dạng sao lưu hiện tại: `app=Hope`, `schemaVersion=1`, ngày là số mili giây từ Unix epoch; có công việc, ca, mẫu checklist, bản nháp và tin nhắn nguồn. Giới hạn tệp 10 MB. Chưa có đồng bộ tài khoản qua mạng.

Không có chức năng chuyển/bàn giao việc giữa người dùng. Các trường cũ được giữ để tương thích dữ liệu đã lưu.

Đợt tính năng này có 25 XCTest trong `HopeTests` (17 bài mới), chưa chạy trên máy Windows. Kiểm tra tĩnh và các bước nghiệm thu iPhone nằm trong `../review/features/FEATURES.txt`. Cần kiểm tra nâng cấp cơ sở dữ liệu cũ trên bản sao trước khi dùng bản build với dữ liệu thật.

## Chạy và kiểm tra bản web

Mở `../PharmaTask_Simulator/index.html`, hoặc phục vụ thư mục đó qua HTTP cục bộ. Dữ liệu mẫu được lưu trong trình duyệt. Công việc dùng khóa theo ngày; dữ liệu v2 cũ không có ngày được chuyển vào tuần hiện tại một lần, giữ nguyên các khóa v2 để đối chiếu.

```powershell
node ../PharmaTask_Simulator/tests/regression.test.cjs
```

Kiểm tra trình duyệt bằng Playwright được cài ngoài mã nguồn:

```powershell
$env:HOPE_PLAYWRIGHT_MODULE = '<duong-dan-toi-playwright>'
$env:HOPE_ENGINE = 'webkit' # hoặc chromium, dùng Chrome đã cài
node ../PharmaTask_Simulator/tests/browser-smoke.cjs
```

WebKit trên Windows giúp kiểm tra bản web; kết quả không thay thế thử app native hoặc Safari trên iPhone.

## Build và kiểm tra iOS trên Mac

1. Cài Xcode có SDK iOS 17 trở lên và XcodeGen.
2. Chạy `xcodegen generate` trong thư mục này, rồi mở `Hope.xcodeproj`.
3. Chọn team ký ứng dụng; bật App Group `group.com.pharmatask.app` cho cả Hope, HopeWidgets và HopeShare. Giữ cùng App Group để cả ba đọc chung cơ sở dữ liệu.
4. Build scheme `Hope`; chạy `HopeTests` trên một iOS Simulator có sẵn. Ví dụ lệnh chỉ build:

```sh
xcodebuild -project Hope.xcodeproj -scheme Hope -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Kiểm thử trên iPhone: bắt đầu/kết thúc ca, ca qua đêm, cỡ chữ lớn, VoiceOver, nhập tin nhắn/ảnh qua Share, thông báo và Live Activity khi app đóng. Các mục này chưa được xác minh trên thiết bị trong lần rà soát Windows.

## Bóc tách Zalo

Nhập Gemini API Key cá nhân trong Cài đặt. Ứng dụng gửi nội dung bạn chọn tới Gemini để bóc tách; không đọc nhóm Zalo tự động. Khóa hiện được lưu bằng App Group UserDefaults. Cần chuyển sang Keychain trước khi phát hành rộng rãi.

Sao chép tin nhắn rồi chạy intent **Bóc tách việc Zalo (Hope)** hoặc nút **Gọn việc từ Zalo**. Shortcuts cũng nhận văn bản hoặc ảnh đầu vào. Có thể gán phím tắt vào Chạm vào mặt lưng trong Trợ năng iPhone.

## Android sau này

SwiftUI, SwiftData, WidgetKit và Shortcuts là phần dành riêng iOS. Bản web hiện chỉ là mô phỏng. Khi làm Android, cần dùng lại quy tắc phân ca, định dạng công việc và bộ màu/chữ, rồi xây giao diện và tích hợp thông báo Android tương ứng; không coi web preview là app Android hoàn chỉnh.

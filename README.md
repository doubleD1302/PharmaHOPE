# Hope

Ứng dụng quản lý công việc và ca trực nhà thuốc. Bản native sử dụng SwiftUI, SwiftData và yêu cầu iOS 17 trở lên. Thư mục `../PharmaTask_Simulator` là bản mô phỏng web, không gọi Gemini và chưa có tab Vườn; phần mô phỏng Zalo trong đó là bản cũ, bản native đã gỡ tính năng này.

Giao diện native đã chuyển sang bộ thiết kế Hope / Quiet Care: nền ngà, xanh ngọc, màu sáng/tối, asset vector và font hệ thống. Xem `DesignAssets/README.txt` cùng `../review/redesign/design-reference.png`. Ảnh này là tài liệu thiết kế, chưa phải ảnh render từ app iOS. Các Native Preview nằm trong `HopeDashboardPreviews.swift`.

## Tính năng dùng cá nhân

- Nhấn giữ việc → Chỉnh sửa để đổi tên, ghi chú, ưu tiên, ngày/giờ hạn và nhắc trước hạn. Xóa có Hoàn tác; tab Tra cứu → bộ lọc Đã xóa cho phép khôi phục lại.
- Tab **Vườn**: chọn cảm xúc, nghỉ 1-3 phút theo nhịp thở, viết nhật ký riêng, nghe âm thanh tạo trên máy (mưa, lá, suối, quán cà phê, hẹn giờ tắt), lời dành cho bạn, khép lại hôm nay, cây và Hope lớn dần theo số ngày bạn ghé nghỉ. Không có chỉ tiêu hay chuỗi ngày.
- Cài đặt → Checklist theo loại ca để thêm, sửa, tắt, xóa và sắp thứ tự mẫu. Chọn loại checklist trong form ca. Mẫu được sao chép khi bắt đầu ca lần đầu; mỗi ca có trạng thái hoàn thành riêng.
- Nhắc trước hạn, đúng hạn và một lần sau 15 phút quá hạn. Nhấn giữ việc hoặc dùng nút trong thông báo để hoãn 10/15 phút. Việc trong ca ngừng được nhắc sau giờ kết thúc; việc chưa gắn ca nhắc độc lập. Lịch ưu tiên tối đa 60 sự kiện gần nhất, không lặp vô hạn.
- Tab Tra cứu tìm không phân biệt hoa/thường và dấu tiếng Việt, lọc trạng thái/ưu tiên/ca/khoảng ngày tạo việc. Việc quá hạn cập nhật theo phút khi xem.
- Cài đặt → Sao lưu và khôi phục xuất/nhập JSON qua ứng dụng Tệp. Xem nội dung trước khi nhập; ghép theo ID và giữ bản có `updatedAt` mới hơn, không xóa dữ liệu ngoài tệp. Ca được thêm từ bản sao lưu chưa tự bắt đầu. Cấu hình API Key không được xuất.

Định dạng sao lưu hiện tại: `app=Hope`, `schemaVersion=1`, ngày là số mili giây từ Unix epoch; có công việc, ca, mẫu checklist và (tuỳ chọn, mặc định bật) cảm xúc, nhật ký, lượt ghé vườn; tệp cũ không có các khóa này vẫn đọc được, khóa `imports` của tệp cũ được bỏ qua. Tệp không mã hoá nên nhật ký nằm nguyên văn trong đó; có công tắc để không kèm. Giới hạn tệp 10 MB. Chưa có đồng bộ tài khoản qua mạng.

Không có chức năng chuyển/bàn giao việc giữa người dùng. Các trường cũ được giữ để tương thích dữ liệu đã lưu.

Các XCTest nằm trong `HopeTests`; workflow `.github/workflows/ios-tests.yml` chạy chúng trên macOS. Cần kiểm tra nâng cấp cơ sở dữ liệu cũ trên bản sao trước khi dùng bản build với dữ liệu thật (schema đã bỏ PendingTaskImport và thêm MoodCheckIn, JournalEntry, HealingVisit).

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
3. Chọn team ký ứng dụng; bật App Group `group.com.pharmatask.app` cho cả Hope và HopeWidgets. Giữ cùng App Group để cả hai đọc chung cơ sở dữ liệu.
4. Build scheme `Hope`; chạy `HopeTests` trên một iOS Simulator có sẵn. Ví dụ lệnh chỉ build:

```sh
xcodebuild -project Hope.xcodeproj -scheme Hope -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Kiểm thử trên iPhone: bắt đầu/kết thúc ca, ca qua đêm, cỡ chữ lớn, VoiceOver, thông báo và Live Activity khi app đóng. Các mục này chưa được xác minh trên thiết bị trong lần rà soát Windows.

## Vườn Hope và Gemini

Nhập Gemini API Key trong Cài đặt; khóa nằm trong Keychain. Tab Vườn chạy đầy đủ khi không có khóa (dùng nội dung viết sẵn). Có khóa thì Gemini viết: lời dành cho bạn, lời nhắc thả lỏng, câu mở đầu nhật ký, gợi ý ghi nhận cuối ngày, câu Hope nói khi chạm vào, thư tuần và (chỉ khi bạn đồng ý từng lần) lời đáp cho một bài nhật ký.

Model được chọn tự động trong `GeminiClient.swift`: ứng dụng hỏi API danh sách model, ưu tiên Flash-Lite mới nhất (rẻ nhất), rồi Flash mới nhất, rồi các bí danh `-latest`, rồi các bản cố định. Danh sách được lưu 24 giờ; model bị gỡ hoặc hết hạn mức thì thử bản kế tiếp. Chỉ gửi tham số tối thiểu để chạy được trên mọi đời Gemini. Mặc định chỉ gửi cảm xúc đã chọn, buổi trong ngày hoặc số lượng; không gửi tên việc hay nhật ký.

Âm thanh được tổng hợp ngay trên máy (`AmbientSoundEngine.swift`), nên không cần tải tệp và nghe được khi offline. Ảnh vườn nằm trong `PharmaTask/Resources/GardenAssets.xcassets`, lấy từ `DesignAssets/healing` và thu nhỏ.

## Android sau này

SwiftUI, SwiftData, WidgetKit và Shortcuts là phần dành riêng iOS. Bản web hiện chỉ là mô phỏng. Khi làm Android, cần dùng lại quy tắc phân ca, định dạng công việc và bộ màu/chữ, rồi xây giao diện và tích hợp thông báo Android tương ứng; không coi web preview là app Android hoàn chỉnh.

Nếu không mở được cơ sở dữ liệu (ví dụ nâng cấp schema lỗi), app không crash và không xoá gì: nó chạy bằng kho tạm trong bộ nhớ và hiện thông báo; tệp dữ liệu cũ giữ nguyên trên máy. Lời gọi Gemini có ngân sách thời gian tổng 15 giây, quá hạn thì dùng nội dung viết sẵn.

## Tab Hope, lịch và khóa Gemini dựng sẵn

- Tab Hope là một cảnh toàn màn hình với tranh vườn phủ kín, vuốt ngang giữa 5 trang: Vườn (thỏ, chim sẻ hoặc con vật bạn chọn cùng Hope, câu trích của vườn), Cảm xúc, Nghỉ và nghe (thở, âm thanh nền), Viết (nhật ký, khép ngày) và Trò chuyện. Không trang nào cuộn dọc khi đủ chỗ; màn hình quá thấp thì trang đó mới cuộn.
- Trò chuyện với Hope và các con vật dùng Gemini trong vai nhân vật; chỉ mở sau khi bạn đồng ý một lần, và quay về lời viết sẵn khi không có khóa hoặc lỗi. Lịch sử lưu trên máy (UserDefaults). Mỗi nhân vật có tính cách và cách nói riêng (Thỏ nhút nhát, nói nhỏ, hỏi một câu nhẹ; Chim sẻ tinh nghịch, hay "Chiếp!", rủ làm một việc nhỏ ngay; Hope điềm tĩnh như cây), cả khi dùng Gemini lẫn lời viết sẵn.
- Gemini được chờ tối đa 90 giây khi trò chuyện (lời gọi khác vẫn 15 giây). Trong lúc chờ hiện "đang suy nghĩ" (ba chấm nhấp nháy, nhãn đổi theo thời gian chờ, nút "Không đợi nữa" sau 12 giây), rồi câu trả lời hiện từng chữ với dòng "đang nhập…". Giao diện không gắn nhãn Gemini để nhập vai; lời giải thích về dữ liệu gửi đi vẫn nằm ở màn đồng ý và Cài đặt.
- Thỏ và Chim sẻ đi lại trên lối mòn lát đá của bức tranh nền, cả ngang lẫn lên xuống dọc theo đường mòn: nhảy từng bước ngắn, đứng nghỉ, quay đầu theo hướng đi, xa thì nhỏ hơn, có bóng đổ dưới chân. Lối mòn (`Features/Garden/GardenPath.swift`) được chiếu lên màn hình đúng như cách ảnh nền phủ kín, và chỉ lấy đoạn nằm trong khung nhìn nên màn hình rộng hay hẹp thú cũng không ra khỏi đá. Nút điều khiển nằm phía trên để phần dưới trang dành cho lối mòn. Giảm chuyển động hoặc chế độ nghỉ thì đứng yên; loài bay giữ nguyên chỗ.
- Câu trích đầu vườn là 24 câu có thật về nỗ lực, kiên trì, tự chủ, lạc quan và mạnh mẽ (Wikiquote, tục ngữ Việt Nam), có tác giả, đã đối chiếu nguyên văn; không dùng những câu hay bị gán nhầm. Lời Việt do mình dịch.
- Phiên thở có hiệu ứng nhiều lớp: quả cầu đổi màu theo pha (hít vào xanh bạc hà, giữ vàng nhạt, thở ra xanh trời), sóng lan ra khi thở ra và thu vào khi hít vào, bụi sáng trôi vào rồi toả ra, vòng tiến độ và số giây còn lại.
- Lịch ca là lịch tháng: chạm một ngày để xem, thêm, sửa hoặc đổi ngày của ca; menu của ca có "Lặp lại ca…" để tạo ca cho các thứ đã chọn trong nhiều tuần. Tra cứu có lịch chọn khoảng ngày tạo việc, chấm dưới ngày có việc.
- Khóa Gemini dựng sẵn: app đọc khóa từ Info.plist (`HopeGeminiKey = $(GEMINI_API_KEY)`), nên người dùng không phải cài đặt. Khóa riêng nhập trong Cài đặt vẫn được ưu tiên.
  - Máy có Xcode: tạo `Config/Secrets.xcconfig` (đã nằm trong `.gitignore`) với dòng `GEMINI_API_KEY = <khóa>`.
  - CI trên GitHub: thêm secret `GEMINI_API_KEY` ở Settings → Secrets and variables → Actions. Hai workflow đã truyền secret này cho xcodebuild; thiếu secret thì khóa để trống và app yêu cầu nhập khóa.
  - Khóa nằm trong gói app nên ai có file IPA đều trích được. Chỉ phát hành app cho chính bạn, và hãy giới hạn khóa trong Google Cloud (chỉ API Generative Language, đặt hạn mức).
- Bản web thử toàn app nằm ở `DesignAssets/healing/web-test` (xem `build.py`). Khóa mặc định của bản web đặt trong `config.local.json` cạnh trang (đã bị `.gitignore`).

## Chuông báo

- Nút chuông (huy hiệu số thông báo chưa đọc, đỏ khi có việc quá hạn) nằm trên thanh của Hôm nay và của tab Hope. Chạm để mở hộp thông báo: việc đang cần chú ý, nút Xong và Hoãn 10 hoặc 15 phút ngay trong hộp, công tắc âm chuông, nút thử chuông.
- Báo khi: việc sắp đến hạn (theo số phút nhắc trước), đến hạn, quá hạn (nằm đó đến khi xong hoặc hoãn), đến giờ nhắc lại sau khi hoãn; sắp đến ca (30 phút trước), đến giờ mà chưa bắt đầu ca; còn 30 và 15 phút hết ca khi còn việc, ca đã hết giờ mà còn việc; nhắc nghỉ một phút sau 14:00 nếu chưa ghé vườn; nhắc khép lại hôm nay sau 21:00. Bản web còn nhắc sao lưu.
- Chuông có giai điệu, mỗi loại một đoạn nhạc dài khoảng 5 đến 8 giây: nhẹ nhàng (sắp đến hạn, sắp đến ca), vui sáng rải hợp âm Đô trưởng (đến hạn), dồn dập trên thang La thứ (quá hạn, sắp hết ca). Trên iOS chuông được tổng hợp bằng mã thành tệp WAV (`Shared/Services/BellMelody.swift`), đặt vào Library/Sounds làm âm thông báo hệ thống, nên thông báo vẫn kêu bằng giai điệu khi app đóng; thông báo mới cho ca trực nằm trong `ShiftNotificationPlan`. Nhắc khép lại hôm nay lúc 21:00 mỗi ngày là tuỳ chọn trong hộp thông báo (mặc định tắt).

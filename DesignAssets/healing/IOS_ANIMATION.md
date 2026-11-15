> Cập nhật art: bộ vector khối hình bị người dùng loại về phong cách. Nguồn art pastel mới nằm trong `painted-rigs/` và chưa được ráp vào bộ chạy iOS. Các đoạn mô tả renderer vector bên dưới là bản thử kỹ thuật, không phải art bàn giao đã duyệt.

# Animation Hope cho iOS

Bản hiện tại dùng vector có khớp từ `rigged-creatures/`, 20 loài và mascot; không dùng chuỗi khung ảnh hoặc thu phóng toàn PNG. Mã native: `GardenRig.swift` và `GardenCreatureScene.swift`. Dữ liệu runtime tại `PharmaTask/Resources/CreatureRigs`.

Mở `rigged-creatures/preview.html` để xem bản thử. Xem README trong cùng thư mục để biết định dạng, kiểm tra và giới hạn. Các SVG/JSON là art mới với đường viền pastel đơn giản, chưa được người dùng duyệt.

Mục tiêu native 60 fps ở chế độ thường, 30 khi tiết kiệm pin. Tạm dừng khi rời tab/app/vùng nhìn; Reduce Motion/VoiceOver giữ tư thế tĩnh. Bản Debug có nút hiện FPS/node/draw count. Không giải mã hoặc tạo path vector trong từng frame. PNG cũ giữ nguyên và thư mục GardenCreatures được loại khỏi nguồn resource bundle trong project.yml.

Kiểm tra cấu trúc rig và bản xem trước Chromium đã qua. XCTest và build iOS chưa chạy vì thiếu Xcode/iOS SDK; chưa xác nhận 60 fps thực tế trên iPhone.

Trên Mac:
```sh
xcodegen generate
xcodebuild test -project Hope.xcodeproj -scheme Hope -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO
```

Trên iPhone: bật FPS trong bản Debug, đổi 20 loài, chuyển tab/app, cuộn ra ngoài rồi trở lại, thử chạm liên tục, Low Power Mode và Reduce Motion. Dùng Instruments kiểm tra Animation Hitches và bộ nhớ. Chỉ kết luận đạt 60 fps sau khi đo trên thiết bị.

## Thỏ vẽ tay (rig phiên bản 2)

Thỏ 046 đã chuyển sang ảnh màu nước từ `painted-rigs/atlases/046-rabbit-parts.png`. Các loài khác vẫn dùng rig vector phiên bản 1; bộ nạp chạy được cả hai.

- Công cụ: `painted-rigs/register_rabbit_parts.py` dò vị trí từng bộ phận so với ảnh tham chiếu v3 (kết quả: `rabbit-placements-raw.json`); `painted-rigs/build_painted_rabbit.py` xếp lại atlas chạy thật và ghi rig. Chạy `python build_painted_rabbit.py --preview` để xem các tư thế (đứng, nhảy, nháy mắt, nghỉ) mà không cần Xcode.
- Atlas chạy thật: `Resources/CreatureAtlases/CreatureAtlas046.png`, 1024×512 (khoảng 2 MB GPU thay vì 6 MB), mỗi bộ phận đã thu về đúng độ phân giải 3x để không nhấp nháy khi thu nhỏ.
- Rig: `Resources/CreatureRigs/CreatureRig046.json` có `atlas`, `atlasSize` và mỗi khớp có `sprite` (rect, anchor, size). 14 sprite cùng một texture, không `SKShapeNode`.
- Chuyển động: thở, đầu gật nhẹ, hai tai, đuôi, nháy mắt (lớp mí mắt hiện theo track `alpha`), và một cú nhảy mỗi 5 giây (track `blink` có `width`). Chế độ nghỉ ngơi chỉ còn thở, tai, đuôi và nháy mắt.
- Bản vector cũ của thỏ lưu ở `painted-rigs/rabbit-vector-backup/`. Lưu ý `build_creature_rigs.py` sẽ ghi đè rig 046 nếu chạy lại.
- Chưa kiểm tra: build iOS, XCTest, và 60 fps trên iPhone. Điểm xoay và độ chồng lớp do bộ dò đặt, đã xem bằng ảnh tĩnh nhưng chưa xem chuyển động thật trên máy.

## Chim cổ đỏ vẽ tay (rig phiên bản 2)

Chim 050 dùng cùng định dạng với thỏ. Công cụ chung cho các loài còn lại là `painted-rigs/painted_rig.py` (`fit`, `compare`, `preview`, `write`) và `make_rabbit_preview.py <id>` để tạo trang xem thử `preview-<id>.html`.

- Atlas robin là một bản vẽ cách điệu khác với ảnh gốc `expansion-100`, nên ảnh gốc chỉ dùng làm hình bóng để căn bố cục (gợi ý vị trí đọc từ lưới tọa độ trong `SPECS`), không so màu. Chỉ thân và đầu được tối ưu tự động; các bộ phận còn lại đặt theo gợi ý, mỏ gắn theo bbox của đầu.
- Mí mắt nhắm: chỉ cắt mảnh nhỏ quanh hàng mi, làm mờ viền rồi đặt đúng lên mắt (không dùng cả đầu, vì bản đầu nhắm mắt to hơn đầu thật).
- Chuyển động: thở, đầu gật, mổ, hót (hàm dưới mở), vẫy đuôi, giũ cánh, nháy mắt, nhảy nhỏ. Đuôi nằm dưới thân để khi cánh nhấc lên không lộ khe.
- Chưa kiểm tra: build iOS, XCTest, 60 fps trên iPhone.

## Nhóm chim đậu (051 chim sẻ, 052 chim xanh, 061 chim nhỏ)

Cùng định dạng và cùng cấu trúc bộ phận với chim cổ đỏ; cấu hình bằng `bird(...)` trong `painted_rig.py`.

- Ảnh gốc có cành cây và là bản vẽ khác atlas (061 còn khác cả màu), nên chỉ so hình bóng, trong vùng thân (`fit_region`), và chỉ thân + đầu được tối ưu. Chân đặt theo gợi ý; mỏ gắn theo bbox đầu. Cánh và đuôi gắn theo giải phẫu so với bbox thân (`BIRD_ANATOMY`, `BIRD_REST_ROTATION` trong `painted_rig.py`): cánh gập nằm trên sườn, mút cánh chỉ vượt hông một chút và chúc xuống; đuôi dài hơn cánh, gốc nằm sau thân nên ló ra dưới cánh và không bao giờ hở khe. Áp dụng cả cho chim cổ đỏ.
- Atlas được xoá alpha rất thấp (`ALPHA_FLOOR`) trước khi cắt: atlas 061 có bóng mờ hình chữ nhật quanh bộ phận.
- Mí mắt: mảnh nhỏ (đường kính 26% bề ngang đầu) quanh tâm tròng mắt (vùng tối dày nhất), viền mờ. Đường kẻ mắt đen của chim xanh không làm lệch tâm.
- Chưa có cành đậu: chân chim lơ lửng. Chưa kiểm tra build iOS, XCTest, 60 fps trên iPhone.

Sửa sau khi xem: atlas chim xanh (052) vẽ hai cánh ngoài ngược chiều (gốc bên trái, lông xoè sang phải) nên được lật ngang (`flip` trong `painted_rig.py`); chim nhỏ (061) có đầu bị cao và hở cổ nên gốc cổ của đầu được gắn vào thân bằng `head_anchor`.

## Chốt bộ vẽ tay: chỉ còn thỏ (046) và chim sẻ (051)

Chim cổ đỏ (050), chim xanh (052) và chim nhỏ (061) đã bỏ khỏi bộ vẽ tay: rig của ba con này được khôi phục về bản vector (từ `painted-rigs/vector-backup/`), atlas và trang xem thử riêng đã xóa. Cấu hình của chúng vẫn còn trong `SPECS` của `painted_rig.py` nếu sau này muốn làm lại. Trang "Phòng thử Hope" chỉ còn thỏ và chim sẻ; các loài còn lại vẫn là vector.

## Nhân vật người đầu tiên: Diệp (NPC001, rig id 101, bản thử; tên cũ Mai)

Atlas 5×5 trong `human-atlases-v1/`, công cụ `painted-rigs/painted_human.py` (`fit`, `compare`, `preview`, `write`). Rig ghi ra `CreatureRig101.json` + `CreatureAtlas101.png` (23 khớp, 22 sprite); chưa có trong danh sách `GardenCreature` của app nên chỉ xem được ở trang Phòng thử Hope.

- Bộ phận tràn qua đường lưới ô nên có mảnh của ô bên cạnh lọt vào: `keep_main` chỉ giữ thành phần liên thông lớn.
- Mí mắt và miệng mở là mảnh da: làm mờ viền hình elip (`feather`) để không lộ hình chữ nhật. Đầu đã có miệng cười và lông mày nên không dùng lớp miệng cười và lông mày.
- Tay, chân, giày gắn theo chuỗi (`chain`) vào bbox bộ phận cha; mép cắt tròn của chi dưới nằm dưới chi trên (z thấp hơn). Chân có `stretch` theo chiều dọc.
- Chuyển động: thở, người đung đưa nhẹ, đầu nghiêng, tóc, bình tưới lắc như quả lắc, nháy mắt, thỉnh thoảng nói (miệng mở) và vẫy tay trái (cánh tay nhấc lên, bàn tay xoè thay bàn tay thả).
- Hạn chế: atlas là bản vẽ khác ảnh toàn thân nên tỉ lệ chân thân chỉ gần đúng; hai khớp gối còn lộ mép nhỏ; chưa có khớp chân đi bộ; chưa kiểm tra build iOS, XCTest, 60 fps.

Cập nhật Diệp: `aim` xoay và co giãn cẳng tay phải để điểm cuối trùng cổ tay bàn tay cầm bình (góc nghỉ ghi vào `rot` trong placements, rig dùng làm `rotation` gốc của khớp; bàn tay nhận góc ngược lại để giữ hướng, vị trí khớp con được bù theo góc xoay của cha). Đỉnh đùi và miệng cẳng chân bỏ vành da và làm mờ để hai ống quần liền một khối.

## Quyết định: không đưa nhân vật người vào game; thêm cáo con (065)

Nhân vật người (Diệp/Mai) bị bỏ vì chuyển động quá khó. Rig 101 và atlas đã xóa khỏi `Resources`; `painted_human.py` và `human-atlases-v1/` giữ lại, chỉ là công cụ chưa dùng.

Cáo con (065) dựng bằng `painted_rig.py` theo giải phẫu nhìn nghiêng, không căn theo ảnh gốc (ảnh gốc là dáng 3/4 quay mặt, atlas lại vẽ nhìn nghiêng). Mỗi bộ phận gắn theo bbox của bộ phận cha (`anatomy`, phần tử thứ tư là bộ phận tham chiếu); vành tròn ở miệng ống của chân dưới được cắt và làm mờ (`trim_top`); chân trước nằm dưới thân để thân che vành đầu trên; chân sau dài ra để bốn bàn chân cùng đứng trên một mặt đất; gốc đuôi giấu sau thân. Bản vector cũ lưu ở `painted-rigs/vector-backup/`.

Cáo con (065), lần làm lại thứ ba: tỉ lệ từng bộ phận đo từ ảnh gốc (thân = 1; đầu 0.90, tai 0.46/0.39, đuôi 0.60, chân trước 0.40, đùi và cẳng chân sau 0.46/0.44) bằng `abs_k`, thay cho tỉ lệ bề ngang (làm đùi sau phình ~1.6 lần và chân trước quá to). Bốn chân tách hẳn: chân gần và chân xa lệch nhau để thấy đủ hai chân trước, hai chân sau. Chân trước nằm trên thân, đầu trên cắt vành và làm mờ nên hoà vào ngực. Đuôi vểnh nhờ góc nghỉ -0.95 rad. Cẳng chân kéo dãn dọc để bàn chân chạm đất (`ground_legs`). Khung bao (`bounds`) đo lại từ hình vẽ thật sau khi xoay.

## Bỏ cáo con, thêm nhím con (047)

Cáo con (065) bỏ khỏi bộ vẽ tay: atlas vẽ nhìn nghiêng còn ảnh gốc là dáng 3/4 quay mặt nên ráp mãi vẫn dị dạng; rig khôi phục về bản vector (`vector-backup/`). Cấu hình cáo vẫn còn trong `SPECS` của `painted_rig.py`.

Nhím con (047) ráp được tự nhiên vì ảnh gốc và atlas cùng dáng nhìn nghiêng quay phải: chỉ đầu, tai gần và đuôi tối ưu theo màu + hình bóng; thân, chân và tai xa đặt cố định theo ảnh gốc. Chân gần như bị lông bụng che hết nên mọi chân nằm sau thân (chỉ lộ phần dưới bụng), vành tròn ở miệng ống chân dưới được cắt và làm mờ, tai xa gắn theo bbox của đầu. Bài học: trước khi ráp, kiểm tra ảnh gốc và atlas có cùng góc nhìn không; nếu khác (như cáo), phải ráp theo giải phẫu và khó đẹp.

Nhím con (047), sửa chân: không giấu hết chân sau thân nữa. Thân, đầu, tai gần và đuôi nâng lên 50 px (`body_shift`) để chân có chỗ lộ đủ hai đoạn; đoạn trên (đùi sau, cánh tay trước) nằm trên thân với mép trên làm mờ (`trim_top`) để hoà vào lông bụng; đoạn dưới gắn vào đáy đoạn trên bằng `anatomy` và kéo dãn chiều dọc tới mặt đất tuyệt đối (`ground_legs.ground_y`).

Nhím con (047), chân lần ba: thử tự vẽ chi bằng mã (`limb_synth.py`: ống thon, kết cấu lông lấy từ atlas, bàn chân cắt từ atlas) cho kết quả xấu (sọc, xỉn màu, đầu vuông) vì kết cấu lông trong atlas chỉ khoảng 100 px, phóng ra không đủ nét. Không dùng. Bản cuối vẫn dùng mảnh chi của atlas: đoạn trên cắt vành đầu trên, nằm sau đoạn dưới; đoạn dưới (cắt vành, mờ nhẹ ở mép trên) nằm trên và che đáy cắt của đoạn trên; không còn đoạn mờ làm ghost ở khớp gối.

Nhím con (047), chân lần bốn: theo yêu cầu, mỗi chân là MỘT mảnh liền (mảnh cẳng chân + bàn chân của atlas, đầu trên nằm sau thân), bỏ hẳn các mảnh đoạn trên (đùi sau, cánh tay trước) khỏi rig. Đầu trên chân đặt thấp hơn mép bụng để không lộ mép cắt; chiều dọc kéo dãn tới mặt đất. Rig còn 11 khớp.

## Bỏ nhím, thêm vịt con (060)

Nhím (047) bỏ khỏi bộ vẽ tay sau nhiều lần sửa chân: các mảnh chi của atlas nhím không ghép được thành chân tự nhiên (đoạn trên và dưới lệch nhau, vành cắt lộ, thử tự vẽ chi bằng mã cũng không đủ nét). Rig về bản vector (`vector-backup/`); cấu hình vẫn còn trong `SPECS`.

Vịt con (060) có cùng bố cục bộ phận với chim sẻ (cùng hàm `bird()`), ảnh gốc và atlas cùng dáng nhìn nghiêng quay phải, không có cành cây nên tối ưu thân + đầu theo màu và hình bóng, các phần còn lại theo gợi ý; dùng atlas `060-duckling-parts-clean-v2.png`; mỏ gắn theo bbox đầu nhưng thấp và nhỏ hơn chim (mỏ vịt dẹt).

Bài học chọn con tiếp theo: con nào có ảnh gốc và atlas cùng góc nhìn, bố cục bộ phận đơn giản và ít chi hai đoạn thì ráp tốt (thỏ, chim sẻ, vịt); dáng khác góc nhìn (cáo) hoặc chi nhiều đoạn bị che (nhím) thì khó.

## Dừng thêm animation, bỏ vịt con (060)

Người dùng quyết định chỉ giữ thỏ (046) và chim sẻ (051) dạng vẽ tay. Vịt con (060) trả về rig vector (`painted-rigs/vector-backup/CreatureRig060.json`), atlas 060 bị xoá khỏi Resources, bài kiểm thử chỉ còn ["046", "051"]. Spec 060 trong `painted_rig.py` vẫn được giữ để dùng lại nếu cần.

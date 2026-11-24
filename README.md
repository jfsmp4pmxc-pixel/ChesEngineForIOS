# Chess Engine for iOS

Ứng dụng cờ vua native (SwiftUI, iOS 15+) có lưu ván, xem lại/phân tích kiểu chess.com bằng Stockfish và hỗ trợ nhập bot ngoài viết bằng Python (`.py`).

## Tính năng

- **Chơi cờ**: hai người, chơi với Stockfish (8 mức độ, từ Mới học đến Tối đa) hoặc với bot Python. Đủ luật: nhập thành, bắt tốt qua đường, phong cấp, chiếu hết, hòa cờ, lặp thế 3 lần, luật 50 nước.
- **Lưu ván**: tự lưu khi ván kết thúc (hoặc bấm Lưu), lưu trong `Documents/Games` (xem được trong app Tệp). Nhập/xuất PGN (dán văn bản hoặc chọn file `.pgn`).
- **Hiệu ứng và đi trước**: quân trượt mượt từ ô đi sang ô đến (cả xe khi nhập thành, và khi đi lại); bật/tắt ở Cài đặt. Khi đối thủ đang nghĩ, bạn có thể đi trước (premove) không giới hạn số nước; mỗi nước được đi sau khi đối thủ đáp, nếu không còn hợp lệ thì cả hàng đợi bị hủy.
- **Xem lại và phân tích**: Stockfish đánh giá từng thế cờ, phân loại nước đi giống chess.com: Thiên tài, Tuyệt vời, Tốt nhất, Xuất sắc, Tốt, Khai cuộc, Thiếu chính xác, Sai lầm, Sai lầm nghiêm trọng, Bắt buộc. Biểu tượng phân loại hiện ở góc trên bên phải ô cờ của quân vừa đi. Nước thiên tài là nước hy sinh quân thực sự mà vẫn giữ được (hoặc cải thiện) thế cờ; với các nước hy sinh nghi ngờ, app tìm sâu thêm một lần trước khi kết luận. Có thanh đánh giá, biểu đồ đánh giá, mũi tên nước tốt nhất, độ chính xác từng bên và tên khai cuộc.
- **Bot ngoài (.py)**: nhập file Python ở tab *Bot*. Xem phần dưới.
- **Hồ sơ engine**: *Lite* (độ sâu 12, 1 luồng, hash 16 MB) hoặc *Full* (độ sâu 18, nhiều luồng, hash 64 MB) trong tab *Cài đặt*.
- **Giao diện tiếng Việt** và bộ quân cờ, biểu tượng phân loại vẽ vector riêng (xem `scripts/gen_assets.py`; chạy lại script để tạo lại `App/Resources/Assets.xcassets`).

### Lưu ý về phiên bản Stockfish

Bản dựng dùng **Stockfish 19** (tag `sf_19`) với một network NNUE duy nhất tải từ data.stockfishchess.org. Lite/Full là hai hồ sơ cấu hình tìm kiếm (độ sâu, luồng, hash), không phải hai network khác nhau.

Độ chính xác và cách chấm nước đi mô phỏng ý tưởng của chess.com (mất bao nhiêu xác suất thắng so với nước tốt nhất) nhưng **không giống hệt** thuật toán độc quyền của họ.

## Viết bot Python

Tạo file `.py` có hàm `get_move(fen)` trả về nước đi dạng UCI (`e2e4`, `e7e8q`) hoặc SAN (`Nf3`):

```python
import random

def get_move(fen):
    # Viết logic của bạn ở đây (chỉ dùng thư viện chuẩn của Python)
    return "e2e4"
```

Nhập file ở tab **Bots**, bấm **Test** để thử, rồi chọn *Python bot* khi tạo ván mới. iOS không cho chạy tiến trình con nên Python được nhúng trực tiếp vào app (CPython 3.13 từ [beeware/Python-Apple-support](https://github.com/beeware/Python-Apple-support)); không có pip, chỉ dùng được thư viện chuẩn. Một bot chạy vô hạn sẽ làm treo hàng đợi Python cho đến khi nó trả về.

## Build file .ipa không ký bằng GitHub Actions

Workflow: [`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml), chạy trên runner `macos-latest`, kích hoạt khi push, pull request, tag `v*` hoặc chạy tay (*Actions → Build unsigned IPA → Run workflow*).

Các bước:

1. Cài XcodeGen và tạo `ChessEngine.xcodeproj` từ [`project.yml`](project.yml).
2. [`scripts/build_stockfish.sh`](scripts/build_stockfish.sh): tải Stockfish `sf_19`, biên dịch thành `libstockfish.a` cho iOS arm64 cùng cầu nối UCI trong [`bridge/`](bridge), tải file network `.nnue` và kiểm tra checksum.
3. [`scripts/fetch_python.sh`](scripts/fetch_python.sh) (không bắt buộc): tải runtime Python cho iOS. Nếu bước này lỗi thì app vẫn build, chỉ mất tính năng bot Python.
4. `xcodebuild` với `CODE_SIGNING_ALLOWED=NO` (không ký).
5. [`scripts/package_ipa.sh`](scripts/package_ipa.sh): gói `.app` vào `Payload/`, nhúng Python (chuyển các module `.so` thành framework như CPython yêu cầu trên iOS) và nén thành `ChessEngine-unsigned.ipa`.
6. Upload artifact `ChessEngine-unsigned-ipa`; với tag `v*` file còn được đính kèm vào GitHub Release.

File `.ipa` **chưa ký**: cần ký lại bằng công cụ của bạn (Sideloadly, AltStore, TrollStore, `zsign`, v.v.) trước khi cài lên máy. Mọi file bên trong (kể cả `Frameworks/*.framework`) cần được ký lại.

Chỉ build cho thiết bị thật (arm64); chưa có bản cho iOS Simulator.

## Cấu trúc

| Thư mục | Nội dung |
| --- | --- |
| `App/Chess` | Luật cờ, FEN, SAN, PGN, ván đấu |
| `App/Engine` | Cầu nối Stockfish (UCI), runtime Python cho bot |
| `App/Analysis` | Chấm nước đi, độ chính xác, sách khai cuộc |
| `App/Storage` | Lưu ván, quản lý bot |
| `App/UI` | Giao diện SwiftUI |
| `bridge` | Mã C++ chạy Stockfish trong tiến trình app |
| `scripts` | Script build cho CI |

## Giấy phép

Stockfish được phát hành theo GPLv3 và được liên kết trực tiếp vào app, vì vậy bản phân phối của ứng dụng này cũng phải tuân theo GPLv3 (kèm mã nguồn).

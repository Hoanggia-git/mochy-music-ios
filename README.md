# Mochy Music iOS

Phiên bản SwiftUI thuần cho iOS (iOS 16.0+) được chuyển thể từ dự án Android [Mochy-Music](https://github.com/realidkroo/Mochy-Music), mang phong cách giao diện **Catppuccin Mocha** cùng hiệu ứng kính mờ hiện đại.

## Tính năng chính

- **Phát nhạc từ YouTube Music (InnerTube API)**: Tìm kiếm bài hát, video, album, nghệ sĩ, playlist; khám phá Bảng xếp hạng, Nhạc mới phát hành, Tâm trạng & Thể loại.
- **Trình phát âm thanh nền chất lượng cao (`AVFoundation`)**: Hỗ trợ màn hình khóa, Control Center, AirPlay, hàng chờ thông minh, trộn bài, lặp lại, chuyển bài mượt (Crossfade / Crossmix) và chuẩn hóa âm lượng.
- **Nhiều phong cách trình phát**: Flagship, iPod, Bedside và Compact.
- **Lời bài hát đồng bộ (Synced Lyrics)**: Hỗ trợ đa nguồn (LrcLib, KuGou, Better Lyrics, SimpMusic, YouLy+, Paxsenix, Genius, Musixmatch...) kèm hiển thị bản dịch.
- **Bộ chỉnh âm 10 băng tần (Equalizer)**: Tùy chỉnh tần số 32Hz–16kHz, hiệu ứng Reverb, tăng âm trầm (Bass Boost) và nhiều preset dựng sẵn.
- **Thư viện cá nhân & Ngoại tuyến**: Yêu thích, lịch sử nghe nhạc, thống kê Recap, tải nhạc nghe offline và quét tệp nhạc cục bộ trên thiết bị.
- **Nhập playlist & Đồng bộ**: Hỗ trợ nhập từ Spotify, Apple Music, TIDAL, tệp CSV; hỗ trợ scrobble Last.fm và sao lưu/khôi phục dữ liệu JSON.
- **Nhận diện nhạc (ShazamKit)** và hình nền động (Canvas).

## Cách build tự động bằng GitHub Actions

Dự án sử dụng **XcodeGen** (`project.yml`) và không phụ thuộc gói SPM bên ngoài, giúp build IPA không cần ký (unsigned) ngay trên runner `macos-latest`:

1. Đẩy mã nguồn lên nhánh `main` hoặc `master` trên GitHub (hoặc mở tab **Actions** → **Build Unsigned IPA** → **Run workflow**).
2. Workflow [.github/workflows/build-ipa.yml](.github/workflows/build-ipa.yml) sẽ tự động:
   - Cài đặt `xcodegen` qua Homebrew.
   - Chạy `xcodegen generate` để tạo `MochyMusic.xcodeproj`.
   - Build bản Release không ký (`CODE_SIGNING_ALLOWED=NO`).
   - Đóng gói thư mục `Payload/MochyMusic.app` thành `MochyMusic-unsigned.ipa`.
3. Vào chi tiết lần chạy workflow hoàn tất, tải về artifact **`MochyMusic-unsigned-ipa`** và giải nén để lấy tệp `MochyMusic-unsigned.ipa`.

## Cách cài đặt IPA lên iPhone / iPad

### Cách 1: Dùng AltStore
1. Cài đặt **AltServer** trên Windows/macOS và **AltStore** trên iPhone/iPad (kết nối cùng Wi-Fi hoặc cáp USB).
2. Mở AltStore trên iPhone → chọn tab **My Apps** → nhấn nút **`+`** ở góc trên bên trái.
3. Chọn tệp `MochyMusic-unsigned.ipa`.
4. Nhập Apple ID nếu được yêu cầu để AltStore tự động ký và cài đặt ứng dụng.

### Cách 2: Dùng Sideloadly
1. Tải và mở **Sideloadly** trên máy tính, kết nối iPhone/iPad qua cáp USB.
2. Kéo thả tệp `MochyMusic-unsigned.ipa` vào cửa sổ Sideloadly.
3. Nhập **Apple ID** của bạn và nhấn **Start**.
4. Sau khi cài xong, vào **Cài đặt → Cài đặt chung → Quản lý VPN & Thiết bị** trên iPhone để **Tin cậy** chứng chỉ nhà phát triển trước khi mở ứng dụng.

### Cách 3: Dùng TrollStore (iOS hỗ trợ)
- Mở trực tiếp tệp `MochyMusic-unsigned.ipa` bằng **TrollStore** và nhấn **Install** để cài vĩnh viễn không cần gia hạn chứng chỉ.

# Mochy Music iOS (MVP)

Phiên bản iOS (SwiftUI) rút gọn lấy cảm hứng từ [realidkroo/Mochy-Music](https://github.com/realidkroo/Mochy-Music), được thiết kế để build tự động thành file `.ipa` (unsigned) qua **GitHub Actions (`macos-latest`)** mà không cần máy Mac.

## Tính năng có sẵn
- **Explore & Search**: Tìm kiếm bài hát và lấy feed nhạc từ YouTube Music (InnerTube).
- **Phát nhạc nền**: Hỗ trợ phát khi tắt màn hình và điều khiển ngoài Lock Screen / Control Center (`AVFoundation` + `MediaPlayer`).
- **Autoplay / Up Next**: Tự động nạp danh sách bài hát liên quan khi phát đơn lẻ.
- **Synced Lyrics**: Hiển thị lời bài hát đồng bộ theo thời gian từ [LRCLIB](https://lrclib.net/) (chạm vào dòng lời để tua tới đoạn đó).
- **Library & Offline**: Yêu thích, lịch sử nghe gần đây, tạo playlist cá nhân, và tải nhạc `.m4a` về máy để nghe offline.

---

## Cách tạo file `.ipa` trên GitHub (không cần máy Mac)

1. Tạo một repository mới trên GitHub (ví dụ `mochy-music-ios`).
2. Đẩy toàn bộ thư mục này lên nhánh `main` của repository đó:
   ```bash
   git init
   git add .
   git commit -m "Initial Mochy Music iOS MVP"
   git branch -M main
   git remote add origin https://github.com/<TEN_USER_CUA_BAN>/<TEN_REPO>.git
   git push -u origin main
   ```
3. Mở repo trên trình duyệt -> vào tab **Actions** -> chọn workflow **Build Unsigned iOS IPA** (tự động chạy khi push, hoặc bấm **Run workflow**).
4. Sau khi chạy xong (khoảng 2–4 phút), bấm vào lần chạy đó -> kéo xuống mục **Artifacts** -> tải **`MochyMusic-unsigned-ipa`** về máy (giải nén sẽ được `MochyMusic-unsigned.ipa`).
5. Dùng **Sideloadly**, **AltStore**, hoặc **SideStore** trên Windows/iPhone để ký bằng Apple ID của bạn và cài file `.ipa` lên iPhone.

---

## Giấy phép & Credits
- Dự án tham khảo giao thức từ [realidkroo/Mochy-Music](https://github.com/realidkroo/Mochy-Music) (GPL-3.0).
- Lời bài hát đồng bộ sử dụng API miễn phí từ [LRCLIB](https://lrclib.net/).

# Hướng dẫn phát triển và phát hành AuraTube

Tài liệu này dành cho người tiếp quản dự án: cách build, thử, đưa thay đổi vào `main` và phát hành bản mới cho người dùng. Làm theo đúng thứ tự trong mục 4 và 5 là đủ để ra một bản an toàn.

## 1. Dự án gồm những gì

| Đường dẫn | Nội dung |
|---|---|
| `AuraTubeNative/` | App macOS chính (Swift, SwiftUI + AppKit). Đây là bản được phát hành. |
| `AuraTubeNative/Sources/Player/` | Player, PiP, đồng hồ phát. |
| `AuraTubeNative/Sources/Services/` | Gọi YouTube (InnerTube, yt-dlp), gợi ý, cập nhật, tải xuống. |
| `AuraTubeNative/Sources/Views/` | Giao diện. |
| `AuraTubeNative/bundle.sh` | Đóng binary thành `/Applications/AuraTube.app`. |
| `AuraTubeNative/package_dmg.sh` | Build + đóng gói DMG và ZIP để phát hành. |
| `version.json` | Số phiên bản, ghi chú phát hành, link tải. App đọc file này để báo cập nhật. |
| `main.js`, `server.js`, `public/`, `src/` | Bản web/Electron cũ. Không nằm trong quy trình phát hành dưới đây. |

Các file `*.dmg`, `*.zip` ở thư mục gốc là sản phẩm đóng gói, đã bị `.gitignore` bỏ qua.

## 2. Chuẩn bị máy

Cần có:

- macOS 13 trở lên và **Xcode đầy đủ** (không chỉ Command Line Tools).
- `gh` (GitHub CLI) đã đăng nhập tài khoản có quyền ghi vào `tung68nt/AuraTube`.
- `yt-dlp` (app dùng làm phương án dự phòng khi tìm kiếm và để tải video).

```bash
brew install gh yt-dlp
```

```bash
gh auth login
```

## 3. Build và chạy thử trên máy

### Build

Phải chỉ định toolchain của Xcode. Nếu chạy `swift build` trần mà máy đang trỏ vào Command Line Tools, build sẽ lỗi `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`.

```bash
cd AuraTubeNative && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release
```

Lần build đầy đủ mất khoảng 2 phút.

### Cài vào /Applications

Lệnh này **tắt AuraTube đang chạy**, xoá `/Applications/AuraTube.app` cũ và cài bản vừa build. Số phiên bản lấy từ `version.json`.

```bash
./AuraTubeNative/bundle.sh
```

### Khi app crash

Báo cáo crash nằm ở `~/Library/Logs/DiagnosticReports/AuraTube-*.ips`. Phần cần đọc là `lastExceptionBacktrace` (nếu có) và luồng có `triggered: true`.

## 4. Quy trình đưa thay đổi vào `main`

**Không commit thẳng lên `main`.** App của người dùng đọc `version.json` trên `main` để báo cập nhật, nên mọi thứ vào `main` phải được thử trước. Bản 2.1.2 từng được đẩy thẳng khi chưa thử tay và mang lỗi PiP đen đến người dùng.

1. Tạo nhánh từ `main`:

   ```bash
   git checkout main && git pull && git checkout -b fix/ten-ngan-gon
   ```

2. Sửa code, build, cài bằng `bundle.sh`.
3. Thử tay theo danh sách ở mục 6.
4. Commit và đẩy nhánh. Tiêu đề commit theo kiểu đang dùng trong lịch sử: `feat(player): ...`, `fix(pip): ...`.

   ```bash
   git push -u origin fix/ten-ngan-gon
   ```

5. Mở pull request vào `main`. Trong mô tả ghi rõ: đổi gì, vì sao, và **đã thử tay những gì, chưa thử gì**.

   ```bash
   gh pr create --base main
   ```

6. Thử xong và ổn thì merge. Repo hiện không có CI, nên bước thử tay ở mục 6 là lớp kiểm tra duy nhất.

   ```bash
   gh pr merge --squash --delete-branch
   ```

PR chỉ chứa thay đổi code. Việc tăng số phiên bản làm ở bước phát hành (mục 5), sau khi merge.

## 5. Phát hành bản mới

Làm trên `main` sau khi PR đã merge. Thứ tự dưới đây quan trọng: link tải phải tồn tại trước hoặc ngay khi `version.json` mới lên `main`, nếu không người dùng bấm cập nhật sẽ gặp link hỏng.

1. Lấy `main` mới nhất:

   ```bash
   git checkout main && git pull
   ```

2. Sửa `version.json`:
   - `version`: tăng số (ví dụ `2.1.2` → `2.1.3`).
   - `build`: tăng 1.
   - `title`: `AuraTube vX.Y.Z (tóm tắt ngắn)`.
   - `releaseNotes`: mỗi ý một dòng bắt đầu bằng `• `, viết cho người dùng đọc, nối bằng `\n`.
   - `downloadUrl`: đổi cả hai chỗ có số phiên bản trong đường dẫn.
   - `publishedAt`: ngày phát hành.

3. Đóng gói. Script này tự build, chạy `bundle.sh` (nên cũng tắt app đang chạy), rồi tạo 4 file ở thư mục gốc: `AuraTube-vX.Y.Z.dmg`, `AuraTube-vX.Y.Z.zip`, `AuraTube.dmg`, `AuraTube.zip`.

   ```bash
   bash AuraTubeNative/package_dmg.sh
   ```

   Dòng cuối phải có `checksum ... is VALID`.

4. Mở app vừa cài, kiểm tra nó chạy và đúng số phiên bản:

   ```bash
   defaults read /Applications/AuraTube.app/Contents/Info.plist CFBundleShortVersionString
   ```

5. Commit `version.json` và đẩy lên `main` (đây là ngoại lệ duy nhất được đẩy thẳng, vì chỉ đổi số phiên bản):

   ```bash
   git add version.json && git commit -m "chore(release): vX.Y.Z" && git push origin main
   ```

6. Tạo bản phát hành trên GitHub ngay sau đó, kèm đủ 4 file. Tiêu đề và ghi chú lấy đúng từ `title` và `releaseNotes` trong `version.json`.

   ```bash
   gh release create vX.Y.Z AuraTube-vX.Y.Z.dmg AuraTube-vX.Y.Z.zip AuraTube.dmg AuraTube.zip --target main --title "TIÊU ĐỀ" --notes "GHI CHÚ"
   ```

7. Kiểm tra link tải trả về 200:

   ```bash
   curl -sIL -o /dev/null -w "%{http_code}\n" https://github.com/tung68nt/AuraTube/releases/download/vX.Y.Z/AuraTube-vX.Y.Z.dmg
   ```

Từ lúc bước 5 xong, người dùng bản cũ sẽ thấy thông báo cập nhật. Vì vậy đừng để khoảng trống dài giữa bước 5 và bước 6.

### Nếu bản vừa phát hành bị lỗi nặng

Sửa `version.json` trên `main` về số phiên bản và `downloadUrl` của bản tốt gần nhất rồi đẩy lên. Người dùng chưa cập nhật sẽ không được mời lên bản lỗi nữa. Sau đó sửa lỗi theo mục 4 và phát hành bản vá với số phiên bản mới.

## 6. Danh sách thử tay trước khi merge

Không có test tự động. Tối thiểu phải thử:

**Khởi động**
- App mở lên, không thoát, trang chủ có video.

**Phát video**
- Bấm một video: tự phát, có tiếng.
- Tua, tạm dừng bằng phím Space, đổi tốc độ.
- Mở menu chất lượng: chế độ Auto hiển thị độ phân giải; chọn tay một mức thì giữ đúng mức đó.
- Cuộn danh sách video liên quan và bình luận trong lúc video đang phát: không giật.
- Không có vạch đen ở hai mép video.

**PiP**
- Bật PiP: video hiện ngay (không đen), đúng kích thước đã lưu.
- Kéo cửa sổ PiP: di chuyển được, không bị bật về app chính.
- Nút tai nghe: PiP ẩn đi, tiếng vẫn phát; bấm nút PiP trên menu bar thì hiện lại.
- Đưa video về cửa sổ chính: video tiếp tục phát ở player chính.
- Chuyển sang app khác rồi quay lại (nếu bật tự động PiP).

**Toàn màn hình và Shorts**
- Vào/thoát toàn màn hình, video không đen.
- Mở một Short: phát dọc, lặp lại khi hết.

**Trang chủ và gợi ý**
- Tab Tất cả, Thịnh hành, Đang theo dõi đều tải được.
- Cuộn tới cuối trang chủ và cuối danh sách liên quan: tự tải thêm.
- Tìm kiếm trả về kết quả.

## 7. Những điểm dễ gây lỗi trong code

Đây là các bẫy đã từng gây lỗi thật. Đọc trước khi sửa player hoặc PiP.

### Một web view dùng chung cho nhiều chỗ hiển thị

Player là một `WKWebView` duy nhất (`MainWebPlayerPool.shared.webView`) nhúng iframe YouTube. Trang xem, lớp toàn màn hình và cửa sổ PiP đều có `NativePlayerView` riêng nhưng cùng muốn giữ web view đó. Quy tắc nằm ở `WebPlayerHostingView` trong `NativePlayerView.swift`: khi PiP đang bật thì host trong cửa sổ PiP giữ web view, ngược lại host trong cửa sổ chính giữ. Nếu thêm chỗ hiển thị player mới, phải tuân theo quy tắc này, nếu không video sẽ đen.

### Không ghi vào `@Published` trong vòng đồng bộ thời gian

Web view gửi vị trí phát về `PlayerManager.updatePlaybackSync` khoảng 10 lần/giây. Hơn 20 view đang theo dõi `PlayerManager`, nên mỗi lần ghi vào một thuộc tính `@Published` trong đường này sẽ làm tất cả vẽ lại. Thời gian hiện tại vì thế nằm ở `PlaybackClock` riêng. Khi thêm state mới: chỉ gán khi giá trị thật sự đổi, hoặc lấy mẫu thưa (xem `recordPlaybackProgress`).

### Khoá riêng tư của WebKit

Cấu hình web view đặt nhiều khoá không công khai qua KVC. Luôn dùng `setValueIfSupported(_:forKey:)` thay cho `setValue(_:forKey:)`: khoá nào WebKit không còn hỗ trợ sẽ ném `NSUnknownKeyException` và app thoát ngay khi tạo player.

### Script nhúng vào iframe

`NativePlayerView.cleanScriptSource` là JavaScript nằm trong chuỗi Swift, chạy trong mọi frame (kể cả iframe YouTube). Trình biên dịch Swift không kiểm tra cú pháp của nó; một lỗi JS làm cả script ngừng chạy mà build vẫn thành công. Sau khi sửa, chép phần script ra file `.js` và chạy `node --check`.

Script này gồm: ẩn giao diện gốc của YouTube, đồng bộ thời gian về app, báo độ phân giải, và bộ điều khiển chất lượng ở chế độ Auto (hạ mức trần khi video khựng lặp lại hoặc rớt khung hình, nâng lại khi ổn định). Việc chọn độ phân giải từng đoạn vẫn do YouTube làm; app chỉ đặt mức trần qua `setPlaybackQualityRange`.

### Cửa sổ PiP

`PiPPanel` là panel không kích hoạt app (`.nonactivatingPanel`). Nếu bỏ cờ này, bấm vào PiP sẽ đưa focus về cửa sổ chính và tính năng "Tắt PiP khi bấm lại app chính" sẽ kéo video về ngay. Chế độ chỉ nghe (nút tai nghe) làm panel gần trong suốt và cho chuột xuyên qua thay vì gỡ panel khỏi màn hình, để WebKit không dừng phát.

### Gợi ý nội dung

`RecommendationService.swift` làm theo ba bước: gom ứng viên từ nhiều nguồn, chấm điểm, xếp lại cho đa dạng. Hồ sơ sở thích (kênh, chủ đề) lưu trong `UserDefaults` và giảm dần theo thời gian. Không có máy chủ: mọi dữ liệu lấy từ API công khai của YouTube không cần đăng nhập, nên không có feed trang chủ thật của YouTube để dùng.

## 8. Nơi lưu dữ liệu người dùng

Tất cả nằm trong `UserDefaults` của bundle `com.auratube.macos`: lịch sử xem, đánh dấu, vị trí xem dở, kênh theo dõi, hồ sơ sở thích, kích thước PiP. Xem một khoá:

```bash
defaults read com.auratube.macos auratube_default_pip_width
```

Khi đổi định dạng dữ liệu đã lưu, đổi luôn tên khoá (thêm hậu tố `_v2`, `_v3`) để dữ liệu cũ không bị đọc sai.

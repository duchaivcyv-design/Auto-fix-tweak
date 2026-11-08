<div align="center">

# Auto Fix Tweak

**Chống treo respring và cô lập tweak gây lỗi cho jailbreak iOS**

[![Version](https://img.shields.io/badge/version-0.4.0-blue?style=for-the-badge)](#-nhật-ký-thay-đổi)
[![Status](https://img.shields.io/badge/status-thử%20nghiệm-orange?style=for-the-badge)](#️-giới-hạn-cần-biết-quan-trọng)
[![iOS](https://img.shields.io/badge/iOS-14.0%2B-black?style=for-the-badge&logo=apple)](#-yêu-cầu)
[![Arch](https://img.shields.io/badge/arch-arm64%20%7C%20arm64e-lightgrey?style=for-the-badge)](#-yêu-cầu)
[![Scheme](https://img.shields.io/badge/scheme-rootless%20%7C%20rootful-green?style=for-the-badge)](#-cài-đặt)

*Tác giả: **Nguyễn Minh Hải***

</div>

---

## ✨ Tổng quan

Auto Fix Tweak tự phát hiện khi một tweak làm SpringBoard **treo, crash hoặc respring liên tục**,
sau đó **cô lập** tweak thủ phạm thay vì để cả thiết bị hỏng theo.

> **Lưu ý về nguyên lý:** một tweak không thể sửa mã máy của tweak khác đang chạy.
> "Tự khắc phục" ở đây nghĩa là **cô lập và khôi phục**: tạm tắt tweak nghi ngờ, đưa
> thiết bị về trạng thái ổn định, và cho phép bật lại bất cứ lúc nào.

## 🚀 Tính năng nổi bật

| | Tính năng | Mô tả ngắn |
|:---:|---|---|
| 🧯 | **Bắt crash SpringBoard** | Ghi PC/LR và tweak nghi ngờ trước khi process chết |
| ⏱️ | **Chống treo watchdog** | Phát hiện main thread bị kẹt và tìm dylib tweak trên stack |
| 🔁 | **Phát hiện respring loop** | Nhận ra vòng lặp khởi động lại và khôi phục tự động |
| 🎯 | **Quy trách nhiệm thông minh** | Kết hợp marker, crash report, manifest ổn định và thời điểm cài |
| 🔒 | **Cô lập tweak lỗi** | Đổi tên tweak thành `*.autofixdisabled` rồi respring |
| 🆘 | **Chế độ an toàn** | Tắt tweak không bảo vệ để thiết bị vào được SpringBoard |
| 📷 | **Sửa camera trước** | Vá hành vi AVFoundation trong Camera và FaceTime |
| 📱 | **Chống crash app** | Loại trừ tweak khỏi app lỗi (best-effort) |
| 🔔 | **Thông báo tiếng Việt** | Liệt kê tweak đã tắt, bật lại chỉ với một chạm |
| 🧹 | **Gỡ cài đặt sạch** | Khôi phục mọi tweak và hoàn tác mọi thay đổi trước khi xoá |

## 🔎 Cách hoạt động

<details open>
<summary><b>1. Bắt lỗi trong SpringBoard</b></summary>

Cài signal handler (`SIGSEGV`, `SIGBUS`, `SIGABRT`, `SIGILL`, `SIGFPE`, `SIGTRAP`) và
uncaught exception handler. Khi SpringBoard crash, tweak ghi PC/LR, tên image và tweak
nghi ngờ vào `crash_last.txt` trước khi process chết.

</details>

<details>
<summary><b>2. Bắt treo main thread / watchdog timeout</b></summary>

Watchdog ping main queue mỗi **3 giây**. Quá 2 lần timeout (mặc định 8 giây mỗi lần, sau
20 giây grace), nó suspend main thread, đọc thread state và unwind frame pointer để tìm
dylib tweak trên stack, rồi ghi `hang_last.txt` và gửi yêu cầu `hang`.

Daemon cố can thiệp trước mốc watchdog ~20 giây của iOS. Nếu iOS vẫn kill SpringBoard,
crash report `0x8badf00d` được dùng để quy trách nhiệm cho tweak.

</details>

<details>
<summary><b>3. Phát hiện vòng lặp respring</b></summary>

Daemon root theo dõi PID của SpringBoard mỗi **1,5 giây**. Từ **3 lần** khởi động lại trong
**45 giây** được coi là loop.

</details>

<details>
<summary><b>4. Phân tích nguyên nhân</b></summary>

Thứ tự ưu tiên:

1. Cảnh báo của watchdog
2. Marker crash / hang
3. Báo cáo `.ips` / `.crash` mới nhất của SpringBoard
4. So sánh với manifest *last-known-good*
5. Tweak cài trong **7 ngày** gần nhất

Nếu không xác định được, tối đa **3 tweak** nghi ngờ sẽ bị tắt.

</details>

<details>
<summary><b>5. Cô lập và leo thang an toàn</b></summary>

- Đổi `Foo.plist` / `Foo.dylib` thành `*.autofixdisabled` trong `DynamicLibraries`, rồi respring.
- Sau **3 lần** khôi phục không ổn định, bật chế độ an toàn: tắt mọi tweak không nằm trong
  danh sách bảo vệ.
- Người dùng bật lại từng tweak từ thông báo.

</details>

<details>
<summary><b>6. Sửa camera trước, giữ tweak chạy</b></summary>

Auto Fix nạp vào **Camera** và **FaceTime**, cài lớp sửa quanh AVFoundation:

- Bổ sung lại camera trước nếu tweak khác đã ẩn nó khỏi danh sách thiết bị
- Khôi phục danh sách format
- Tạo lại `AVCaptureDeviceInput` bằng thiết bị dự phòng
- Thêm lại input khi session lỗi
- Chặn exception từ `addInput:`, `addOutput:`, `startRunning`, `lockForConfiguration:`

Nó dò camera **mỗi 3 giây**. Nếu vẫn hỏng, ghi `camera_last.txt` kèm danh sách tweak đang
nạp và **tweak nào hook method camera nào** (`hookowners`). Tweak có hook camera được ưu tiên
là nghi phạm, nhưng **không bị tắt ngay**: nó chỉ bị tạm tắt sau `cameraDisableAfterFailures`
lần sửa thất bại (mặc định **3**).

</details>

<details>
<summary><b>7. Chống crash app do tweak can thiệp</b></summary>

- Cùng một tweak làm một app crash **2 lần trong 15 phút** → thử thêm `Exclude` vào plist
  tweak (best-effort).
- Camera / FaceTime: tạm tắt hẳn tweak ngay từ crash đầu tiên.
- Tweak làm crash ở **3 app khác nhau trong 30 phút** → tạm tắt toàn bộ.

</details>

<details>
<summary><b>8. Thoát Safe Mode và chống treo khi không nạp được tweak</b></summary>

Daemon kiểm tra heartbeat. Nếu SpringBoard vẫn sống nhưng Auto Fix không được nạp (dấu hiệu
Safe Mode) và có crash report / marker gần đây chỉ ra tweak nghi ngờ, daemon tạm tắt tweak
đó rồi respring.

</details>

<details>
<summary><b>9. Bật lại / hoàn tác</b></summary>

Chọn **"Bật lại & Respring"** hoặc **"Bật lại tất cả"** trong thông báo. Daemon khôi phục tên
file gốc, xoá bản ghi quarantine, gỡ các mục `Exclude` do Auto Fix thêm vào rồi respring.

</details>

## ⚠️ Giới hạn cần biết (quan trọng)

> [!WARNING]
> Đây là **bản thử nghiệm**. Nên cài trên thiết bị đã jailbreak có khả năng khôi phục
> (Dopamine / palera1n rootless hoặc rootful tương ứng).

- **Không sửa được code của tweak khác.** Với camera, Auto Fix chỉ vá *hành vi* ở tầng
  AVFoundation; không gỡ được hook tùy ý hay logic riêng của tweak đó.
- **Watchdog chỉ chạy trong SpringBoard.** Với app thường, daemon chỉ đọc crash report, không
  chặn được crash xảy ra trước khi report được ghi.
- **Camera:** nếu tweak chỉ làm preview đen nhưng thiết bị vẫn "có mặt" và format bình thường,
  hoặc lỗi nằm trong iOS, Auto Fix không xác định được thủ phạm. Khi đó tweak vẫn chạy ở chế
  độ sửa và chẩn đoán được ghi vào `camera_hooks.txt` / `camera_diag.txt`.
- **`Exclude` không được ElleKit hỗ trợ** (chỉ đọc `Filter.Bundles` và `Filter.Executables`),
  nên loại trừ theo app chỉ là best-effort và không thể dùng để "chữa" camera.
- **Chọn thủ phạm là heuristic.** Có thể tắt nhầm tweak lành. Luôn có nút bật lại và chế độ an toàn.
- **Safe Mode chỉ được thoát** khi có crash report / marker gần đây quy được cho tweak. Không có
  bằng chứng thì giữ nguyên để tránh tắt nhầm.
- **Cần daemon chạy bằng root**, vì SpringBoard chạy quyền `mobile` không thể đổi tên file trong
  thư mục tweak do root sở hữu.

## 📋 Yêu cầu

| Hạng mục | Yêu cầu |
|---|---|
| iOS | 14.0 trở lên |
| Kiến trúc | arm64 / arm64e |
| Scheme | `rootless` (`iphoneos-arm64`) hoặc `rootful` (`iphoneos-arm`) |
| Build | WSL/Linux hoặc macOS, [Theos](https://theos.dev), SDK iPhoneOS 15.6 |

## 📦 Thành phần sau khi cài

<details>
<summary><b>Rootless</b> (tiền tố <code>/var/jb</code>)</summary>

```
/var/jb/Library/MobileSubstrate/DynamicLibraries/AutoFixTweak.dylib
/var/jb/Library/MobileSubstrate/DynamicLibraries/AutoFixTweak.plist
/var/jb/usr/libexec/AutoFixDaemon
/var/jb/Library/LaunchDaemons/com.minhhai.autofixtweakd.plist
```

</details>

<details>
<summary><b>Rootful</b></summary>

Giống rootless, bỏ tiền tố `/var/jb`.

</details>

Tweak nạp vào **SpringBoard**, **Camera** và **FaceTime** (filter `com.apple.springboard`,
`com.apple.camera`, `com.apple.facetime`). Trong Camera/FaceTime, nó chỉ chạy lớp sửa camera
và bộ dò camera, không bật watchdog hay UI.

<details>
<summary><b>Dữ liệu và log</b> — <code>/var/mobile/Library/AutoFixTweak/</code></summary>

```
├── config.plist          # cấu hình
├── tweak_state.plist     # heartbeat, boot, lastNoticeSeen
├── daemon_state.plist    # quarantine, notice, lastAnalysis (root sở hữu)
├── last_good.plist       # manifest trạng thái ổn định
├── crash_last.txt        # marker crash gần nhất
├── hang_last.txt         # marker treo gần nhất
├── camera_last.txt       # marker lỗi camera (có thể nằm trong tmp của Camera)
├── camera_hooks.txt      # tweak nào đang hook method camera nào
├── camera_diag.txt       # báo cáo chẩn đoán lớp sửa camera
├── tweak.log
├── daemon.log
├── daemon.out / daemon.err
└── requests/             # IPC: *.req (mobile ghi, daemon xử lý)
```

</details>

## ⚙️ Cấu hình

Sửa `/var/mobile/Library/AutoFixTweak/config.plist`, rồi respring hoặc khởi động lại daemon.

<details>
<summary><b>Xem toàn bộ các khoá</b></summary>

**Vòng lặp và watchdog**

| Khoá | Mặc định | Ý nghĩa |
|---|:---:|---|
| `enabled` | `true` | Bật toàn bộ cơ chế |
| `notifyUI` | `true` | Hiện thông báo trong SpringBoard |
| `loopWindow` | `45` | Cửa sổ thời gian (giây) để đếm restart |
| `loopCount` | `3` | Số restart trong cửa sổ để coi là loop |
| `hangTimeout` | `8` | Thời gian chờ ping main thread (giây) |
| `hangGrace` | `20` | Bỏ qua watchdog N giây đầu sau khi SpringBoard khởi động |
| `maxRecoveries` | `3` | Số lần khôi phục trước khi vào chế độ an toàn |
| `allowSafeAll` | `true` | Cho phép tắt toàn bộ tweak khi cần |
| `heartbeatInterval` | `10` | Chu kỳ heartbeat của tweak (giây) |

**Crash app**

| Khoá | Mặc định | Ý nghĩa |
|---|:---:|---|
| `appGuardEnabled` | `true` | Bật theo dõi crash app và loại trừ tweak khỏi app lỗi |
| `appCrashWindow` | `900` | Cửa sổ (giây) đếm crash của cùng tweak + app |
| `appCrashThreshold` | `2` | Số crash trong cửa sổ để loại trừ tweak khỏi app |
| `appCrashEscalate` | `3` | Số crash để tạm tắt toàn bộ tweak |
| `appMultiBundleThreshold` | `3` | Số app khác nhau bị crash trong 30 phút để tạm tắt tweak |

**Safe Mode**

| Khoá | Mặc định | Ý nghĩa |
|---|:---:|---|
| `safeModeGuard` | `true` | Bật cơ chế phát hiện và thoát Safe Mode |
| `safeModeGrace` | `90` | Số giây heartbeat được coi là "mất tín hiệu" |

**Camera**

| Khoá | Mặc định | Ý nghĩa |
|---|:---:|---|
| `cameraGuard` | `true` | Bật xử lý lỗi camera do tweak |
| `cameraProbe` | `true` | Dò camera trước trong tiến trình Camera bằng AVFoundation |
| `cameraMarkerMaxAge` | `600` | Chỉ xử lý marker camera mới hơn N giây |
| `cameraCrashThreshold` | `1` | Số crash Camera/FaceTime để tạm tắt tweak |
| `cameraRepair` | `true` | Bật lớp sửa camera trong Camera/FaceTime |
| `cameraDisableAfterFailures` | `3` | Số lần sửa thất bại trước khi tạm tắt tweak |
| `cameraFailureWindow` | `1800` | Cửa sổ (giây) để đếm số lần sửa thất bại |
| `cameraNeverDisable` | `false` | `true`: không bao giờ tạm tắt tweak vì camera |

</details>

## 🛠️ Tự build

```bash
cd AutoFixTweak
chmod +x layout/DEBIAN/postinst layout/DEBIAN/prerm layout/DEBIAN/postrm build.sh

./build.sh              # build cả rootless và rootful vào dist/
./build.sh rootless     # chỉ rootless
./build.sh rootful      # chỉ rootful
```

Hoặc build trực tiếp:

```bash
cp control.rootless control
make package PACKAGE_SCHEME=rootless FINALPACKAGE=1
```

> [!TIP]
> File copy từ ổ Windows có thể mang quyền `0777`, khiến `dpkg-deb` từ chối. `build.sh` đã tự
> chuẩn hoá quyền (`0644` cho file, `0755` cho thư mục và script hook).

## 📥 Cài đặt

| Thiết bị | File cần cài |
|---|---|
| **Rootless** (Dopamine, palera1n rootless…) | `com.minhhai.autofixtweak_0.3.0_iphoneos-arm64.deb` |
| **Rootful** (checkra1n, unc0ver…) | `com.minhhai.autofixtweak_0.3.0_iphoneos-arm.deb` |

Cài bằng Sileo / Zebra / Filza, hoặc:

```bash
dpkg -i <file>.deb
```

`postinst` tạo thư mục dữ liệu, cấp quyền cho `mobile` và nạp LaunchDaemon
`com.minhhai.autofixtweakd`. Nếu launchd không tự nạp, chạy:

```bash
launchctl bootstrap system /var/jb/Library/LaunchDaemons/com.minhhai.autofixtweakd.plist
```

## 🗑️ Gỡ cài đặt

Gỡ bằng trình quản lý gói. `prerm` sẽ dừng daemon và chạy `AutoFixDaemon --restore-all` để
khôi phục tweak đã tạm tắt và gỡ các mục `Exclude` do Auto Fix thêm vào. Sau đó `postrm`:

1. Dừng daemon lần cuối
2. Khôi phục nốt mọi `*.autofixdisabled` còn sót trong các thư mục tweak
3. Xoá `/var/mobile/Library/AutoFixTweak`

## 📝 Nhật ký thay đổi

<details open>
<summary><b>🟦 0.3.0</b> — Lớp sửa camera</summary>

- Thêm **lớp sửa camera** trong Camera/FaceTime: khôi phục camera trước bị tweak khác ẩn,
  khôi phục danh sách format, tạo lại `AVCaptureDeviceInput`, thêm lại input khi session lỗi.
- Chuyển sang **sửa trước, giữ tweak chạy**: tweak nghi ngờ không bị tắt ngay. Chỉ tạm tắt sau
  `cameraDisableAfterFailures` lần thất bại (mặc định 3) trong `cameraFailureWindow` (30 phút).
- **Cài lại hook muộn** sau ~1,5 giây, để kết quả camera bị tweak khác lọc vẫn được bù lại.
- Thêm **chẩn đoán hook**: ghi `camera_hooks.txt` và `camera_diag.txt`; tweak có hook camera
  được ưu tiên là nghi phạm.
- Tự bật lại các tweak từng bị tạm tắt vì camera khi nâng cấp lên 0.3.0.
- Nạp thêm vào **FaceTime**.
- Thêm cấu hình: `cameraRepair`, `cameraDisableAfterFailures`, `cameraFailureWindow`,
  `cameraNeverDisable`.

</details>

<details>
<summary><b>🟩 0.2.2</b> — Dò camera liên tục</summary>

- Dò camera **mỗi 3 giây** trong suốt thời gian app Camera mở (trước đây chỉ một lần sau 4 giây).
- Thêm nhận diện `front-no-formats`: camera trước còn xuất hiện nhưng không còn format hợp lệ.
- Daemon kiểm tra marker camera mỗi 3 giây, nên tạm tắt tweak và kill Camera gần như ngay.
- Mỗi phiên Camera chỉ báo lỗi một lần cho mỗi lần chuyển từ "tốt" sang "hỏng".

</details>

<details>
<summary><b>🟨 0.2.1</b> — Nạp vào Camera</summary>

- Nạp vào tiến trình **Camera**, dò camera trước/sau bằng AVFoundation, ghi `camera_last.txt`.
- Daemon chọn thủ phạm, tạm tắt tweak và kill riêng tiến trình Camera (không respring).
- Crash Camera/FaceTime được xử lý ngay lần đầu.
- Ghi nhận `loadedTweaks` từ crash report và đọc `Filter` của tweak để ưu tiên đúng thủ phạm.

</details>

<details>
<summary><b>🟥 0.2.0</b> — Chống crash app và watchdog</summary>

- Theo dõi crash app thường: loại trừ tweak khỏi app lỗi bằng `Exclude`, leo thang nếu vẫn crash.
- Nhận diện watchdog timeout (`0x8badf00d`) và quy trách nhiệm theo faulting thread.
- Phát hiện và tự thoát Safe Mode khi có bằng chứng crash từ tweak.
- Giảm `hangTimeout` / `hangGrace` để can thiệp trước watchdog của iOS.
- Thêm `AutoFixDaemon --restore-all` và `prerm` để gỡ cài đặt sạch.

</details>

<details>
<summary><b>⬜ 0.1.0</b> — Bản đầu tiên</summary>

Crash guard, hang watchdog, phát hiện respring loop, quarantine tweak lỗi, chế độ an toàn,
thông báo bật lại, daemon root, hỗ trợ rootless và rootful.

</details>

---

<div align="center">

Made with 🛡️ by **Nguyễn Minh Hải**

</div>

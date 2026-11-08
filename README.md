VĐL cuteo 

- **Tên hiển thị:** Auto Fix Tweak
- **Tác giả:** Nguyễn Minh Hải
- **Phiên bản:** 0.3.0 (bản thử nghiệm)
- **Mô tả:** Tweak giúp chống treo respring cho các tweak. Tự phát hiện vòng lặp respring,
  treo SpringBoard/watchdog timeout, crash app do tweak can thiệp, loại trừ tweak khỏi
  app bị lỗi hoặc tạm tắt tweak gây lỗi, tự thoát Safe Mode và cho bật lại từ thông báo.
- **Nền tảng:** iOS 14.0 trở lên, arm64/arm64e, rootless (`iphoneos-arm64`) và
  rootful (`iphoneos-arm`).

## Auto Fix làm gì

Một tweak không thể sửa mã máy của tweak khác đang chạy. Vì vậy "tự khắc phục" ở đây
được hiểu đúng theo nghĩa **cô lập và khôi phục**:

1. **Bắt lỗi trong SpringBoard** – cài signal handler (SIGSEGV, SIGBUS, SIGABRT,
   SIGILL, SIGFPE, SIGTRAP) và uncaught exception handler. Khi SpringBoard crash, nó ghi
   lại PC/LR, tên image và tweak nghi ngờ vào `crash_last.txt` trước khi process chết.
2. **Bắt treo main thread / watchdog timeout** – watchdog ping main queue mỗi 3 giây.
   Quá 2 lần timeout (mặc định 8 giây/lần, sau 20 giây grace), nó suspend main thread,
   đọc thread state và unwind frame pointer để tìm dylib tweak trên stack, ghi
   `hang_last.txt` và gửi yêu cầu `hang`. Daemon cố can thiệp trước mốc watchdog
   ~20 giây của iOS; nếu iOS vẫn kill SpringBoard, crash report `0x8badf00d` được
   dùng để quy trách nhiệm cho tweak.
3. **Phát hiện vòng lặp respring** – daemon root theo dõi PID của SpringBoard mỗi 1,5
   giây. Từ 3 lần khởi động lại trong 45 giây được coi là loop.
4. **Phân tích nguyên nhân** – ưu tiên: cảnh báo của watchdog → marker crash/hang →
   báo cáo `.ips`/`.crash` mới nhất của SpringBoard → so sánh với manifest "trạng thái
   ổn định" (last-known-good) → tweak cài trong 7 ngày gần nhất. Nếu không xác định
   được, tắt tối đa 3 tweak nghi ngờ.
5. **Cô lập tweak lỗi** – daemon root đổi tên `Foo.plist`/`Foo.dylib` thành
   `*.autofixdisabled` trong thư mục DynamicLibraries rồi respring. Các tweak còn lại
   vẫn chạy bình thường.
6. **Leo thang an toàn** – sau 3 lần khôi phục không ổn định, daemon bật chế độ an toàn:
   tắt toàn bộ tweak không nằm trong danh sách bảo vệ để thiết bị vào được SpringBoard.
   Người dùng có thể bật lại từng tweak từ thông báo.
7. **Sửa camera trước, giữ tweak chạy** – Auto Fix được nạp vào **Camera** và
   **FaceTime**, cài một lớp sửa quanh AVFoundation: bổ sung lại camera trước vào danh
   sách thiết bị nếu tweak khác ẩn nó, khôi phục danh sách format, tạo lại
   `AVCaptureDeviceInput` bằng thiết bị dự phòng, thêm lại input khi session lỗi và chặn
   exception từ `addInput:`/`addOutput:`/`startRunning`/`lockForConfiguration:`.
   Đồng thời nó dò camera mỗi 3 giây; nếu vẫn hỏng, ghi `camera_last.txt` kèm danh sách
   tweak đang nạp và **tweak nào đang hook method camera nào** (`hookowners`). Daemon ưu
   tiên tweak có hook camera, nhưng **không tắt ngay**: tweak tiếp tục chạy và chỉ bị tạm
   tắt sau `cameraDisableAfterFailures` lần sửa thất bại (mặc định 3).
8. **Chống crash app do tweak can thiệp** – daemon còn đọc crash report (`.ips`/`.crash`)
   của app thường. Nếu cùng một tweak làm một app crash 2 lần trong 15 phút, Auto Fix
   thử thêm `Exclude` vào plist tweak (best-effort; xem giới hạn bên dưới). Với
   Camera/FaceTime, nó tạm tắt hẳn tweak ngay từ crash đầu tiên. Tweak làm crash từ 3
   app khác nhau trong 30 phút cũng bị tạm tắt toàn bộ.
9. **Tự thoát Safe Mode / chống treo khi không nạp được tweak** – daemon kiểm tra
   heartbeat của Auto Fix. Nếu SpringBoard vẫn sống nhưng Auto Fix không được nạp
   (dấu hiệu Safe Mode) và có crash report/marker gần đây chỉ ra tweak nghi ngờ, daemon
   tạm tắt tweak đó rồi respring để đưa thiết bị về trạng thái bình thường.
10. **Bật lại / hoàn tác** – thông báo tiếng Việt liệt kê tweak đã tắt và app đã loại
   trừ; chọn "Bật lại & Respring" hoặc "Bật lại tất cả". Daemon khôi phục tên file gốc,
   xoá bản ghi quarantine, gỡ các mục `Exclude` do Auto Fix thêm vào rồi respring.
11. **Gỡ cài đặt an toàn** – `prerm` dừng daemon và chạy `AutoFixDaemon --restore-all`
   để trả lại mọi tweak + hoàn tác `Exclude`; `postrm` khôi phục nốt các file
   `*.autofixdisabled` còn sót và xoá dữ liệu.

## Giới hạn cần biết (quan trọng)

- Không thể "sửa code" của tweak khác. Với camera, Auto Fix có thể vá **hành vi** ở tầng
  AVFoundation (ẩn thiết bị, mất format, tạo input lỗi, exception) để tweak tiếp tục
  chạy; nó không thể gỡ hook tùy ý của tweak khác hay sửa logic riêng của tweak đó.
- Watchdog chống treo chỉ chạy trong **SpringBoard**. Với app thường, daemon chỉ đọc
  crash report; nó không chặn được crash xảy ra trước khi report được ghi.
- **Camera**: lớp sửa xử lý được trường hợp camera trước bị ẩn khỏi danh sách thiết bị,
  mất format, hoặc tạo input lỗi. Nếu tweak chỉ làm preview đen nhưng thiết bị vẫn "có
  mặt" và format bình thường, hoặc lỗi nằm trong iOS, Auto Fix không thể xác định thủ
  phạm. Khi đó daemon vẫn giữ tweak chạy (chế độ sửa) và ghi chẩn đoán vào
  `camera_hooks.txt` / `camera_diag.txt`.
- **`Exclude` không được ElleKit hỗ trợ** (ElleKit chỉ đọc `Filter.Bundles` và
  `Filter.Executables`), nên cơ chế loại trừ theo app chỉ là best-effort và không thể
  dùng để "chữa" camera. Đường camera vì vậy dùng lớp sửa AVFoundation; nếu sửa không
  được sau ngưỡng cấu hình, daemon mới tạm tắt hẳn tweak thủ phạm.
- Việc chọn thủ phạm là heuristic: ưu tiên tweak khai báo filter cho Camera, sau đó
  tweak mới cài gần nhất trong số tweak đang nạp. Có thể tắt nhầm tweak lành; luôn có
  nút bật lại.
- Phát hiện dựa trên suy đoán: crash report, marker, thời điểm cài đặt. Có thể tắt nhầm
  tweak lành. Vì vậy luôn có nút bật lại và chế độ an toàn.
- Safe Mode chỉ được thoát khi có crash report/marker gần đây quy được cho tweak. Nếu
  không có bằng chứng, daemon giữ nguyên để tránh tắt nhầm.
- Cần **daemon chạy bằng root** vì SpringBoard chạy quyền mobile, không thể đổi tên file
  trong thư mục tweak do root sở hữu.
- Đây là bản thử nghiệm. Nên cài trên thiết bị đã jailbreak có khả năng khôi phục
  (Dopamine/palera1n rootless hoặc rootful tương ứng).

## Thành phần sau khi cài

Rootless:

```
/var/jb/Library/MobileSubstrate/DynamicLibraries/AutoFixTweak.dylib
/var/jb/Library/MobileSubstrate/DynamicLibraries/AutoFixTweak.plist
/var/jb/usr/libexec/AutoFixDaemon
/var/jb/Library/LaunchDaemons/com.minhhai.autofixtweakd.plist
```

Rootful: bỏ tiền tố `/var/jb`.

Tweak được nạp vào **SpringBoard**, **Camera** và **FaceTime** (filter
`com.apple.springboard` + `com.apple.camera` + `com.apple.facetime`). Trong Camera/FaceTime
nó chạy lớp sửa camera và bộ dò camera, không bật watchdog/UI.

Dữ liệu và log (dùng chung cho cả hai scheme):

```
/var/mobile/Library/AutoFixTweak/
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

## Cấu hình

Sửa `/var/mobile/Library/AutoFixTweak/config.plist` rồi respring (hoặc khởi động lại
daemon). Các khoá:

| Khoá | Mặc định | Ý nghĩa |
|---|---|---|
| `enabled` | `true` | Bật toàn bộ cơ chế |
| `notifyUI` | `true` | Hiện thông báo trong SpringBoard |
| `loopWindow` | `45` | Cửa sổ thời gian (giây) để đếm restart |
| `loopCount` | `3` | Số restart trong cửa sổ để coi là loop |
| `hangTimeout` | `8` | Thời gian chờ ping main thread (giây) |
| `hangGrace` | `20` | Bỏ qua watchdog trong N giây đầu sau khi SpringBoard khởi động |
| `maxRecoveries` | `3` | Số lần khôi phục trước khi vào chế độ an toàn |
| `allowSafeAll` | `true` | Cho phép tắt toàn bộ tweak khi cần |
| `heartbeatInterval` | `10` | Chu kỳ heartbeat của tweak (giây) |
| `appGuardEnabled` | `true` | Bật theo dõi crash app và loại trừ tweak khỏi app lỗi |
| `appCrashWindow` | `900` | Cửa sổ (giây) đếm crash của cùng tweak + app |
| `appCrashThreshold` | `2` | Số crash trong cửa sổ để loại trừ tweak khỏi app |
| `appCrashEscalate` | `3` | Số crash để tạm tắt toàn bộ tweak |
| `appMultiBundleThreshold` | `3` | Số app khác nhau bị crash trong 30 phút để tạm tắt tweak |
| `safeModeGuard` | `true` | Bật cơ chế phát hiện và thoát Safe Mode |
| `safeModeGrace` | `90` | Số giây heartbeat được coi là "mất tín hiệu" |
| `cameraGuard` | `true` | Bật xử lý lỗi camera do tweak |
| `cameraProbe` | `true` | Dò camera trước trong tiến trình Camera bằng AVFoundation |
| `cameraMarkerMaxAge` | `600` | Chỉ xử lý marker camera mới hơn N giây |
| `cameraCrashThreshold` | `1` | Số crash Camera/FaceTime để tạm tắt tweak |
| `cameraRepair` | `true` | Bật lớp sửa camera trong tiến trình Camera/FaceTime |
| `cameraDisableAfterFailures` | `3` | Số lần sửa thất bại trước khi tạm tắt tweak |
| `cameraFailureWindow` | `1800` | Cửa sổ (giây) để đếm số lần sửa thất bại |
| `cameraNeverDisable` | `false` | `true`: không bao giờ tạm tắt tweak vì camera |

## Tự build

Yêu cầu: WSL/Linux, Theos, SDK iPhoneOS15.6, toolchain clang của Theos.

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

Lưu ý: file copy từ ổ Windows có thể mang quyền 0777; `dpkg-deb` sẽ từ chối. `build.sh`
đã tự chuẩn hoá quyền (`chmod 0644` cho file, `0755` cho thư mục và script hook).

## Cài đặt

- Thiết bị **rootless** (Dopamine, palera1n rootless…): cài
  `com.minhhai.autofixtweak_0.3.0_iphoneos-arm64.deb`.
- Thiết bị **rootful** (checkra1n, unc0ver…): cài
  `com.minhhai.autofixtweak_0.3.0_iphoneos-arm.deb`.

Có thể cài bằng Sileo/Zebra/Filza hoặc:

```bash
dpkg -i <file>.deb
```

`postinst` tạo thư mục dữ liệu, cấp quyền cho mobile và nạp LaunchDaemon
`com.minhhai.autofixtweakd`. Nếu launchd không tự nạp, chạy:

```bash
launchctl bootstrap system /var/jb/Library/LaunchDaemons/com.minhhai.autofixtweakd.plist
```

## Gỡ cài đặt

Gỡ bằng trình quản lý gói. `prerm` sẽ dừng daemon, chạy `AutoFixDaemon --restore-all`
để khôi phục tweak đã tạm tắt và gỡ các mục `Exclude` do Auto Fix thêm vào plist.
Sau đó `postrm`:

1. Dừng daemon lần cuối.
2. Khôi phục nốt mọi `*.autofixdisabled` còn sót trong các thư mục tweak.
3. Xoá `/var/mobile/Library/AutoFixTweak`.

## Nhật ký thay đổi

### 0.3.0
- Thêm **lớp sửa camera** chạy trong tiến trình Camera/FaceTime: tự khôi phục camera
  trước bị tweak khác ẩn khỏi danh sách thiết bị, khôi phục danh sách format, tạo lại
  `AVCaptureDeviceInput` và thêm lại input khi session lỗi.
- Chuyển sang chế độ **sửa trước, giữ tweak chạy**: tweak bị nghi ngờ không bị tắt ngay;
  camera được sửa tại chỗ. Chỉ tạm tắt sau `cameraDisableAfterFailures` lần thất bại
  (mặc định 3) trong `cameraFailureWindow` (mặc định 30 phút).
- **Cài lại hook muộn** sau ~1,5 giây: hook của Auto Fix luôn nằm ngoài hook của tweak
  khác, nên kết quả camera trước bị tweak lọc mất vẫn được bù lại.
- Thêm **chẩn đoán hook**: quét các lớp AVFoundation/Camera, xác định tweak nào đang
  hook method nào, ghi `camera_hooks.txt` và `camera_diag.txt`; tweak có hook camera
  được ưu tiên là nghi phạm.
- Tự bật lại các tweak từng bị tạm tắt vì camera khi nâng cấp lên 0.3.0 để chúng chạy
  với lớp sửa mới.
- Nạp thêm vào **FaceTime** để sửa camera trước trong gọi video.
- Thêm cấu hình: `cameraRepair`, `cameraDisableAfterFailures`, `cameraFailureWindow`,
  `cameraNeverDisable`.

### 0.2.2
- Camera được dò lại **mỗi 3 giây** trong suốt thời gian app Camera mở, thay vì chỉ
  một lần sau 4 giây. Tweak phá camera sau vài giây vẫn bị phát hiện.
- Thêm nhận diện `front-no-formats`: camera trước còn xuất hiện nhưng không còn
  format hợp lệ (tweak phá cấu hình thiết bị).
- Daemon kiểm tra marker camera mỗi 3 giây, tách khỏi nhịp quét crash 30 giây, nên
  tạm tắt tweak và kill Camera gần như ngay khi phát hiện.
- Mỗi phiên Camera chỉ báo lỗi một lần cho mỗi lần chuyển từ "tốt" sang "hỏng", tránh
  tắt liên tiếp nhiều tweak.

### 0.2.1
- Auto Fix giờ được nạp vào tiến trình **Camera**: dò camera trước/sau bằng
  AVFoundation, ghi `camera_last.txt` kèm danh sách tweak đang nạp.
- Daemon đọc marker (cả bản trong sandbox Camera), chọn thủ phạm, tạm tắt hẳn tweak và
  kill riêng tiến trình Camera — không respring; mở lại Camera để kiểm tra.
- Crash Camera/FaceTime được xử lý ngay lần đầu, kể cả khi tweak chỉ nằm trong danh
  sách image đã nạp mà không xuất hiện trên stack.
- Ghi nhận `loadedTweaks` từ crash report và đọc `Filter` của tweak để ưu tiên đúng
  thủ phạm.
- Ghi rõ giới hạn: ElleKit không hỗ trợ `Exclude`, nên camera dùng biện pháp tạm tắt
  toàn bộ thay vì loại trừ theo app.

### 0.2.0
- Thêm theo dõi crash app thường: loại trừ tweak khỏi riêng app bị lỗi (Camera, Photos…)
  bằng `Exclude`, leo thang tạm tắt toàn bộ nếu vẫn crash hoặc crash nhiều app.
- Thêm nhận diện watchdog timeout (`0x8badf00d`) và quy trách nhiệm theo faulting thread.
- Thêm phát hiện và tự thoát Safe Mode khi có bằng chứng crash từ tweak.
- Giảm `hangTimeout`/`hangGrace` để can thiệp trước watchdog của iOS.
- Thêm `AutoFixDaemon --restore-all` và `prerm` để gỡ cài đặt sạch.

### 0.1.0
- Bản thử nghiệm đầu tiên: crash guard, hang watchdog, phát hiện respring loop,
  quarantine tweak lỗi, chế độ an toàn, thông báo bật lại, daemon root, hỗ trợ
  rootless và rootful.

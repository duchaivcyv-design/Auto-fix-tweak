#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

/* Cài lớp sửa camera trong tiến trình Camera: theo dõi/khôi phục thiết bị
   camera trước bị tweak khác ẩn hoặc làm hỏng cấu hình, giữ tweak đó chạy. */
void AFStartCameraRepair(void);

/* Quét các lớp AVFoundation/Camera để tìm method bị tweak khác hook.
   Trả về danh sách base tweak (không trùng), ưu tiên theo số hook. */
NSArray<NSString *> *AFScanCameraHookOwners(void);

/* Ghi báo cáo hook + trạng thái sửa vào camera_diag.txt (có fallback tmp). */
void AFWriteCameraDiagnostics(NSString * _Nullable reason,
                              NSArray<NSString *> * _Nullable bases);

/* Dùng nội bộ bởi các hook trong AFCameraRepair.xm. */
BOOL AFCameraRepairProcess(void);
BOOL AFCameraRepairEnabled(void);
BOOL AFInCameraRepair(void);
void AFSetCameraRepairGuard(BOOL value);
AVCaptureDevice * _Nullable AFFrontCameraFallbackDevice(void);
NSArray<AVCaptureDevice *> *AFRepairDeviceList(NSArray<AVCaptureDevice *> *list);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

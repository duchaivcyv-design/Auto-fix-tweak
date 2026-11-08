#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

/* Chạy trong tiến trình Camera: dò camera trước và ghi camera_last.txt
   nếu phát hiện thiết bị bị tweak khác can thiệp. */
void AFStartCameraProbe(void);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

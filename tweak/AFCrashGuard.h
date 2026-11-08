#import <Foundation/Foundation.h>
#import <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

void AFInstallCrashGuard(void);
void AFPrepareImageTable(void);
uint64_t AFStripCodePointer(uint64_t address);
NSString * _Nullable AFImagePathForAddress(uint64_t address);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

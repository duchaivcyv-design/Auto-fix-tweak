#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, AFAppGuardResult) {
    AFAppGuardResultNone = 0,
    AFAppGuardResultChanged = 1 << 0,
    AFAppGuardResultNeedRespring = 1 << 1
};

/* Quét crash report của app và marker camera; xử lý tweak gây crash/lỗi camera. */
AFAppGuardResult AFAppGuardTick(NSDictionary *config, NSMutableDictionary *state);

NSArray<NSDictionary *> *AFAppExclusionRecords(NSDictionary *state);
NSUInteger AFSanitizeExclusionRecords(NSMutableDictionary *state);

/* Hoàn tác loại trừ theo tên tweak; trả về số bản ghi đã gỡ. */
NSUInteger AFRemoveAppExclusions(NSString * _Nullable base,
                                 NSMutableDictionary *state,
                                 NSString * _Nullable * _Nullable errorOut);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif


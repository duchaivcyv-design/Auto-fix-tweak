#import <Foundation/Foundation.h>
#import "shared/AFTweakScanner.h"

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

BOOL AFDisableTweak(AFTweakInfo *info,
                     NSString *reason,
                     NSMutableDictionary *state,
                     NSString * _Nullable * _Nullable errorOut);
BOOL AFEnableTweak(NSString *base,
                   NSMutableDictionary *state,
                   NSString * _Nullable * _Nullable errorOut);
NSArray<NSDictionary *> *AFQuarantineRecords(NSDictionary *state);
BOOL AFIsTweakQuarantined(NSString *base, NSDictionary *state);

BOOL AFQuarantinePathSafe(NSString * _Nullable path, BOOL disabled);
NSUInteger AFSanitizeQuarantineRecords(NSMutableDictionary *state);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

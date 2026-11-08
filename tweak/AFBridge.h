#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

void AFRecordBootNow(void);
void AFStartHeartbeat(void);
void AFStartStatusPoller(void);
void AFQueueRequest(NSString *name, NSDictionary * _Nullable payload);
void AFUpdateTweakState(void (^updater)(NSMutableDictionary *state));

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

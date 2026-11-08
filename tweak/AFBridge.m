#import "tweak/AFBridge.h"
#import "tweak/AFUI.h"
#import "shared/AFCore.h"

#import <unistd.h>
#import <sys/stat.h>

static dispatch_queue_t gStateQueue = nil;
static dispatch_source_t gHeartbeatTimer = nil;
static dispatch_source_t gStatusTimer = nil;

static dispatch_queue_t AFStateQueue(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gStateQueue = dispatch_queue_create("com.minhhai.autofixtweak.state",
                                            DISPATCH_QUEUE_SERIAL);
    });
    return gStateQueue;
}

void AFUpdateTweakState(void (^updater)(NSMutableDictionary *state)) {
    if (!updater) return;
    dispatch_async(AFStateQueue(), ^{
        @autoreleasepool {
            AFEnsureStateDir();
            NSDictionary *existing = AFReadPlist(AFTweakStatePath());
            NSMutableDictionary *state = existing ? [existing mutableCopy]
                                                 : [NSMutableDictionary dictionary];
            NSMutableArray *boots = [state[@"boots"] isKindOfClass:[NSArray class]]
                ? [state[@"boots"] mutableCopy] : [NSMutableArray array];
            state[@"boots"] = boots;
            updater(state);
            state[@"version"] = AFVersion;
            id finalBootsValue = state[@"boots"];
            NSMutableArray *finalBoots = [finalBootsValue isKindOfClass:[NSMutableArray class]]
                ? finalBootsValue : [NSMutableArray array];
            while (finalBoots.count > 30) [finalBoots removeObjectAtIndex:0];
            state[@"boots"] = finalBoots;
            if (!AFWritePlist(AFTweakStatePath(), state)) {
                AFLog(@"Không ghi được tweak_state.plist");
            }
        }
    });
}

void AFRecordBootNow(void) {
    @autoreleasepool {
        AFEnsureStateDir();
        NSDictionary *existing = AFReadPlist(AFTweakStatePath());
        NSMutableDictionary *state = existing ? [existing mutableCopy]
                                             : [NSMutableDictionary dictionary];
        NSMutableArray *boots = [state[@"boots"] isKindOfClass:[NSArray class]]
            ? [state[@"boots"] mutableCopy] : [NSMutableArray array];
        [boots addObject:@(AFNow())];
        while (boots.count > 30) [boots removeObjectAtIndex:0];
        state[@"boots"] = boots;
        state[@"lastHeartbeat"] = @(AFNow());
        state[@"pid"] = @(getpid());
        state[@"version"] = AFVersion;
        AFWritePlist(AFTweakStatePath(), state);
    }
}

void AFStartHeartbeat(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        AFUpdateTweakState(^(NSMutableDictionary *state) {
            state[@"lastHeartbeat"] = @(AFNow());
            state[@"pid"] = @(getpid());
        });

        NSDictionary *config = AFLoadConfig();
        double interval = [config[@"heartbeatInterval"] doubleValue];
        if (interval < 3) interval = 10;

        dispatch_queue_t queue = dispatch_queue_create(
            "com.minhhai.autofixtweak.heartbeat", DISPATCH_QUEUE_SERIAL);
        gHeartbeatTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(gHeartbeatTimer,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)),
            (uint64_t)(interval * NSEC_PER_SEC), 2 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(gHeartbeatTimer, ^{
            AFUpdateTweakState(^(NSMutableDictionary *state) {
                state[@"lastHeartbeat"] = @(AFNow());
                state[@"pid"] = @(getpid());
            });
        });
        dispatch_resume(gHeartbeatTimer);
    });
}

void AFStartStatusPoller(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_queue_t queue = dispatch_queue_create(
            "com.minhhai.autofixtweak.status", DISPATCH_QUEUE_SERIAL);
        gStatusTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(gStatusTimer,
            dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC),
            6 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(gStatusTimer, ^{
            @autoreleasepool {
                NSDictionary *config = AFLoadConfig();
                if (![config[@"notifyUI"] boolValue]) return;

                NSDictionary *daemonState = AFReadPlist(AFDaemonStatePath());
                NSDictionary *notice = daemonState[@"notice"];
                if (![notice isKindOfClass:[NSDictionary class]]) return;

                double noticeID = [notice[@"id"] doubleValue];
                if (noticeID <= 0) return;

                NSDictionary *tweakState = AFReadPlist(AFTweakStatePath());
                double lastSeen = [tweakState[@"lastNoticeSeen"] doubleValue];
                if (noticeID <= lastSeen) return;

                AFUpdateTweakState(^(NSMutableDictionary *state) {
                    state[@"lastNoticeSeen"] = @(noticeID);
                });

                dispatch_async(dispatch_get_main_queue(), ^{
                    AFShowNotice(notice);
                });
            }
        });
        dispatch_resume(gStatusTimer);
    });
}

void AFQueueRequest(NSString *name, NSDictionary *payload) {
    if (name.length == 0) return;
    @autoreleasepool {
        AFEnsureStateDir();
        NSString *safeName = AFSanitizeToken(name);
        if (safeName.length == 0) return;

        NSMutableDictionary *request = payload ? [payload mutableCopy]
                                               : [NSMutableDictionary dictionary];
        request[@"created"] = @(AFNow());
        NSString *path = [AFRequestsDir() stringByAppendingPathComponent:
                          [safeName stringByAppendingString:@".req"]];
        if ([request writeToFile:path atomically:YES]) {
            chmod(path.fileSystemRepresentation, 0644);
            AFLog(@"Đã gửi yêu cầu: %@", safeName);
        } else {
            AFLog(@"Không ghi được yêu cầu: %@", safeName);
        }
    }
}

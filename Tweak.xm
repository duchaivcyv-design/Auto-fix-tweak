#import <Foundation/Foundation.h>

#import "shared/AFCore.h"
#import "tweak/AFCrashGuard.h"
#import "tweak/AFHangWatchdog.h"
#import "tweak/AFBridge.h"
#import "tweak/AFUI.h"
#import "tweak/AFCameraGuard.h"
#import "tweak/AFCameraRepair.h"

static BOOL AFIsSpringBoardProcess(void) {
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;
    if ([bundleID isEqualToString:@"com.apple.springboard"]) return YES;
    NSString *processName = [NSProcessInfo processInfo].processName;
    return [processName isEqualToString:@"SpringBoard"];
}

static BOOL AFIsCameraProcess(void) {
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;
    if ([bundleID isEqualToString:@"com.apple.camera"]) return YES;
    return [[NSProcessInfo processInfo].processName isEqualToString:@"Camera"];
}

static BOOL AFIsFaceTimeProcess(void) {
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;
    if ([bundleID isEqualToString:@"com.apple.facetime"]) return YES;
    return [[NSProcessInfo processInfo].processName isEqualToString:@"FaceTime"];
}

%ctor {
    @autoreleasepool {
        if (AFCameraRepairProcess()) AFStartCameraRepair();
        if (AFIsCameraProcess()) {
            AFStartCameraProbe();
            return;
        }
        if (AFIsFaceTimeProcess()) return;
        if (!AFIsSpringBoardProcess()) return;

        AFEnsureStateDir();
        if (!AFFileExists(AFConfigPath())) {
            AFWritePlist(AFConfigPath(), AFDefaultConfig());
        }

        AFRecordBootNow();
        AFInstallCrashGuard();
        AFStartHangWatchdog();
        AFStartHeartbeat();
        AFStartStatusPoller();

        AFLog(@"Auto Fix Tweak %@ đã nạp vào SpringBoard (pid %d)",
              AFVersion, getpid());
    }
}

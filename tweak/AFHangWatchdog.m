#import "tweak/AFHangWatchdog.h"
#import "tweak/AFCrashGuard.h"
#import "tweak/AFBridge.h"
#import "shared/AFCore.h"

#import <mach/mach.h>
#import <mach/thread_act.h>
#import <mach/arm/thread_status.h>
#import <mach/vm_map.h>
#import <pthread.h>
#import <unistd.h>
#import <time.h>

static dispatch_source_t gHangTimer = nil;
static mach_port_t gMainThreadPort = MACH_PORT_NULL;
static NSTimeInterval gWatchdogStartTime = 0;
static NSTimeInterval gLastHangRequest = 0;
static BOOL gPingInFlight = NO;
static NSUInteger gConsecutiveTimeouts = 0;

static NSString *AFSampleMainThread(NSMutableArray<NSString *> *frames) {
#if defined(__arm64__)
    if (gMainThreadPort == MACH_PORT_NULL) return nil;

    NSString *suspect = nil;
    kern_return_t result = thread_suspend(gMainThreadPort);
    if (result != KERN_SUCCESS) return nil;

    arm_thread_state64_t state;
    mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    result = thread_get_state(gMainThreadPort, ARM_THREAD_STATE64,
                              (thread_state_t)&state, &count);

    if (result == KERN_SUCCESS) {
        uint64_t pc = AFStripCodePointer((uint64_t)arm_thread_state64_get_pc(state));
        uint64_t framePointer = (uint64_t)arm_thread_state64_get_fp(state);

        NSString *pcImage = AFImagePathForAddress(pc);
        if (pcImage && frames.count < 32) [frames addObject:pcImage];
        if (pcImage && AFIsTweakImagePath(pcImage)) suspect = pcImage;

        for (int i = 0; i < 24 && framePointer != 0; i++) {
            uint64_t pair[2] = {0, 0};
            vm_size_t outSize = 0;
            kern_return_t readResult = vm_read_overwrite(mach_task_self(),
                (vm_address_t)framePointer, sizeof(pair),
                (vm_address_t)(uintptr_t)pair, &outSize);
            if (readResult != KERN_SUCCESS || outSize != sizeof(pair)) break;

            uint64_t nextFrame = pair[0];
            uint64_t returnAddress = AFStripCodePointer(pair[1]);
            NSString *image = AFImagePathForAddress(returnAddress);
            if (image && frames.count < 32) [frames addObject:image];
            if (!suspect && image && AFIsTweakImagePath(image)) suspect = image;

            if (nextFrame <= framePointer) break;
            framePointer = nextFrame;
        }
    }

    thread_resume(gMainThreadPort);

    if (!suspect) {
        for (NSString *image in frames) {
            if (AFIsTweakImagePath(image)) { suspect = image; break; }
        }
    }
    return suspect;
#else
    return nil;
#endif
}

static void AFWriteHangMarker(NSString *suspect, NSArray<NSString *> *frames, double timeout) {
    NSString *base = suspect.length ? AFBaseFromTweakFileName(suspect.lastPathComponent) : @"";
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"time=%lld\nkind=hang\nbase=%@\nimage=%@\nseconds=%.0f\n",
     (long long)time(NULL), base ?: @"", suspect ?: @"", timeout];

    NSMutableArray<NSString *> *shortFrames = [NSMutableArray array];
    for (NSString *frame in frames) {
        if (shortFrames.count >= 16) break;
        [shortFrames addObject:frame];
    }
    if (shortFrames.count) {
        [text appendFormat:@"frames=%@\n", [shortFrames componentsJoinedByString:@"|"]];
    }
    [text writeToFile:AFHangMarkerPath() atomically:YES
             encoding:NSUTF8StringEncoding error:NULL];
}

static void AFWatchdogTick(void) {
    @autoreleasepool {
        NSDictionary *config = AFLoadConfig();
        if (![config[@"enabled"] boolValue]) return;

        NSTimeInterval now = AFNow();
        double grace = [config[@"hangGrace"] doubleValue];
        if (grace <= 0) grace = 25.0;
        if (now - gWatchdogStartTime < grace) return;

        if (gPingInFlight) return;
        gPingInFlight = YES;

        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_semaphore_signal(semaphore);
        });

        double timeout = [config[@"hangTimeout"] doubleValue];
        if (timeout <= 0) timeout = 12.0;
        long waitResult = dispatch_semaphore_wait(semaphore,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)));
        gPingInFlight = NO;

        if (waitResult == 0) {
            gConsecutiveTimeouts = 0;
            return;
        }

        gConsecutiveTimeouts++;
        AFLog(@"Main thread không phản hồi ping (%.0fs), lần %lu",
              timeout, (unsigned long)gConsecutiveTimeouts);

        if (gConsecutiveTimeouts < 2) return;
        gConsecutiveTimeouts = 0;

        NSTimeInterval current = AFNow();
        if (current - gLastHangRequest < 60) return;
        gLastHangRequest = current;

        NSMutableArray<NSString *> *frames = [NSMutableArray array];
        NSString *suspect = AFSampleMainThread(frames);
        NSString *base = suspect.length ? AFBaseFromTweakFileName(suspect.lastPathComponent) : @"";

        AFWriteHangMarker(suspect, frames, timeout);
        AFLog(@"SpringBoard treo > %.0fs, nghi ngờ: %@", timeout * 2, base.length ? base : @"không xác định");

        AFQueueRequest(@"hang", @{
            @"base": base ?: @"",
            @"image": suspect ?: @"",
            @"seconds": @(timeout * 2),
            @"frames": frames ?: @[]
        });
    }
}

void AFStartHangWatchdog(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gWatchdogStartTime = AFNow();
        gMainThreadPort = pthread_mach_thread_np(pthread_self());
        dispatch_async(dispatch_get_main_queue(), ^{
            gMainThreadPort = pthread_mach_thread_np(pthread_self());
        });

        dispatch_queue_t queue = dispatch_queue_create(
            "com.minhhai.autofixtweak.watchdog", DISPATCH_QUEUE_SERIAL);
        gHangTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(gHangTimer,
            dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
            3 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(gHangTimer, ^{
            AFWatchdogTick();
        });
        dispatch_resume(gHangTimer);
    });
}

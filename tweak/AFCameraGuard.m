#import "tweak/AFCameraGuard.h"
#import "tweak/AFCameraRepair.h"
#import "shared/AFCore.h"

#import <AVFoundation/AVFoundation.h>
#import <mach-o/dyld.h>
#import <unistd.h>
#import <time.h>

typedef NS_ENUM(NSInteger, AFCameraStatus) {
    AFCameraStatusUnknown = 0,
    AFCameraStatusHealthy,
    AFCameraStatusFrontMissing,
    AFCameraStatusFrontNoFormats
};

static NSArray<NSString *> *AFLoadedTweakBases(void) {
    NSMutableArray<NSString *> *bases = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        NSString *path = [NSString stringWithUTF8String:name];
        if (path.length == 0 || !AFIsTweakImagePath(path)) continue;
        NSString *base = AFBaseFromTweakFileName(path.lastPathComponent);
        if (base.length == 0 || AFIsSelfTweakBase(base)) continue;
        NSString *key = base.lowercaseString;
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        [bases addObject:base];
    }
    return bases;
}

static void AFWriteCameraMarker(NSString *reason,
                                NSInteger front,
                                NSInteger rear,
                                NSArray<NSString *> *bases) {
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"time=%lld\n", (long long)time(NULL)];
    [text appendString:@"kind=camera\n"];
    [text appendString:@"bundle=com.apple.camera\n"];
    [text appendString:@"proc=Camera\n"];
    [text appendFormat:@"reason=%@\n", reason ?: @"unknown"];
    [text appendFormat:@"front=%ld\n", (long)front];
    [text appendFormat:@"rear=%ld\n", (long)rear];
    if (bases.count) {
        [text appendFormat:@"bases=%@\n", [bases componentsJoinedByString:@"|"]];
    }

    NSArray<NSString *> *owners = AFScanCameraHookOwners();
    if (owners.count) {
        [text appendFormat:@"hookowners=%@\n", [owners componentsJoinedByString:@"|"]];
    }

    AFEnsureStateDir();
    NSError *error = nil;
    if ([text writeToFile:AFCameraMarkerPath() atomically:YES
                 encoding:NSUTF8StringEncoding error:&error]) {
        return;
    }

    /* Sandbox của Camera có thể chặn ghi ra thư mục chung; ghi vào tmp của app. */
    NSString *fallback = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"autofix_camera.txt"];
    NSError *fallbackError = nil;
    if (![text writeToFile:fallback atomically:YES
                  encoding:NSUTF8StringEncoding error:&fallbackError]) {
        AFLog(@"Camera: không ghi được marker: %@ / %@",
              error.localizedDescription ?: @"?",
              fallbackError.localizedDescription ?: @"?");
    }
}

static NSArray<AVCaptureDeviceType> *AFVideoDeviceTypes(void) {
    NSMutableArray<AVCaptureDeviceType> *types = [NSMutableArray array];
    if (@available(iOS 11.0, *)) {
        [types addObject:AVCaptureDeviceTypeBuiltInWideAngleCamera];
        [types addObject:AVCaptureDeviceTypeBuiltInTrueDepthCamera];
    }
    return types;
}

static AVCaptureDeviceDiscoverySession *AFSharedDiscovery(void) {
    static AVCaptureDeviceDiscoverySession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            session = [AVCaptureDeviceDiscoverySession
                discoverySessionWithDeviceTypes:AFVideoDeviceTypes()
                                      mediaType:AVMediaTypeVideo
                                       position:AVCaptureDevicePositionUnspecified];
        } @catch (NSException *exception) {
            AFLog(@"Camera: không tạo được discovery session: %@",
                  exception.reason ?: exception.name);
        }
    });
    return session;
}

static AFCameraStatus AFProbeCamera(NSInteger *frontCount, NSInteger *rearCount) {
    NSInteger front = 0;
    NSInteger rear = 0;
    AVCaptureDevice *frontDevice = nil;

    NSArray<AVCaptureDevice *> *devices = AFSharedDiscovery().devices;
    for (AVCaptureDevice *device in devices) {
        if (device.position == AVCaptureDevicePositionFront) {
            front++;
            if (!frontDevice) frontDevice = device;
        } else if (device.position == AVCaptureDevicePositionBack) {
            rear++;
        }
    }

    if (frontCount) *frontCount = front;
    if (rearCount) *rearCount = rear;

    if (front > 0) {
        /* Camera trước có mặt nhưng không còn format hợp lệ: tweak đã phá
           phần cấu hình thiết bị. Chỉ kết luận khi vẫn còn camera sau. */
        if (rear > 0 && frontDevice && frontDevice.formats.count == 0) {
            return AFCameraStatusFrontNoFormats;
        }
        return AFCameraStatusHealthy;
    }
    return rear > 0 ? AFCameraStatusFrontMissing : AFCameraStatusUnknown;
}

static void AFCameraCheck(NSInteger *frontOut, NSInteger *rearOut) {
    @autoreleasepool {
        @try {
            NSDictionary *config = AFLoadConfig();
            if (![config[@"cameraProbe"] boolValue]) return;

            /* Chỉ báo lỗi một lần cho mỗi lần chuyển từ tốt sang hỏng,
               tránh daemon tắt liên tiếp nhiều tweak trong cùng một phiên Camera. */
            static BOOL reported = NO;

            NSInteger front = 0;
            NSInteger rear = 0;
            AFCameraStatus status = AFProbeCamera(&front, &rear);
            if (frontOut) *frontOut = front;
            if (rearOut) *rearOut = rear;

            if (status == AFCameraStatusHealthy || status == AFCameraStatusUnknown) {
                if (reported) {
                    AFLog(@"Camera: camera trước đã trở lại bình thường");
                }
                reported = NO;
                return;
            }
            if (reported) return;

            NSArray<NSString *> *bases = AFLoadedTweakBases();
            AFLog(@"Camera: %@ (front=%ld rear=%ld tweak=%lu)",
                  status == AFCameraStatusFrontMissing ? @"front-missing"
                                                       : @"front-no-formats",
                  (long)front, (long)rear, (unsigned long)bases.count);
            reported = YES;
            if (bases.count == 0) return;

            AFWriteCameraMarker(status == AFCameraStatusFrontMissing
                                    ? @"front-missing" : @"front-no-formats",
                                front, rear, bases);
        } @catch (NSException *exception) {
            AFLog(@"Camera: bỏ qua thăm dò do lỗi %@",
                  exception.reason ?: exception.name);
        }
    }
}

void AFStartCameraProbe(void) {
    static dispatch_once_t once;
    static dispatch_source_t timer;
    dispatch_once(&once, ^{
        dispatch_queue_t queue = dispatch_queue_create(
            "com.minhhai.autofixtweak.camera", DISPATCH_QUEUE_SERIAL);

        /* Chờ Camera dựng xong session rồi dò ngay, sau đó dò lại mỗi 3 giây.
           Camera có thể bị tweak phá sau khi đã mở vài giây, nên một lần dò
           duy nhất ở giây thứ 4 là không đủ. */
        timer = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(timer,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),
            (uint64_t)(3 * NSEC_PER_SEC), (uint64_t)(0.5 * NSEC_PER_SEC));
        dispatch_source_set_event_handler(timer, ^{
            AFCameraCheck(NULL, NULL);
        });
        dispatch_resume(timer);
    });
}

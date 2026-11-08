#import "tweak/AFCameraRepair.h"
#import "shared/AFCore.h"

#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <substrate.h>
#import <mach-o/dyld.h>
#import <time.h>

/* Cờ chống đệ quy: khi lớp sửa đang tự liệt kê thiết bị, các hook của chính
   Auto Fix phải gọi thẳng implementation gốc thay vì sửa lại kết quả. */
static _Thread_local BOOL tAFRepairGuard;
static BOOL gCameraRepairEnabled = NO;

BOOL AFInCameraRepair(void) {
    return tAFRepairGuard;
}

BOOL AFCameraRepairEnabled(void) {
    return gCameraRepairEnabled;
}

BOOL AFCameraRepairProcess(void) {
    static BOOL isCamera = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *bundleID = [NSBundle mainBundle].bundleIdentifier ?: @"";
        NSString *process = [NSProcessInfo processInfo].processName ?: @"";
        isCamera = [bundleID isEqualToString:@"com.apple.camera"] ||
                   [bundleID isEqualToString:@"com.apple.facetime"] ||
                   [process caseInsensitiveCompare:@"Camera"] == NSOrderedSame ||
                   [process caseInsensitiveCompare:@"FaceTime"] == NSOrderedSame;
    });
    return isCamera;
}

void AFSetCameraRepairGuard(BOOL value) {
    tAFRepairGuard = value;
}

static uintptr_t AFStripPointerAuth(uintptr_t value) {
    if (value > 0x00007FFFFFFFFFFFULL) {
        value &= 0x00007FFFFFFFFFFFULL;
    }
    return value;
}

static NSString *AFTweakBaseForAddress(void *address) {
    if (!address) return nil;
    uintptr_t raw = AFStripPointerAuth((uintptr_t)address);
    Dl_info info;
    if (dladdr((void *)raw, &info) == 0 || !info.dli_fname) return nil;
    NSString *path = [NSString stringWithUTF8String:info.dli_fname];
    if (path.length == 0 || !AFIsTweakImagePath(path)) return nil;
    NSString *base = AFBaseFromTweakFileName(path.lastPathComponent);
    if (base.length == 0 || AFIsSelfTweakBase(base)) return nil;
    return base;
}

static NSArray<AVCaptureDeviceType> *AFRepairDeviceTypes(void) {
    NSMutableArray<AVCaptureDeviceType> *types = [NSMutableArray array];
    if (@available(iOS 11.0, *)) {
        [types addObject:AVCaptureDeviceTypeBuiltInWideAngleCamera];
        [types addObject:AVCaptureDeviceTypeBuiltInTrueDepthCamera];
    }
    return types;
}

static BOOL AFDeviceIsFront(AVCaptureDevice *device) {
    return device && device.position == AVCaptureDevicePositionFront;
}

static NSArray<AVCaptureDevice *> *AFCollectFrontDevices(void) {
    NSMutableArray<AVCaptureDevice *> *found = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    void (^addDevice)(AVCaptureDevice *) = ^(AVCaptureDevice *device) {
        if (!AFDeviceIsFront(device)) return;
        NSString *key = device.uniqueID.length ? device.uniqueID
                       : [NSString stringWithFormat:@"%p", device];
        if ([seen containsObject:key]) return;
        [seen addObject:key];
        [found addObject:device];
    };

    @try {
        AVCaptureDeviceDiscoverySession *session =
            [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:AFRepairDeviceTypes()
                                                                   mediaType:AVMediaTypeVideo
                                                                    position:AVCaptureDevicePositionUnspecified];
        for (AVCaptureDevice *device in session.devices) addDevice(device);
    } @catch (NSException *exception) {
        AFLog(@"CameraRepair: discovery lỗi %@", exception.reason ?: exception.name);
    }

    @try {
        for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
            addDevice(device);
        }
    } @catch (NSException *exception) {
        AFLog(@"CameraRepair: devicesWithMediaType lỗi %@", exception.reason ?: exception.name);
    }

    return found;
}

AVCaptureDevice *AFFrontCameraFallbackDevice(void) {
    static AVCaptureDevice *cached = nil;
    static NSTimeInterval cachedAt = 0;
    static NSRecursiveLock *lock = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lock = [[NSRecursiveLock alloc] init];
    });

    [lock lock];
    NSTimeInterval now = AFNow();
    if (cached && now - cachedAt < 2.0) {
        AVCaptureDevice *device = cached;
        [lock unlock];
        return device;
    }

    BOOL previous = tAFRepairGuard;
    tAFRepairGuard = YES;
    NSArray<AVCaptureDevice *> *devices;
    @try {
        devices = AFCollectFrontDevices();
    } @catch (NSException *exception) {
        devices = @[];
        AFLog(@"CameraRepair: liệt kê camera lỗi %@", exception.reason ?: exception.name);
    }
    tAFRepairGuard = previous;

    AVCaptureDevice *chosen = nil;
    for (AVCaptureDevice *device in devices) {
        if (device.formats.count > 0) { chosen = device; break; }
    }
    if (!chosen) chosen = devices.firstObject;

    cached = chosen;
    cachedAt = now;
    [lock unlock];
    return chosen;
}

NSArray<AVCaptureDevice *> *AFRepairDeviceList(NSArray<AVCaptureDevice *> *list) {
    if (![list isKindOfClass:[NSArray class]]) return list;
    if (tAFRepairGuard) return list;

    BOOL hasFront = NO;
    for (AVCaptureDevice *device in list) {
        if (AFDeviceIsFront(device)) { hasFront = YES; break; }
    }
    if (hasFront) return list;

    AVCaptureDevice *front = AFFrontCameraFallbackDevice();
    if (!front) return list;

    NSMutableArray<AVCaptureDevice *> *repaired = [NSMutableArray arrayWithArray:list];
    [repaired addObject:front];
    AFLog(@"CameraRepair: thêm lại camera trước vào danh sách thiết bị");
    return repaired;
}

static void AFWriteRepairText(NSString *text, NSString *fileName) {
    AFEnsureStateDir();
    NSString *path = [AFStateDir() stringByAppendingPathComponent:fileName];
    NSError *error = nil;
    if ([text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        return;
    }
    NSString *fallback = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    NSError *fallbackError = nil;
    if (![text writeToFile:fallback atomically:YES
                  encoding:NSUTF8StringEncoding error:&fallbackError]) {
        AFLog(@"CameraRepair: không ghi được %@: %@ / %@", fileName,
              error.localizedDescription ?: @"?",
              fallbackError.localizedDescription ?: @"?");
    }
}

static NSArray<NSString *> *AFCameraDiagnosticClasses(void) {
    return @[
        @"AVCaptureDevice",
        @"AVCaptureDeviceDiscoverySession",
        @"AVCaptureDeviceInput",
        @"AVCaptureDeviceFormat",
        @"AVCaptureSession",
        @"AVCaptureVideoPreviewLayer",
        @"AVCaptureConnection",
        @"AVCapturePhotoOutput",
        @"AVCapturePhotoSettings",
        @"AVCaptureStillImageOutput",
        @"AVCaptureVideoDataOutput",
        @"AVCaptureMetadataOutput",
        @"AVCaptureMovieFileOutput",
        @"AVCaptureAudioDataOutput",
        @"CAMCameraViewController",
        @"CAMCaptureController",
        @"CAMApplicationDelegate",
        @"CAMViewfinderViewController"
    ];
}

NSArray<NSString *> *AFScanCameraHookOwners(void) {
    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    NSMutableSet<NSString *> *seenPairs = [NSMutableSet set];

    for (NSString *className in AFCameraDiagnosticClasses()) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;
        Class cursor = cls;
        NSUInteger depth = 0;
        while (cursor && cursor != [NSObject class] && depth < 6) {
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cursor, &methodCount);
            for (unsigned int i = 0; i < methodCount; i++) {
                SEL selector = method_getName(methods[i]);
                if (!selector) continue;
                NSString *pair = [NSString stringWithFormat:@"%@|%@",
                                  NSStringFromClass(cursor), NSStringFromSelector(selector)];
                if ([seenPairs containsObject:pair]) continue;
                [seenPairs addObject:pair];

                IMP imp = method_getImplementation(methods[i]);
                NSString *owner = AFTweakBaseForAddress((void *)imp);
                if (!owner) continue;

                counts[owner] = @([counts[owner] unsignedIntegerValue] + 1);
                [entries addObject:[NSString stringWithFormat:@"%@|%@|%@",
                                    owner, NSStringFromClass(cursor),
                                    NSStringFromSelector(selector)]];
            }
            if (methods) free(methods);
            cursor = class_getSuperclass(cursor);
            depth++;
        }
    }

    [entries sortUsingSelector:@selector(caseInsensitiveCompare:)];
    AFWriteRepairText([entries componentsJoinedByString:@"\n"], @"camera_hooks.txt");

    NSArray<NSString *> *owners = [counts keysSortedByValueUsingComparator:
        ^NSComparisonResult(NSNumber *a, NSNumber *b) {
            return [b compare:a];
        }];
    return owners ?: @[];
}

void AFWriteCameraDiagnostics(NSString *reason, NSArray<NSString *> *bases) {
    @autoreleasepool {
        NSMutableString *text = [NSMutableString string];
        [text appendFormat:@"time=%lld\n", (long long)time(NULL)];
        [text appendFormat:@"version=%@\n", AFVersion];
        [text appendFormat:@"bundle=%@\n", [NSBundle mainBundle].bundleIdentifier ?: @"?"];
        [text appendFormat:@"proc=%@\n", [NSProcessInfo processInfo].processName ?: @"?"];
        [text appendFormat:@"reason=%@\n", reason ?: @"unknown"];
        [text appendString:@"repair=on\n"];

        NSArray<NSString *> *owners = AFScanCameraHookOwners();
        [text appendFormat:@"hookowners=%@\n", [owners componentsJoinedByString:@"|"]];
        [text appendFormat:@"loaded=%@\n", [(bases ?: @[]) componentsJoinedByString:@"|"]];

        NSString *hooksPath = [AFStateDir() stringByAppendingPathComponent:@"camera_hooks.txt"];
        NSString *hooks = [NSString stringWithContentsOfFile:hooksPath
                                                    encoding:NSUTF8StringEncoding
                                                       error:NULL];
        if (hooks.length) {
            [text appendString:@"--- hooks ---\n"];
            [text appendString:hooks];
            if (![hooks hasSuffix:@"\n"]) [text appendString:@"\n"];
        }

        AFWriteRepairText(text, @"camera_diag.txt");
    }
}

/* --- Hook muộn -------------------------------------------------------------
   Các tweak khác cài hook ở thời điểm nạp dylib. Nếu hook của Auto Fix được cài
   trước, hook của tweak kia sẽ nằm ngoài và có thể lọc mất camera trước sau khi
   Auto Fix đã sửa. Cài lại sau ~1,5 giây đưa lớp sửa lên ngoài cùng: nó gọi cả
   chuỗi hook cũ rồi bù lại kết quả. */

static NSArray *(*gOrigDiscoveryDevices)(id, SEL);
static AVCaptureDevice *(*gOrigDefaultFront)(id, SEL, AVCaptureDevicePosition);
static AVCaptureDevice *(*gOrigDefaultType)(id, SEL, AVCaptureDeviceType,
                                            AVMediaType, AVCaptureDevicePosition);
static NSArray *(*gOrigDevicesWithMediaType)(id, SEL, AVMediaType);
static NSArray *(*gOrigFormats)(id, SEL);
static id (*gOrigInputInit)(id, SEL, AVCaptureDevice *, NSError **);
static void (*gOrigAddInput)(id, SEL, AVCaptureInput *);

static NSArray *AFLateDiscoveryDevices(id self, SEL _cmd) {
    NSArray *devices = gOrigDiscoveryDevices ? gOrigDiscoveryDevices(self, _cmd) : nil;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return devices;
    return AFRepairDeviceList(devices);
}

static AVCaptureDevice *AFLateDefaultFront(id self, SEL _cmd,
                                           AVCaptureDevicePosition position) {
    AVCaptureDevice *device = gOrigDefaultFront ? gOrigDefaultFront(self, _cmd, position) : nil;
    if (device || position != AVCaptureDevicePositionFront) return device;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return device;
    AVCaptureDevice *fallback = AFFrontCameraFallbackDevice();
    if (fallback) {
        AFLog(@"CameraRepair: hook muộn khôi phục defaultDeviceWithPosition:Front");
        return fallback;
    }
    return device;
}

static AVCaptureDevice *AFLateDefaultType(id self, SEL _cmd,
                                          AVCaptureDeviceType deviceType,
                                          AVMediaType mediaType,
                                          AVCaptureDevicePosition position) {
    AVCaptureDevice *device = gOrigDefaultType
        ? gOrigDefaultType(self, _cmd, deviceType, mediaType, position) : nil;
    if (device || position != AVCaptureDevicePositionFront) return device;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return device;
    AVCaptureDevice *fallback = AFFrontCameraFallbackDevice();
    if (fallback) {
        AFLog(@"CameraRepair: hook muộn khôi phục defaultDeviceWithDeviceType position:Front");
        return fallback;
    }
    return device;
}

static NSArray *AFLateDevicesWithMediaType(id self, SEL _cmd, AVMediaType mediaType) {
    NSArray *devices = gOrigDevicesWithMediaType
        ? gOrigDevicesWithMediaType(self, _cmd, mediaType) : nil;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return devices;
    return AFRepairDeviceList(devices);
}

static NSArray *AFLateFormats(id self, SEL _cmd) {
    NSArray *formats = gOrigFormats ? gOrigFormats(self, _cmd) : nil;
    AVCaptureDevice *device = self;
    if (formats.count > 0 || device.position != AVCaptureDevicePositionFront) return formats;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return formats;

    AVCaptureDevice *fallback = AFFrontCameraFallbackDevice();
    if (fallback && fallback != device) {
        BOOL previous = AFInCameraRepair();
        AFSetCameraRepairGuard(YES);
        NSArray *altFormats = nil;
        @try {
            altFormats = [fallback formats];
        } @catch (NSException *exception) {
            altFormats = nil;
        }
        AFSetCameraRepairGuard(previous);
        if (altFormats.count) {
            AFLog(@"CameraRepair: hook muộn khôi phục %lu format camera trước",
                  (unsigned long)altFormats.count);
            return altFormats;
        }
    }

    AVCaptureDeviceFormat *active = device.activeFormat;
    if (active) return @[active];
    return formats;
}

static id AFLateInputInit(id self, SEL _cmd, AVCaptureDevice *device, NSError **error) {
    id result = gOrigInputInit ? gOrigInputInit(self, _cmd, device, error) : nil;
    if (result || !device || device.position != AVCaptureDevicePositionFront) return result;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return result;

    AVCaptureDevice *fallback = AFFrontCameraFallbackDevice();
    if (!fallback || fallback == device) return result;

    BOOL previous = AFInCameraRepair();
    AFSetCameraRepairGuard(YES);
    id retry = [[AVCaptureDeviceInput alloc] initWithDevice:fallback error:error];
    AFSetCameraRepairGuard(previous);
    if (retry) {
        AFLog(@"CameraRepair: hook muộn tạo lại input camera trước");
        return retry;
    }
    return result;
}

static void AFLateAddInput(id self, SEL _cmd, AVCaptureInput *input) {
    @try {
        if (gOrigAddInput) gOrigAddInput(self, _cmd, input);
    } @catch (NSException *exception) {
        AFLog(@"CameraRepair: hook muộn addInput lỗi %@", exception.reason ?: exception.name);
        if (![input isKindOfClass:[AVCaptureDeviceInput class]]) return;
        AVCaptureDevice *device = ((AVCaptureDeviceInput *)input).device;
        if (device.position != AVCaptureDevicePositionFront || AFInCameraRepair()) return;

        AVCaptureDevice *fallback = AFFrontCameraFallbackDevice();
        if (!fallback || fallback == device) return;
        NSError *error = nil;
        AVCaptureDeviceInput *fresh = [AVCaptureDeviceInput deviceInputWithDevice:fallback
                                                                           error:&error];
        if (!fresh) return;
        @try {
            if (gOrigAddInput) gOrigAddInput(self, _cmd, fresh);
            AFLog(@"CameraRepair: hook muộn thêm lại input camera trước");
        } @catch (NSException *second) {
            AFLog(@"CameraRepair: hook muộn vẫn lỗi input: %@",
                  second.reason ?: second.name);
        }
    }
}

static void AFInstallLateCameraHooks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!AFCameraRepairEnabled()) return;

        Class discovery = NSClassFromString(@"AVCaptureDeviceDiscoverySession");
        if (discovery) {
            MSHookMessageEx(discovery, @selector(devices),
                            (IMP)AFLateDiscoveryDevices, (IMP *)&gOrigDiscoveryDevices);
        }
        Class device = NSClassFromString(@"AVCaptureDevice");
        if (device) {
            MSHookMessageEx(device, @selector(defaultDeviceWithPosition:),
                            (IMP)AFLateDefaultFront, (IMP *)&gOrigDefaultFront);
            MSHookMessageEx(device,
                            @selector(defaultDeviceWithDeviceType:mediaType:position:),
                            (IMP)AFLateDefaultType, (IMP *)&gOrigDefaultType);
            MSHookMessageEx(device, @selector(devicesWithMediaType:),
                            (IMP)AFLateDevicesWithMediaType, (IMP *)&gOrigDevicesWithMediaType);
            MSHookMessageEx(device, @selector(formats),
                            (IMP)AFLateFormats, (IMP *)&gOrigFormats);
        }
        Class input = NSClassFromString(@"AVCaptureDeviceInput");
        if (input) {
            MSHookMessageEx(input, @selector(initWithDevice:error:),
                            (IMP)AFLateInputInit, (IMP *)&gOrigInputInit);
        }
        Class session = NSClassFromString(@"AVCaptureSession");
        if (session) {
            MSHookMessageEx(session, @selector(addInput:),
                            (IMP)AFLateAddInput, (IMP *)&gOrigAddInput);
        }
        AFLog(@"CameraRepair: đã cài hook muộn phủ lên hook của tweak khác");
    });
}

/* Được gọi sớm trong tiến trình Camera. Các hook thực tế nằm trong
   AFCameraRepairHooks.xm (Logos) để giữ nguyên chữ ký method. */
void AFStartCameraRepair(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *config = AFLoadConfig();
        if (![config[@"cameraRepair"] boolValue]) return;
        gCameraRepairEnabled = YES;
        AFWriteCameraDiagnostics(@"startup", nil);
        AFLog(@"CameraRepair: đã bật lớp sửa camera (tweak vẫn được giữ chạy)");

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            AFInstallLateCameraHooks();
        });
    });
}

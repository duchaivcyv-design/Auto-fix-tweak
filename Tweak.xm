// Auto Fix Tweak — gộp toàn bộ shared/ + tweak/ + Tweak.xm vào một file.
// Daemon (daemon/) không được gộp vào vì là process root riêng (LaunchDaemon, có main()).
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <stdint.h>
#import <sys/stat.h>
#import <sys/types.h>
#import <unistd.h>
#import <fcntl.h>
#import <pthread.h>
#import <time.h>
#import <math.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <signal.h>
#import <sys/ucontext.h>
#import <stdlib.h>
#import <string.h>
#import <stdio.h>
#import <mach/mach.h>
#import <mach/thread_act.h>
#import <mach/arm/thread_status.h>
#import <mach/vm_map.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <substrate.h>

// ---------------------------- HEADERS ----------------------------

// ===================== shared/AFCore.h =====================
#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const AFVersion;
FOUNDATION_EXPORT NSString * const AFAuthor;
FOUNDATION_EXPORT NSString * const AFDaemonLabel;

/* Paths */
NSString *AFJBRoot(void);
BOOL AFIsRootless(void);
NSString *AFStateDir(void);
NSString *AFTweakStatePath(void);
NSString *AFDaemonStatePath(void);
NSString *AFConfigPath(void);
NSString *AFRequestsDir(void);
NSString *AFLastGoodPath(void);
NSString *AFTweakLogPath(void);
NSString *AFDaemonLogPath(void);
NSString *AFCrashMarkerPath(void);
NSString *AFHangMarkerPath(void);
NSString *AFCameraMarkerPath(void);
NSString *AFDPKGStatusPath(void);
NSString *AFDPKGInfoDir(void);

NSArray<NSString *> *AFDynamicLibraryDirs(void);
NSArray<NSString *> *AFCrashReportDirs(void);

/* Files / plists / logging */
BOOL AFFileExists(NSString *path);
BOOL AFEnsureDirectory(NSString *path, int mode);
void AFEnsureStateDir(void);
void AFEnsureRequestsDir(void);
void AFChownMobile(NSString *path);
NSDictionary * _Nullable AFReadPlist(NSString *path);
BOOL AFWritePlist(NSString *path, NSDictionary *dict);
BOOL AFWritePlistSecure(NSString *path, NSDictionary *dict);
NSTimeInterval AFNow(void);
NSString *AFTimeString(NSTimeInterval interval);
NSArray<NSString *> *AFSplitLines(NSString *text);
void AFLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void AFLogTo(NSString *path, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);

/* Config */
NSDictionary *AFDefaultConfig(void);
NSDictionary *AFLoadConfig(void);

/* Tweak naming / classification */
NSString *AFSanitizeToken(NSString *token);
NSString *AFNormalizePath(NSString *path);
NSString *AFBaseFromTweakFileName(NSString *fileName);
BOOL AFIsWhitelistedTweakBase(NSString *base);
BOOL AFIsSelfTweakBase(NSString *base);
BOOL AFIsTweakImagePath(NSString *path);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

// ===================== shared/AFTweakScanner.h =====================
#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

@interface AFTweakInfo : NSObject
@property (nonatomic, copy) NSString *base;
@property (nonatomic, copy, nullable) NSString *plistPath;
@property (nonatomic, copy, nullable) NSString *dylibPath;
@property (nonatomic, copy, nullable) NSString *disabledPlistPath;
@property (nonatomic, copy, nullable) NSString *disabledDylibPath;
@property (nonatomic, copy, nullable) NSString *package;
@property (nonatomic) NSTimeInterval installTime;
@property (nonatomic) NSTimeInterval mtime;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL hasFilter;
- (NSDictionary *)dictionaryRepresentation;
@end

NSDictionary<NSString *, AFTweakInfo *> *AFScanTweakMap(void);
NSArray<AFTweakInfo *> *AFScanTweaks(void);
AFTweakInfo * _Nullable AFTweakInfoForBase(NSString *base);

/* Đọc Filter trong plist để biết tweak có được nạp vào bundle/executable hay không. */
BOOL AFTweakInfoMayLoadInProcess(AFTweakInfo *info,
                                 NSString * _Nullable bundleID,
                                 NSString * _Nullable executable);
BOOL AFTweakInfoExplicitlyTargetsBundle(AFTweakInfo *info,
                                        NSString * _Nullable bundleID,
                                        NSString * _Nullable executable);
NSDictionary<NSString *, NSNumber *> *AFPackageInstallTimes(void);
NSDictionary<NSString *, NSString *> *AFPathToPackageMap(void);
NSDictionary<NSString *, id> *AFBuildManifest(NSArray<AFTweakInfo *> *tweaks);
NSDictionary * _Nullable AFLastGoodManifest(void);
BOOL AFSaveLastGoodManifest(NSDictionary *manifest);
NSArray<AFTweakInfo *> *AFRecentlyInstalledTweaks(NSArray<AFTweakInfo *> *all,
                                                  NSTimeInterval since,
                                                  NSSet<NSString *> *exclude);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

// ===================== shared/AFCrashParser.h =====================
#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

@interface AFCrashInfo : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic) NSTimeInterval time;
@property (nonatomic, copy) NSString *procName;
@property (nonatomic, copy, nullable) NSString *exceptionType;
@property (nonatomic, copy, nullable) NSString *terminationReason;
@property (nonatomic, copy, nullable) NSString *suspectBase;
@property (nonatomic, copy, nullable) NSString *suspectPath;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSArray<NSString *> *tweakFrames;
@property (nonatomic, copy) NSArray<NSString *> *loadedTweakBases;
@property (nonatomic, copy, nullable) NSString *bundleID;
@property (nonatomic) BOOL watchdog;
- (NSDictionary *)dictionaryRepresentation;
@end

AFCrashInfo * _Nullable AFParseCrashReport(NSString *path);
NSArray<NSDictionary *> *AFCrashReportCandidates(NSTimeInterval maxAge);
NSArray<AFCrashInfo *> *AFRecentCrashReports(NSTimeInterval maxAge, NSUInteger limit);
AFCrashInfo * _Nullable AFNewestSpringBoardCrash(NSTimeInterval maxAge);
AFCrashInfo * _Nullable AFReadCrashMarker(void);
AFCrashInfo * _Nullable AFReadHangMarker(void);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

// ===================== tweak/AFBridge.h =====================
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

// ===================== tweak/AFCameraGuard.h =====================
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

// ===================== tweak/AFCameraRepair.h =====================
#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

/* Cài lớp sửa camera trong tiến trình Camera: theo dõi/khôi phục thiết bị
   camera trước bị tweak khác ẩn hoặc làm hỏng cấu hình, giữ tweak đó chạy. */
void AFStartCameraRepair(void);

/* Quét các lớp AVFoundation/Camera để tìm method bị tweak khác hook.
   Trả về danh sách base tweak (không trùng), ưu tiên theo số hook. */
NSArray<NSString *> *AFScanCameraHookOwners(void);

/* Ghi báo cáo hook + trạng thái sửa vào camera_diag.txt (có fallback tmp). */
void AFWriteCameraDiagnostics(NSString * _Nullable reason,
                              NSArray<NSString *> * _Nullable bases);

/* Dùng nội bộ bởi các hook trong AFCameraRepair.xm. */
BOOL AFCameraRepairProcess(void);
BOOL AFCameraRepairEnabled(void);
BOOL AFInCameraRepair(void);
void AFSetCameraRepairGuard(BOOL value);
AVCaptureDevice * _Nullable AFFrontCameraFallbackDevice(void);
NSArray<AVCaptureDevice *> *AFRepairDeviceList(NSArray<AVCaptureDevice *> *list);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

// ===================== tweak/AFCrashGuard.h =====================
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

// ===================== tweak/AFHangWatchdog.h =====================
#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

void AFStartHangWatchdog(void);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

// ===================== tweak/AFUI.h =====================
#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

void AFShowNotice(NSDictionary *notice);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

// ---------------------------- IMPLEMENTATION ----------------------------

// ===================== shared/AFCore.m =====================
NSString * const AFVersion = @"0.3.0";
NSString * const AFAuthor = @"Nguyễn Minh Hải";
NSString * const AFDaemonLabel = @"com.minhhai.autofixtweakd";

static const uid_t AFMobileUID = 501;
static const gid_t AFMobileGID = 501;

NSString *AFJBRoot(void) {
    static NSString *root;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:@"/var/jb/usr/lib"] || [fm fileExistsAtPath:@"/var/jb/Library"]) {
            root = @"/var/jb";
        } else {
            root = @"";
        }
    });
    return root;
}

BOOL AFIsRootless(void) {
    return AFJBRoot().length > 0;
}

NSString *AFStateDir(void) {
    return @"/var/mobile/Library/AutoFixTweak";
}

NSString *AFTweakStatePath(void) {
    return [AFStateDir() stringByAppendingPathComponent:@"tweak_state.plist"];
}

NSString *AFDaemonStatePath(void) {
    return [AFStateDir() stringByAppendingPathComponent:@"daemon_state.plist"];
}

NSString *AFConfigPath(void) {
    return [AFStateDir() stringByAppendingPathComponent:@"config.plist"];
}

NSString *AFRequestsDir(void) {
    return [AFStateDir() stringByAppendingPathComponent:@"requests"];
}

NSString *AFLastGoodPath(void) {
    return [AFStateDir() stringByAppendingPathComponent:@"last_good.plist"];
}

NSString *AFTweakLogPath(void) {
    return [AFStateDir() stringByAppendingPathComponent:@"tweak.log"];
}

NSString *AFDaemonLogPath(void) {
    return [AFStateDir() stringByAppendingPathComponent:@"daemon.log"];
}

NSString *AFCrashMarkerPath(void) {
    return [AFStateDir() stringByAppendingPathComponent:@"crash_last.txt"];
}

NSString *AFHangMarkerPath(void) {
    return [AFStateDir() stringByAppendingPathComponent:@"hang_last.txt"];
}

NSString *AFCameraMarkerPath(void) {
    return [AFStateDir() stringByAppendingPathComponent:@"camera_last.txt"];
}

static NSString *AFPathAtRoot(NSString *root, NSString *relative) {
    if (root.length == 0) {
        return [@"/" stringByAppendingPathComponent:relative];
    }
    return [root stringByAppendingPathComponent:relative];
}

NSString *AFDPKGStatusPath(void) {
    NSString *root = AFJBRoot();
    NSArray *candidates = @[
        AFPathAtRoot(root, @"var/lib/dpkg/status"),
        @"/var/lib/dpkg/status"
    ];
    for (NSString *path in candidates) {
        if (AFFileExists(path)) return path;
    }
    return candidates.firstObject;
}

NSString *AFDPKGInfoDir(void) {
    NSString *root = AFJBRoot();
    NSArray *candidates = @[
        AFPathAtRoot(root, @"var/lib/dpkg/info"),
        @"/var/lib/dpkg/info"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) return path;
    }
    return candidates.firstObject;
}

NSArray<NSString *> *AFDynamicLibraryDirs(void) {
    NSMutableArray *dirs = [NSMutableArray array];
    NSString *root = AFJBRoot();
    NSArray *candidates = @[
        AFPathAtRoot(root, @"Library/MobileSubstrate/DynamicLibraries"),
        AFPathAtRoot(root, @"usr/lib/TweakInject"),
        @"/Library/MobileSubstrate/DynamicLibraries",
        @"/usr/lib/TweakInject"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        if (path.length == 0) continue;
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) {
            if (![dirs containsObject:path]) [dirs addObject:path];
        }
    }
    return dirs;
}

NSArray<NSString *> *AFCrashReportDirs(void) {
    NSMutableArray *dirs = [NSMutableArray array];
    NSArray *candidates = @[
        @"/var/mobile/Library/Logs/CrashReporter",
        @"/var/mobile/Library/Logs/CrashReporter/Retired",
        @"/var/mobile/Library/Logs/CrashReporter/DiagnosticLogs",
        @"/var/root/Library/Logs/CrashReporter"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) {
            [dirs addObject:path];
        }
    }
    return dirs;
}

BOOL AFFileExists(NSString *path) {
    if (path.length == 0) return NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

BOOL AFEnsureDirectory(NSString *path, int mode) {
    if (path.length == 0) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL ok = [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
    if (!ok) return NO;
    chmod(path.fileSystemRepresentation, (mode_t)mode);
    if (getuid() == 0 && [path hasPrefix:@"/var/mobile/"]) {
        chown(path.fileSystemRepresentation, AFMobileUID, AFMobileGID);
    }
    return YES;
}

void AFEnsureStateDir(void) {
    AFEnsureDirectory(AFStateDir(), 0755);
    AFEnsureRequestsDir();
}

void AFEnsureRequestsDir(void) {
    AFEnsureDirectory(AFRequestsDir(), 0777);
}

void AFChownMobile(NSString *path) {
    if (path.length == 0 || getuid() != 0) return;
    if (![path hasPrefix:@"/var/mobile/"]) return;
    chown(path.fileSystemRepresentation, AFMobileUID, AFMobileGID);
}

NSDictionary *AFReadPlist(NSString *path) {
    if (path.length == 0 || !AFFileExists(path)) return nil;
    id obj = [NSDictionary dictionaryWithContentsOfFile:path];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

BOOL AFWritePlist(NSString *path, NSDictionary *dict) {
    if (path.length == 0 || !dict) return NO;
    AFEnsureDirectory([path stringByDeletingLastPathComponent], 0755);
    BOOL ok = [dict writeToFile:path atomically:YES];
    if (ok) {
        chmod(path.fileSystemRepresentation, 0644);
        AFChownMobile(path);
    }
    return ok;
}

BOOL AFWritePlistSecure(NSString *path, NSDictionary *dict) {
    if (path.length == 0 || !dict) return NO;
    AFEnsureDirectory([path stringByDeletingLastPathComponent], 0755);
    BOOL ok = [dict writeToFile:path atomically:YES];
    if (ok) {
        chmod(path.fileSystemRepresentation, 0644);
        if (getuid() == 0) {
            chown(path.fileSystemRepresentation, 0, 0);
        }
    }
    return ok;
}

NSTimeInterval AFNow(void) {
    return [[NSDate date] timeIntervalSince1970];
}

NSString *AFTimeString(NSTimeInterval interval) {
    time_t seconds = (time_t)floor(interval);
    struct tm tmValue;
    localtime_r(&seconds, &tmValue);
    char buffer[32] = {0};
    strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", &tmValue);
    return [NSString stringWithUTF8String:buffer];
}

NSArray<NSString *> *AFSplitLines(NSString *text) {
    if (text.length == 0) return @[];
    NSMutableArray *out = [NSMutableArray array];
    NSArray *raw = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSCharacterSet *trim = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSString *line in raw) {
        NSString *t = [line stringByTrimmingCharactersInSet:trim];
        if (t.length) [out addObject:t];
    }
    return out;
}

static NSLock *AFLogLock(void) {
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSLock new]; });
    return lock;
}

void AFLogTo(NSString *path, NSString *format, ...) {
    if (path.length == 0) return;
    @autoreleasepool {
        va_list args;
        va_start(args, format);
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);

        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", AFTimeString(AFNow()), message ?: @""];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (!data) return;

        AFEnsureDirectory([path stringByDeletingLastPathComponent], 0755);
        NSLock *lock = AFLogLock();
        [lock lock];
        int fd = open(path.fileSystemRepresentation, O_CREAT | O_WRONLY | O_APPEND, 0644);
        if (fd >= 0) {
            struct stat st;
            if (fstat(fd, &st) == 0 && st.st_size > 512 * 1024) {
                ftruncate(fd, 0);
                lseek(fd, 0, SEEK_SET);
            }
            ssize_t ignored = write(fd, data.bytes, data.length);
            (void)ignored;
            close(fd);
            AFChownMobile(path);
        }
        [lock unlock];
    }
}

void AFLog(NSString *format, ...) {
    @autoreleasepool {
        va_list args;
        va_start(args, format);
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        AFLogTo(AFTweakLogPath(), @"%@", message ?: @"");
    }
}

NSDictionary *AFDefaultConfig(void) {
    return @{
        @"enabled": @YES,
        @"notifyUI": @YES,
        @"loopWindow": @45.0,
        @"loopCount": @3,
        @"hangTimeout": @8.0,
        @"hangGrace": @20.0,
        @"maxRecoveries": @3,
        @"allowSafeAll": @YES,
        @"heartbeatInterval": @10.0,
        @"appGuardEnabled": @YES,
        @"appCrashWindow": @900.0,
        @"appCrashThreshold": @2,
        @"appCrashEscalate": @3,
        @"appMultiBundleThreshold": @3,
        @"safeModeGuard": @YES,
        @"safeModeGrace": @90.0,
        @"cameraGuard": @YES,
        @"cameraProbe": @YES,
        @"cameraMarkerMaxAge": @600.0,
        @"cameraCrashThreshold": @1,
        @"cameraRepair": @YES,
        @"cameraDisableAfterFailures": @3,
        @"cameraFailureWindow": @1800.0,
        @"cameraNeverDisable": @NO
    };
}

NSDictionary *AFLoadConfig(void) {
    NSMutableDictionary *config = [AFDefaultConfig() mutableCopy];
    NSDictionary *saved = AFReadPlist(AFConfigPath());
    if (saved) {
        for (NSString *key in saved) {
            config[key] = saved[key];
        }
    }
    return config;
}

NSString *AFSanitizeToken(NSString *token) {
    if (token.length == 0) return @"";
    NSMutableString *out = [NSMutableString stringWithCapacity:token.length];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-"];
    for (NSUInteger i = 0; i < token.length && out.length < 120; i++) {
        unichar c = [token characterAtIndex:i];
        if ([allowed characterIsMember:c]) {
            [out appendFormat:@"%C", c];
        } else {
            [out appendString:@"_"];
        }
    }
    return out;
}

NSString *AFNormalizePath(NSString *path) {
    if (path.length == 0) return @"";
    NSString *p = path;
    if ([p hasPrefix:@"/private/var/"]) {
        p = [p substringFromIndex:[@"/private" length]];
    }
    if ([p hasPrefix:@"/var/jb/"]) {
        p = [p substringFromIndex:[@"/var/jb" length]];
    } else if ([p isEqualToString:@"/var/jb"]) {
        p = @"/";
    }
    return p;
}

NSString *AFBaseFromTweakFileName(NSString *fileName) {
    if (fileName.length == 0) return @"";
    NSString *name = [fileName lastPathComponent];
    NSArray *suffixes = @[@".autofixdisabled", @".dylib", @".plist", @".disabled"];
    BOOL changed = YES;
    while (changed) {
        changed = NO;
        NSString *lower = name.lowercaseString;
        for (NSString *suffix in suffixes) {
            if ([lower hasSuffix:suffix] && name.length > suffix.length) {
                name = [name substringToIndex:name.length - suffix.length];
                changed = YES;
                break;
            }
        }
    }
    return name;
}

BOOL AFIsSelfTweakBase(NSString *base) {
    NSString *lower = base.lowercaseString;
    return [lower hasPrefix:@"autofixtweak"] || [lower hasPrefix:@"autofixdaemon"];
}

BOOL AFIsWhitelistedTweakBase(NSString *base) {
    NSString *lower = base.lowercaseString;
    if (AFIsSelfTweakBase(lower)) return YES;

    static NSSet *exact;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        exact = [NSSet setWithArray:@[
            @"mobilesubstrate", @"cydiasubstrate", @"libsubstrate", @"substrated",
            @"ellekit", @"libhooker", @"tweakloader", @"tweakcompat",
            @"preferenceloader", @"rocketbootstrap", @"librocketbootstrap",
            @"cephei", @"libcephei", @"libsandy", @"libcspreferences",
            @"applist", @"altlist", @"libcolorpicker", @"safemode", @"choicy",
            @"libhookerconfigurator", @"substitute", @"libsubstitute"
        ]];
    });
    if ([exact containsObject:lower]) return YES;

    NSArray *prefixes = @[
        @"ellekit", @"libhooker", @"substrate", @"tweakloader",
        @"cephei", @"preferenceloader", @"rocketbootstrap", @"libsandy",
        @"applist", @"libcolorpicker", @"libcspreferences", @"safemode",
        @"choicy", @"autofix"
    ];
    for (NSString *prefix in prefixes) {
        if ([lower hasPrefix:prefix]) return YES;
    }
    return NO;
}

BOOL AFIsTweakImagePath(NSString *path) {
    if (path.length == 0) return NO;
    if ([path containsString:@"AutoFixTweak"] || [path containsString:@"AutoFixDaemon"]) return NO;

    if ([path containsString:@"/DynamicLibraries/"]) return YES;
    if ([path containsString:@"/TweakInject/"]) return YES;

    if (![path hasSuffix:@".dylib"]) return NO;
    if (![path containsString:@"/"] && [path.lowercaseString hasPrefix:@"lib"]) return NO;
    if ([path hasPrefix:@"/System/"]) return NO;
    if ([path hasPrefix:@"/usr/lib/"]) return NO;
    if ([path hasPrefix:@"/var/jb/usr/lib/"] &&
        ![path containsString:@"/TweakInject/"]) return NO;
    return YES;
}

// ===================== shared/AFTweakScanner.m =====================
@implementation AFTweakInfo

- (BOOL)enabled {
    return self.plistPath.length > 0;
}

- (BOOL)hasFilter {
    return self.plistPath.length > 0 || self.disabledPlistPath.length > 0;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (self.base) dict[@"base"] = self.base;
    if (self.plistPath) dict[@"plist"] = self.plistPath;
    if (self.dylibPath) dict[@"dylib"] = self.dylibPath;
    if (self.disabledPlistPath) dict[@"disabledPlist"] = self.disabledPlistPath;
    if (self.disabledDylibPath) dict[@"disabledDylib"] = self.disabledDylibPath;
    if (self.package) dict[@"package"] = self.package;
    dict[@"installTime"] = @(self.installTime);
    dict[@"mtime"] = @(self.mtime);
    dict[@"enabled"] = @(self.enabled);
    return dict;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ base=%@ enabled=%d pkg=%@ plist=%@ dylib=%@>",
            self.class, self.base, self.enabled, self.package ?: @"?",
            self.plistPath ?: @"-", self.dylibPath ?: @"-"];
}

@end

static NSTimeInterval AFModificationTime(NSString *path) {
    if (path.length == 0) return 0;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    NSDate *date = attrs[NSFileModificationDate];
    return date ? date.timeIntervalSince1970 : 0;
}

static BOOL AFClassifyTweakFile(NSString *name, NSString **outBase, int *outKind) {
    NSString *suffixPlistDisabled = @".plist.autofixdisabled";
    NSString *suffixDylibDisabled = @".dylib.autofixdisabled";
    if ([name hasSuffix:suffixPlistDisabled]) {
        *outBase = [name substringToIndex:name.length - suffixPlistDisabled.length];
        *outKind = 2;
        return YES;
    }
    if ([name hasSuffix:suffixDylibDisabled]) {
        *outBase = [name substringToIndex:name.length - suffixDylibDisabled.length];
        *outKind = 3;
        return YES;
    }
    if ([name hasSuffix:@".plist"]) {
        *outBase = [name substringToIndex:name.length - [@".plist" length]];
        *outKind = 0;
        return YES;
    }
    if ([name hasSuffix:@".dylib"]) {
        *outBase = [name substringToIndex:name.length - [@".dylib" length]];
        *outKind = 1;
        return YES;
    }
    return NO;
}

NSDictionary<NSString *, AFTweakInfo *> *AFScanTweakMap(void) {
    NSMutableDictionary<NSString *, AFTweakInfo *> *map = [NSMutableDictionary dictionary];
    NSFileManager *fm = [NSFileManager defaultManager];

    for (NSString *dir in AFDynamicLibraryDirs()) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:dir error:NULL];
        if (!contents) continue;
        for (NSString *name in contents) {
            if (name.length == 0 || [name hasPrefix:@"."]) continue;

            NSString *full = [dir stringByAppendingPathComponent:name];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:full isDirectory:&isDir] || isDir) continue;

            NSString *base = nil;
            int kind = -1;
            if (!AFClassifyTweakFile(name, &base, &kind) || base.length == 0) continue;

            AFTweakInfo *info = map[base];
            if (!info) {
                info = [AFTweakInfo new];
                info.base = base;
                map[base] = info;
            }

            if (kind == 0) {
                if (!info.plistPath) info.plistPath = full;
            } else if (kind == 1) {
                if (!info.dylibPath) info.dylibPath = full;
            } else if (kind == 2) {
                if (!info.disabledPlistPath) info.disabledPlistPath = full;
            } else if (kind == 3) {
                if (!info.disabledDylibPath) info.disabledDylibPath = full;
            }
        }
    }

    NSDictionary<NSString *, NSString *> *pathMap = AFPathToPackageMap();
    NSDictionary<NSString *, NSNumber *> *installTimes = AFPackageInstallTimes();

    for (AFTweakInfo *info in map.allValues) {
        NSString *anyPath = info.plistPath ?: info.disabledPlistPath ?: info.dylibPath ?: info.disabledDylibPath;
        NSString *pkg = nil;
        if (anyPath.length) {
            pkg = pathMap[AFNormalizePath(anyPath)];
            if (!pkg) pkg = pathMap[anyPath.lastPathComponent];
        }
        if (!pkg && info.plistPath.length) {
            pkg = pathMap[AFNormalizePath(info.plistPath)];
        }
        info.package = pkg;

        NSTimeInterval bestMTime = 0;
        NSArray *paths = @[
            info.plistPath ?: @"", info.dylibPath ?: @"",
            info.disabledPlistPath ?: @"", info.disabledDylibPath ?: @""
        ];
        for (NSString *path in paths) {
            NSTimeInterval t = AFModificationTime(path);
            if (t > bestMTime) bestMTime = t;
        }
        info.mtime = bestMTime;

        NSTimeInterval install = pkg.length ? installTimes[pkg].doubleValue : 0;
        info.installTime = install > 0 ? install : bestMTime;
    }

    return map;
}

NSArray<AFTweakInfo *> *AFScanTweaks(void) {
    NSDictionary<NSString *, AFTweakInfo *> *map = AFScanTweakMap();
    return [map.allValues sortedArrayUsingComparator:^NSComparisonResult(AFTweakInfo *a, AFTweakInfo *b) {
        return [a.base caseInsensitiveCompare:b.base];
    }];
}

AFTweakInfo *AFTweakInfoForBase(NSString *base) {
    if (base.length == 0) return nil;
    NSDictionary<NSString *, AFTweakInfo *> *map = AFScanTweakMap();
    AFTweakInfo *info = map[base];
    if (info) return info;
    NSString *lower = base.lowercaseString;
    for (NSString *key in map) {
        if ([key.lowercaseString isEqualToString:lower]) return map[key];
    }
    return nil;
}

static BOOL AFPatternMatches(NSString *pattern, NSString *value) {
    if (![pattern isKindOfClass:[NSString class]] || pattern.length == 0) return NO;
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
    if ([pattern caseInsensitiveCompare:value] == NSOrderedSame) return YES;
    if ([pattern hasSuffix:@"*"]) {
        NSString *prefix = [pattern substringToIndex:pattern.length - 1];
        return [value.lowercaseString hasPrefix:prefix.lowercaseString];
    }
    return NO;
}

static BOOL AFListMatches(NSArray *list, NSString *value) {
    if (![list isKindOfClass:[NSArray class]]) return NO;
    for (id item in list) {
        if (AFPatternMatches(item, value)) return YES;
    }
    return NO;
}

BOOL AFTweakInfoMayLoadInProcess(AFTweakInfo *info,
                                 NSString *bundleID,
                                 NSString *executable) {
    if (!info || info.plistPath.length == 0) return NO;
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:info.plistPath];
    if (![root isKindOfClass:[NSDictionary class]]) return NO;

    id filterValue = root[@"Filter"];
    if (![filterValue isKindOfClass:[NSDictionary class]]) return YES;
    NSDictionary *filter = filterValue;

    NSArray *bundles = [filter[@"Bundles"] isKindOfClass:[NSArray class]]
        ? filter[@"Bundles"] : @[];
    NSArray *executables = [filter[@"Executables"] isKindOfClass:[NSArray class]]
        ? filter[@"Executables"] : @[];
    NSArray *classes = [filter[@"Classes"] isKindOfClass:[NSArray class]]
        ? filter[@"Classes"] : @[];

    if (AFListMatches(bundles, bundleID)) return YES;
    if (AFListMatches(executables, executable)) return YES;

    /* Không có Bundles/Executables thì tweak chạy theo lớp hoặc toàn hệ thống. */
    if (bundles.count == 0 && executables.count == 0) return YES;
    /* Có Classes nhưng không xác định được lớp đó có trong tiến trình hay không. */
    if (classes.count > 0) return YES;
    return NO;
}

BOOL AFTweakInfoExplicitlyTargetsBundle(AFTweakInfo *info,
                                        NSString *bundleID,
                                        NSString *executable) {
    if (!info || info.plistPath.length == 0) return NO;
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:info.plistPath];
    if (![root isKindOfClass:[NSDictionary class]]) return NO;
    id filterValue = root[@"Filter"];
    if (![filterValue isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *filter = filterValue;

    NSArray *bundles = [filter[@"Bundles"] isKindOfClass:[NSArray class]]
        ? filter[@"Bundles"] : @[];
    NSArray *executables = [filter[@"Executables"] isKindOfClass:[NSArray class]]
        ? filter[@"Executables"] : @[];
    return AFListMatches(bundles, bundleID) || AFListMatches(executables, executable);
}

static NSDictionary *gCachedPathMap;
static NSDictionary *gCachedInstallTimes;
static NSTimeInterval gCachedMapTime;

static NSLock *AFMapLock(void) {
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSLock new]; });
    return lock;
}

static void AFRefreshDPKGMaps(void) {
    NSTimeInterval now = AFNow();
    if (gCachedPathMap && gCachedInstallTimes && now - gCachedMapTime < 120) return;

    NSMutableDictionary *pathMap = [NSMutableDictionary dictionary];
    NSMutableDictionary *installTimes = [NSMutableDictionary dictionary];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *infoDir = AFDPKGInfoDir();

    NSArray *files = [fm contentsOfDirectoryAtPath:infoDir error:NULL];
    for (NSString *name in files) {
        if (![name hasSuffix:@".list"]) continue;
        NSString *pkg = [name substringToIndex:name.length - [@".list" length]];
        NSString *full = [infoDir stringByAppendingPathComponent:name];

        NSTimeInterval mtime = AFModificationTime(full);
        if (mtime > 0) installTimes[pkg] = @(mtime);

        NSData *data = [NSData dataWithContentsOfFile:full options:NSDataReadingMappedIfSafe error:NULL];
        if (!data || data.length > 4 * 1024 * 1024) continue;
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text) text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        if (!text) continue;

        for (NSString *line in AFSplitLines(text)) {
            if (![line containsString:@"/DynamicLibraries/"] &&
                ![line containsString:@"/TweakInject/"]) continue;
            if (![line hasSuffix:@".dylib"] && ![line hasSuffix:@".plist"]) continue;
            NSString *normalized = AFNormalizePath(line);
            if (normalized.length) pathMap[normalized] = pkg;
            NSString *last = line.lastPathComponent;
            if (last.length && !pathMap[last]) pathMap[last] = pkg;
        }
    }

    gCachedPathMap = [pathMap copy];
    gCachedInstallTimes = [installTimes copy];
    gCachedMapTime = now;
}

NSDictionary<NSString *, NSString *> *AFPathToPackageMap(void) {
    NSLock *lock = AFMapLock();
    [lock lock];
    AFRefreshDPKGMaps();
    NSDictionary *result = gCachedPathMap ?: @{};
    [lock unlock];
    return result;
}

NSDictionary<NSString *, NSNumber *> *AFPackageInstallTimes(void) {
    NSLock *lock = AFMapLock();
    [lock lock];
    AFRefreshDPKGMaps();
    NSDictionary *result = gCachedInstallTimes ?: @{};
    [lock unlock];
    return result;
}

NSDictionary<NSString *, id> *AFBuildManifest(NSArray<AFTweakInfo *> *tweaks) {
    NSMutableDictionary *manifest = [NSMutableDictionary dictionary];
    for (AFTweakInfo *info in tweaks) {
        if (!info.enabled || info.base.length == 0) continue;
        if (AFIsSelfTweakBase(info.base)) continue;
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"base"] = info.base;
        if (info.plistPath) entry[@"plist"] = info.plistPath;
        if (info.dylibPath) entry[@"dylib"] = info.dylibPath;
        if (info.package) entry[@"package"] = info.package;
        entry[@"installTime"] = @(info.installTime);
        entry[@"mtime"] = @(info.mtime);
        manifest[info.base] = entry;
    }
    return manifest;
}

NSDictionary *AFLastGoodManifest(void) {
    return AFReadPlist(AFLastGoodPath());
}

BOOL AFSaveLastGoodManifest(NSDictionary *manifest) {
    NSDictionary *payload = @{
        @"time": @(AFNow()),
        @"tweaks": manifest ?: @{}
    };
    return AFWritePlist(AFLastGoodPath(), payload);
}

NSArray<AFTweakInfo *> *AFRecentlyInstalledTweaks(NSArray<AFTweakInfo *> *all,
                                                  NSTimeInterval since,
                                                  NSSet<NSString *> *exclude) {
    NSMutableArray *out = [NSMutableArray array];
    for (AFTweakInfo *info in all) {
        if (!info.enabled) continue;
        if (AFIsSelfTweakBase(info.base) || AFIsWhitelistedTweakBase(info.base)) continue;
        if (exclude && [exclude containsObject:info.base]) continue;
        if (info.installTime <= 0 || info.installTime < since) continue;
        [out addObject:info];
    }
    [out sortUsingComparator:^NSComparisonResult(AFTweakInfo *a, AFTweakInfo *b) {
        if (a.installTime != b.installTime) {
            return a.installTime > b.installTime ? NSOrderedAscending : NSOrderedDescending;
        }
        if (a.mtime != b.mtime) {
            return a.mtime > b.mtime ? NSOrderedAscending : NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    return out;
}

// ===================== shared/AFCrashParser.m =====================
@implementation AFCrashInfo

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (self.path) dict[@"path"] = self.path;
    dict[@"time"] = @(self.time);
    if (self.procName) dict[@"procName"] = self.procName;
    if (self.exceptionType) dict[@"exceptionType"] = self.exceptionType;
    if (self.terminationReason) dict[@"terminationReason"] = self.terminationReason;
    if (self.suspectBase) dict[@"suspectBase"] = self.suspectBase;
    if (self.suspectPath) dict[@"suspectPath"] = self.suspectPath;
    if (self.summary) dict[@"summary"] = self.summary;
    if (self.tweakFrames.count) dict[@"tweakFrames"] = self.tweakFrames;
    if (self.loadedTweakBases.count) dict[@"loadedTweaks"] = self.loadedTweakBases;
    if (self.bundleID) dict[@"bundleID"] = self.bundleID;
    dict[@"watchdog"] = @(self.watchdog);
    return dict;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ %@>", self.class, self.summary ?: @"?"];
}

@end

static NSString *AFStringValue(id value) {
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return nil;
}

static id AFJSONObject(NSString *text) {
    if (text.length == 0) return nil;
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;
    NSError *error = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    return error ? nil : obj;
}

static NSTimeInterval AFReportMTime(NSString *path) {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    NSDate *date = attrs[NSFileModificationDate];
    return date ? date.timeIntervalSince1970 : 0;
}

static NSString *AFImagePathAtIndex(NSArray *images, NSInteger index) {
    if (index < 0 || index >= (NSInteger)images.count) return nil;
    id obj = images[(NSUInteger)index];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSString *path = AFStringValue(obj[@"path"]);
    NSString *name = AFStringValue(obj[@"name"]);
    if (path.length) return path;
    if (name.length) return name;
    return nil;
}

static void AFAppendLoadedTweak(NSMutableArray<NSString *> *bases,
                                NSMutableSet<NSString *> *seen,
                                NSString *path) {
    if (!AFIsTweakImagePath(path)) return;
    NSString *base = AFBaseFromTweakFileName(path.lastPathComponent ?: path);
    if (base.length == 0 || AFIsSelfTweakBase(base)) return;
    NSString *key = base.lowercaseString;
    if ([seen containsObject:key]) return;
    [seen addObject:key];
    [bases addObject:base];
}

static NSString *AFAbsolutePathInLine(NSString *line) {
    NSArray *tokens = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *found = nil;
    for (NSString *token in tokens) {
        if (token.length < 2 || ![token hasPrefix:@"/"]) continue;
        if ([token containsString:@".dylib"] || [token containsString:@".framework/"]) {
            found = token;
        }
    }
    return found;
}

static BOOL AFTextLooksLikeWatchdog(NSString *text) {
    if (text.length == 0) return NO;
    NSString *lower = text.lowercaseString;
    return [lower containsString:@"0x8badf00d"] ||
           [lower containsString:@"watchdog"] ||
           [lower containsString:@"timed out"];
}

static AFCrashInfo *AFParseTextCrash(NSString *text, NSString *path) {
    NSArray *lines = AFSplitLines(text);
    NSString *proc = @"";
    NSString *bundleID = nil;
    NSString *exceptionType = nil;
    NSString *termination = nil;
    NSMutableDictionary *binary = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *crashedNames = [NSMutableArray array];

    BOOL inImages = NO;
    BOOL inCrashed = NO;

    for (NSString *line in lines) {
        if ([line hasPrefix:@"Process:"]) {
            NSString *rest = [line substringFromIndex:[@"Process:" length]];
            NSArray *parts = [rest componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            for (NSString *part in parts) {
                if (part.length) { proc = part; break; }
            }
            continue;
        }
        if ([line hasPrefix:@"Identifier:"]) {
            bundleID = [[line substringFromIndex:[@"Identifier:" length]]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            continue;
        }
        if ([line hasPrefix:@"Exception Type:"]) {
            exceptionType = [[line substringFromIndex:[@"Exception Type:" length]]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            continue;
        }
        if ([line hasPrefix:@"Termination Reason:"] ||
            [line hasPrefix:@"Termination Description:"]) {
            NSString *prefix = [line hasPrefix:@"Termination Reason:"]
                ? @"Termination Reason:" : @"Termination Description:";
            NSString *value = [[line substringFromIndex:prefix.length]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (value.length) termination = value;
            continue;
        }
        if ([line hasPrefix:@"Binary Images:"]) {
            inImages = YES;
            inCrashed = NO;
            continue;
        }
        if ([line containsString:@"Crashed:"]) {
            inCrashed = YES;
            inImages = NO;
            continue;
        }
        if ([line hasPrefix:@"Thread "]) {
            inCrashed = NO;
        }

        if (inImages) {
            NSString *absolute = AFAbsolutePathInLine(line);
            if (absolute.length) {
                NSString *shortName = absolute.lastPathComponent;
                if (shortName.length) binary[shortName] = absolute;
                NSString *noExtension = [shortName stringByDeletingPathExtension];
                if (noExtension.length && !binary[noExtension]) binary[noExtension] = absolute;
            }
        }

        if (inCrashed) {
            NSArray *rawTokens = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSMutableArray *tokens = [NSMutableArray array];
            for (NSString *token in rawTokens) if (token.length) [tokens addObject:token];
            if (tokens.count >= 2) {
                NSString *first = tokens[0];
                unichar firstChar = [first characterAtIndex:0];
                if (firstChar >= '0' && firstChar <= '9') {
                    NSString *imageName = tokens[1];
                    if (imageName.length) [crashedNames addObject:imageName];
                } else {
                    inCrashed = NO;
                }
            }
        }
    }

    NSString *suspectPath = nil;
    for (NSString *name in crashedNames) {
        NSString *candidate = binary[name];
        if (!candidate) candidate = binary[[name stringByAppendingString:@".dylib"]];
        if (!candidate) candidate = binary[[name stringByDeletingPathExtension]];
        if (candidate.length && AFIsTweakImagePath(candidate)) {
            NSString *base = AFBaseFromTweakFileName(candidate.lastPathComponent);
            if (!AFIsSelfTweakBase(base)) { suspectPath = candidate; break; }
        }
    }

    if (!suspectPath) {
        for (NSString *key in binary) {
            NSString *candidate = binary[key];
            if (!AFIsTweakImagePath(candidate)) continue;
            NSString *base = AFBaseFromTweakFileName(candidate.lastPathComponent);
            if (AFIsSelfTweakBase(base)) continue;
            suspectPath = candidate;
            break;
        }
    }

    if (proc.length == 0 && suspectPath.length == 0 && exceptionType.length == 0) return nil;

    NSMutableArray<NSString *> *loadedBases = [NSMutableArray array];
    NSMutableSet<NSString *> *loadedSeen = [NSMutableSet set];
    for (NSString *key in binary) {
        AFAppendLoadedTweak(loadedBases, loadedSeen, binary[key]);
    }

    AFCrashInfo *info = [AFCrashInfo new];
    info.path = path;
    info.time = AFReportMTime(path);
    info.procName = proc.length ? proc : @"";
    info.exceptionType = exceptionType;
    info.terminationReason = termination;
    info.bundleID = bundleID.length ? bundleID : nil;
    info.watchdog = AFTextLooksLikeWatchdog(text);
    info.tweakFrames = crashedNames.count ? crashedNames : @[];
    info.loadedTweakBases = loadedBases;
    if (suspectPath.length) {
        info.suspectPath = suspectPath;
        info.suspectBase = AFBaseFromTweakFileName(suspectPath.lastPathComponent);
    }
    NSMutableString *summary = [NSMutableString stringWithFormat:@"%@ %@",
                                info.procName, exceptionType ?: @"crash"];
    if (info.suspectBase) [summary appendFormat:@" -> %@", info.suspectBase];
    info.summary = summary;
    return info;
}

AFCrashInfo *AFParseCrashReport(NSString *path) {
    if (path.length == 0) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    if (!data || data.length == 0 || data.length > 16 * 1024 * 1024) return nil;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) return nil;

    NSDictionary *body = nil;
    NSDictionary *header = nil;
    NSRange newline = [text rangeOfString:@"\n"];
    if (newline.location != NSNotFound) {
        NSString *firstLine = [text substringToIndex:newline.location];
        if ([firstLine rangeOfString:@"{"].location != NSNotFound) {
            id obj = AFJSONObject(firstLine);
            if ([obj isKindOfClass:[NSDictionary class]]) header = obj;
        }
        NSString *rest = [text substringFromIndex:newline.location + 1];
        id obj = AFJSONObject(rest);
        if ([obj isKindOfClass:[NSDictionary class]]) body = obj;
    }
    if (!body && [text hasPrefix:@"{"]) {
        id obj = AFJSONObject(text);
        if ([obj isKindOfClass:[NSDictionary class]]) body = obj;
    }
    if (!body) return AFParseTextCrash(text, path);

    NSArray *images = [body[@"usedImages"] isKindOfClass:[NSArray class]] ? body[@"usedImages"] : @[];
    NSArray *threads = [body[@"threads"] isKindOfClass:[NSArray class]] ? body[@"threads"] : @[];

    NSDictionary *triggered = nil;
    for (id thread in threads) {
        if (![thread isKindOfClass:[NSDictionary class]]) continue;
        if ([thread[@"triggered"] boolValue]) { triggered = thread; break; }
    }

    NSDictionary *faultingThread = nil;
    if ([body[@"faultingThread"] isKindOfClass:[NSNumber class]]) {
        NSInteger index = [body[@"faultingThread"] integerValue];
        if (index >= 0 && index < (NSInteger)threads.count) {
            id candidate = threads[(NSUInteger)index];
            if ([candidate isKindOfClass:[NSDictionary class]]) faultingThread = candidate;
        }
    }

    NSMutableArray<NSString *> *tweakFrames = [NSMutableArray array];
    __block NSString *suspectPath = nil;

    void (^scanFrames)(NSArray *) = ^(NSArray *frames) {
        if (![frames isKindOfClass:[NSArray class]]) return;
        for (id frameObj in frames) {
            if (![frameObj isKindOfClass:[NSDictionary class]]) continue;
            NSInteger imageIndex = [frameObj[@"imageIndex"] integerValue];
            NSString *imagePath = AFImagePathAtIndex(images, imageIndex);
            if (!AFIsTweakImagePath(imagePath)) continue;
            NSString *base = AFBaseFromTweakFileName(imagePath.lastPathComponent ?: imagePath);
            if (AFIsSelfTweakBase(base)) continue;

            NSString *symbol = AFStringValue(frameObj[@"symbol"]);
            if (symbol.length == 0) symbol = AFStringValue(frameObj[@"imageOffset"]);
            NSString *description = [NSString stringWithFormat:@"%@ %@",
                                     imagePath.lastPathComponent ?: base, symbol ?: @""];
            if (tweakFrames.count < 40) [tweakFrames addObject:description];
            if (!suspectPath) suspectPath = imagePath;
        }
    };

    if (triggered) scanFrames(triggered[@"frames"]);
    if (!suspectPath && faultingThread && faultingThread != triggered) {
        scanFrames(faultingThread[@"frames"]);
    }
    if (!suspectPath && body[@"lastExceptionBacktrace"]) scanFrames(body[@"lastExceptionBacktrace"]);
    if (!suspectPath) {
        for (id thread in threads) {
            if (![thread isKindOfClass:[NSDictionary class]]) continue;
            if (thread == triggered || thread == faultingThread) continue;
            scanFrames(thread[@"frames"]);
            if (suspectPath) break;
        }
    }

    NSMutableArray<NSString *> *loadedBases = [NSMutableArray array];
    NSMutableSet<NSString *> *loadedSeen = [NSMutableSet set];
    for (NSUInteger i = 0; i < images.count; i++) {
        AFAppendLoadedTweak(loadedBases, loadedSeen,
                            AFImagePathAtIndex(images, (NSInteger)i));
    }

    NSMutableString *exceptionType = [NSMutableString string];
    NSDictionary *exception = [body[@"exception"] isKindOfClass:[NSDictionary class]] ? body[@"exception"] : nil;
    NSString *type = AFStringValue(exception[@"type"]);
    NSString *signal = AFStringValue(exception[@"signal"]);
    if (type.length) [exceptionType appendString:type];
    if (signal.length) {
        if (exceptionType.length) [exceptionType appendString:@" "];
        [exceptionType appendFormat:@"(%@)", signal];
    }

    NSMutableString *termination = [NSMutableString string];
    NSDictionary *term = [body[@"termination"] isKindOfClass:[NSDictionary class]] ? body[@"termination"] : nil;
    NSArray *reasons = [term[@"reasons"] isKindOfClass:[NSArray class]] ? term[@"reasons"] : nil;
    for (id reason in reasons) {
        NSString *r = AFStringValue(reason);
        if (!r.length) continue;
        if (termination.length) [termination appendString:@" "];
        [termination appendString:r];
    }

    NSString *bundleID = AFStringValue(header[@"bundleID"]) ?:
                         AFStringValue(header[@"bundleIdentifier"]);
    if (bundleID.length == 0 && [body[@"bundleInfo"] isKindOfClass:[NSDictionary class]]) {
        bundleID = AFStringValue(body[@"bundleInfo"][@"CFBundleIdentifier"]);
    }
    if (bundleID.length == 0 && [body[@"procInfo"] isKindOfClass:[NSDictionary class]]) {
        bundleID = AFStringValue(body[@"procInfo"][@"CFBundleIdentifier"]);
    }

    NSString *watchdogText = [NSString stringWithFormat:@"%@ %@",
                              exceptionType ?: @"", termination ?: @""];
    NSString *lowerWatchdog = watchdogText.lowercaseString;

    AFCrashInfo *info = [AFCrashInfo new];
    info.path = path;
    info.time = AFReportMTime(path);
    info.procName = AFStringValue(body[@"procName"]) ?:
                    AFStringValue(header[@"app_name"]) ?:
                    AFStringValue(header[@"name"]) ?: @"";
    info.exceptionType = exceptionType.length ? exceptionType : nil;
    info.terminationReason = termination.length ? termination : nil;
    info.bundleID = bundleID.length ? bundleID : nil;
    info.watchdog = [lowerWatchdog containsString:@"0x8badf00d"] ||
                    [lowerWatchdog containsString:@"watchdog"] ||
                    [lowerWatchdog containsString:@"timed out"];
    info.tweakFrames = tweakFrames;
    info.loadedTweakBases = loadedBases;
    if (suspectPath.length) {
        info.suspectPath = suspectPath;
        info.suspectBase = AFBaseFromTweakFileName(suspectPath.lastPathComponent ?: suspectPath);
    }

    NSMutableString *summary = [NSMutableString stringWithFormat:@"%@ %@",
                                info.procName.length ? info.procName : @"?",
                                info.watchdog ? @"watchdog timeout" :
                                (info.exceptionType ?: @"crash")];
    if (info.terminationReason) [summary appendFormat:@" [%@]", info.terminationReason];
    if (info.suspectBase) [summary appendFormat:@" -> %@", info.suspectBase];
    info.summary = summary;
    return info;
}

NSArray<NSDictionary *> *AFCrashReportCandidates(NSTimeInterval maxAge) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSTimeInterval now = AFNow();
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    for (NSString *dir in AFCrashReportDirs()) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:dir error:NULL];
        for (NSString *name in contents) {
            NSString *extension = name.pathExtension.lowercaseString;
            if (![extension isEqualToString:@"ips"] && ![extension isEqualToString:@"crash"]) {
                continue;
            }
            NSString *full = [dir stringByAppendingPathComponent:name];
            if ([seen containsObject:full]) continue;
            [seen addObject:full];
            NSTimeInterval modified = AFReportMTime(full);
            if (modified <= 0 || now - modified > maxAge) continue;
            [candidates addObject:@{@"path": full, @"time": @(modified)}];
        }
    }

    [candidates sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        double ta = [a[@"time"] doubleValue];
        double tb = [b[@"time"] doubleValue];
        if (ta == tb) return NSOrderedSame;
        return ta > tb ? NSOrderedAscending : NSOrderedDescending;
    }];
    return candidates;
}

NSArray<AFCrashInfo *> *AFRecentCrashReports(NSTimeInterval maxAge, NSUInteger limit) {
    if (limit == 0) limit = 40;
    NSMutableArray<AFCrashInfo *> *reports = [NSMutableArray array];
    for (NSDictionary *candidate in AFCrashReportCandidates(maxAge)) {
        if (reports.count >= limit) break;
        AFCrashInfo *info = AFParseCrashReport(candidate[@"path"]);
        if (info) [reports addObject:info];
    }
    return reports;
}

AFCrashInfo *AFNewestSpringBoardCrash(NSTimeInterval maxAge) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSTimeInterval now = AFNow();
    NSString *bestPath = nil;
    NSTimeInterval bestTime = 0;

    for (NSString *dir in AFCrashReportDirs()) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:dir error:NULL];
        for (NSString *name in contents) {
            if (![name hasPrefix:@"SpringBoard"]) continue;
            NSString *extension = name.pathExtension.lowercaseString;
            if (![extension isEqualToString:@"ips"] && ![extension isEqualToString:@"crash"]) continue;
            NSString *full = [dir stringByAppendingPathComponent:name];
            NSTimeInterval modified = AFReportMTime(full);
            if (modified <= 0 || now - modified > maxAge) continue;
            if (modified > bestTime) {
                bestTime = modified;
                bestPath = full;
            }
        }
    }

    if (!bestPath) return nil;
    return AFParseCrashReport(bestPath);
}

static NSDictionary *AFReadKeyValueFile(NSString *path) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    if (text.length == 0) return nil;
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSString *line in AFSplitLines(text)) {
        NSRange separator = [line rangeOfString:@"="];
        if (separator.location == NSNotFound) continue;
        NSString *key = [line substringToIndex:separator.location];
        NSString *value = [line substringFromIndex:separator.location + 1];
        if (key.length) dict[key] = value;
    }
    return dict;
}

AFCrashInfo *AFReadCrashMarker(void) {
    NSString *path = AFCrashMarkerPath();
    NSDictionary *kv = AFReadKeyValueFile(path);
    if (!kv) return nil;

    NSTimeInterval time = [kv[@"time"] doubleValue];
    if (time <= 0) time = AFReportMTime(path);
    if (time <= 0) return nil;

    NSString *base = kv[@"base"];
    NSString *lrBase = kv[@"lr_base"];
    if (base.length == 0 || AFIsSelfTweakBase(base)) base = lrBase;
    if (base.length && AFIsSelfTweakBase(base)) base = nil;

    NSString *procValue = kv[@"proc"];
    NSString *signalValue = kv[@"signal"];
    NSString *imageValue = kv[@"image"];
    NSString *lrImageValue = kv[@"lr_image"];

    AFCrashInfo *info = [AFCrashInfo new];
    info.path = path;
    info.time = time;
    info.procName = procValue.length ? procValue : @"SpringBoard";
    NSString *signal = signalValue.length ? signalValue : @"?";
    info.exceptionType = [NSString stringWithFormat:@"signal %@", signal];
    info.suspectBase = base;
    info.suspectPath = imageValue.length ? imageValue :
                       (lrImageValue.length ? lrImageValue : nil);
    info.tweakFrames = @[];
    info.summary = [NSString stringWithFormat:@"SpringBoard signal %@%@", signal,
                    base.length ? [NSString stringWithFormat:@" -> %@", base] : @""];
    return info;
}

AFCrashInfo *AFReadHangMarker(void) {
    NSString *path = AFHangMarkerPath();
    NSDictionary *kv = AFReadKeyValueFile(path);
    if (!kv) return nil;

    NSTimeInterval time = [kv[@"time"] doubleValue];
    if (time <= 0) time = AFReportMTime(path);
    if (time <= 0) return nil;

    NSMutableArray<NSString *> *frames = [NSMutableArray array];
    NSString *framesText = kv[@"frames"];
    if (framesText.length) {
        for (NSString *frame in [framesText componentsSeparatedByString:@"|"]) {
            if (frame.length && frames.count < 40) [frames addObject:frame];
        }
    }

    NSString *base = kv[@"base"];
    NSString *image = kv[@"image"];
    if (base.length == 0) {
        for (NSString *frame in frames) {
            if (!AFIsTweakImagePath(frame)) continue;
            NSString *candidate = AFBaseFromTweakFileName(frame.lastPathComponent);
            if (candidate.length && !AFIsSelfTweakBase(candidate)) {
                base = candidate;
                image = frame;
                break;
            }
        }
    }
    if (base.length && AFIsSelfTweakBase(base)) base = nil;

    AFCrashInfo *info = [AFCrashInfo new];
    info.path = path;
    info.time = time;
    info.procName = @"SpringBoard";
    info.exceptionType = @"main-thread hang";
    info.suspectBase = base;
    info.suspectPath = image;
    info.tweakFrames = frames;
    info.summary = [NSString stringWithFormat:@"SpringBoard treo %@s%@",
                    kv[@"seconds"] ?: @"?",
                    base.length ? [NSString stringWithFormat:@" -> %@", base] : @""];
    return info;
}

// ===================== tweak/AFCrashGuard.m =====================
typedef struct {
    uint64_t start;
    uint64_t end;
    char *path;
} AFImageRange;

static AFImageRange *gRanges = NULL;
static size_t gRangeCount = 0;
static char gCrashMarkerPathC[512];
static struct sigaction gOldActions[NSIG];
static NSUncaughtExceptionHandler *gPreviousExceptionHandler = NULL;
static volatile sig_atomic_t gHandlingCrash = 0;
static volatile sig_atomic_t gMarkerWritten = 0;

static const int kAFSignals[] = { SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE, SIGTRAP };
static const size_t kAFSignalCount = sizeof(kAFSignals) / sizeof(kAFSignals[0]);

uint64_t AFStripCodePointer(uint64_t address) {
    return address & 0x00007FFFFFFFFFFFULL;
}

static void AFBaseFromPathC(const char *path, char *out, size_t outSize) {
    if (!out || outSize == 0) return;
    out[0] = '\0';
    if (!path) return;

    const char *slash = strrchr(path, '/');
    const char *name = slash ? slash + 1 : path;
    size_t length = strlen(name);

    const char *suffixes[] = { ".dylib", ".plist", NULL };
    for (int i = 0; suffixes[i]; i++) {
        size_t suffixLength = strlen(suffixes[i]);
        if (length > suffixLength &&
            strcmp(name + length - suffixLength, suffixes[i]) == 0) {
            length -= suffixLength;
            break;
        }
    }

    if (length >= outSize) length = outSize - 1;
    memcpy(out, name, length);
    out[length] = '\0';
}

void AFPrepareImageTable(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *marker = AFCrashMarkerPath().fileSystemRepresentation;
        snprintf(gCrashMarkerPathC, sizeof(gCrashMarkerPathC), "%s", marker ? marker : "");

        uint32_t imageCount = _dyld_image_count();
        AFImageRange *ranges = (AFImageRange *)calloc(imageCount > 0 ? imageCount : 1, sizeof(AFImageRange));
        if (!ranges) return;

        size_t used = 0;
        for (uint32_t i = 0; i < imageCount; i++) {
            const struct mach_header *header = _dyld_get_image_header(i);
            if (!header) continue;

            intptr_t slide = _dyld_get_image_vmaddr_slide(i);
            uint64_t start = 0;
            uint64_t end = 0;

            if (header->magic == MH_MAGIC_64) {
                const struct mach_header_64 *header64 = (const struct mach_header_64 *)header;
                const uint8_t *cursor = (const uint8_t *)(header64 + 1);
                for (uint32_t c = 0; c < header64->ncmds; c++) {
                    const struct load_command *command = (const struct load_command *)cursor;
                    if (command->cmdsize < sizeof(struct load_command)) break;
                    if (command->cmd == LC_SEGMENT_64) {
                        const struct segment_command_64 *segment =
                            (const struct segment_command_64 *)command;
                        if (strcmp(segment->segname, "__TEXT") == 0 ||
                            strcmp(segment->segname, "__TEXT_EXEC") == 0) {
                            uint64_t segmentStart = (uint64_t)(segment->vmaddr + slide);
                            uint64_t segmentEnd = segmentStart + (uint64_t)segment->vmsize;
                            if (start == 0 || segmentStart < start) start = segmentStart;
                            if (segmentEnd > end) end = segmentEnd;
                        }
                    }
                    cursor += command->cmdsize;
                }
            } else if (header->magic == MH_MAGIC) {
                const struct mach_header *header32 = header;
                const uint8_t *cursor = (const uint8_t *)(header32 + 1);
                for (uint32_t c = 0; c < header32->ncmds; c++) {
                    const struct load_command *command = (const struct load_command *)cursor;
                    if (command->cmdsize < sizeof(struct load_command)) break;
                    if (command->cmd == LC_SEGMENT) {
                        const struct segment_command *segment =
                            (const struct segment_command *)command;
                        if (strcmp(segment->segname, "__TEXT") == 0) {
                            uint64_t segmentStart = (uint64_t)(segment->vmaddr + slide);
                            uint64_t segmentEnd = segmentStart + (uint64_t)segment->vmsize;
                            if (start == 0 || segmentStart < start) start = segmentStart;
                            if (segmentEnd > end) end = segmentEnd;
                        }
                    }
                    cursor += command->cmdsize;
                }
            }

            const char *path = _dyld_get_image_name(i);
            if (!path || end <= start) continue;

            ranges[used].start = start;
            ranges[used].end = end;
            ranges[used].path = strdup(path);
            if (!ranges[used].path) continue;
            used++;
        }

        gRanges = ranges;
        gRangeCount = used;
    });
}

static const char *AFImagePathForAddressC(uint64_t address) {
    if (gRangeCount == 0 || !gRanges) return NULL;
    uint64_t value = AFStripCodePointer(address);
    for (size_t i = 0; i < gRangeCount; i++) {
        if (value >= gRanges[i].start && value < gRanges[i].end) {
            return gRanges[i].path;
        }
    }
    return NULL;
}

NSString *AFImagePathForAddress(uint64_t address) {
    AFPrepareImageTable();
    const char *path = AFImagePathForAddressC(address);
    return path ? [NSString stringWithUTF8String:path] : nil;
}

static void AFWriteSignalMarker(int sig, void *context) {
    uint64_t pc = 0;
    uint64_t lr = 0;

#if defined(__arm64__)
    if (context) {
        ucontext_t *ucontext = (ucontext_t *)context;
        if (ucontext->uc_mcontext) {
            arm_thread_state64_t state = ucontext->uc_mcontext->__ss;
            pc = (uint64_t)arm_thread_state64_get_pc(state);
            lr = (uint64_t)arm_thread_state64_get_lr(state);
        }
    }
#endif

    const char *image = AFImagePathForAddressC(pc);
    const char *lrImage = AFImagePathForAddressC(lr);
    char base[256] = {0};
    char lrBase[256] = {0};
    AFBaseFromPathC(image, base, sizeof(base));
    AFBaseFromPathC(lrImage, lrBase, sizeof(lrBase));

    char buffer[4096];
    int length = snprintf(buffer, sizeof(buffer),
        "time=%lld\n"
        "kind=signal\n"
        "signal=%d\n"
        "pc=0x%llx\n"
        "lr=0x%llx\n"
        "image=%s\n"
        "lr_image=%s\n"
        "base=%s\n"
        "lr_base=%s\n"
        "proc=SpringBoard\n",
        (long long)time(NULL), sig,
        (unsigned long long)pc, (unsigned long long)lr,
        image ? image : "", lrImage ? lrImage : "",
        base, lrBase);
    if (length <= 0) return;

    size_t toWrite = (size_t)(length < (int)sizeof(buffer) ? length : (int)sizeof(buffer));
    int fd = open(gCrashMarkerPathC, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return;
    ssize_t ignored = write(fd, buffer, toWrite);
    (void)ignored;
    close(fd);
}

static void AFSignalHandler(int sig, siginfo_t *info, void *context) {
    if (gHandlingCrash) {
        signal(sig, SIG_DFL);
        raise(sig);
        _exit(128 + sig);
    }
    gHandlingCrash = 1;

    if (!gMarkerWritten) {
        gMarkerWritten = 1;
        AFWriteSignalMarker(sig, context);
    }

    if (sig > 0 && sig < NSIG) {
        struct sigaction previous = gOldActions[sig];
        if ((previous.sa_flags & SA_SIGINFO) && previous.sa_sigaction) {
            previous.sa_sigaction(sig, info, context);
        } else if (previous.sa_handler &&
                   previous.sa_handler != SIG_DFL &&
                   previous.sa_handler != SIG_IGN) {
            previous.sa_handler(sig);
        }
    }

    signal(sig, SIG_DFL);
    raise(sig);
    _exit(128 + sig);
}

static NSString *AFModuleNameFromStackLine(NSString *line) {
    NSArray *tokens = [line componentsSeparatedByCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *nonEmpty = [NSMutableArray array];
    for (NSString *token in tokens) {
        if (token.length) [nonEmpty addObject:token];
    }
    if (nonEmpty.count >= 2) return nonEmpty[1];
    return nil;
}

static void AFExceptionHandler(NSException *exception) {
    if (!gMarkerWritten) {
        gMarkerWritten = 1;
        @try {
            NSSet *tweakBases = nil;
            @try {
                NSDictionary<NSString *, AFTweakInfo *> *map = AFScanTweakMap();
                tweakBases = [NSSet setWithArray:map.allKeys];
            } @catch (NSException *ignored) {
                (void)ignored;
            }

            NSString *base = @"";
            NSMutableArray<NSString *> *frames = [NSMutableArray array];
            NSArray<NSString *> *symbols = [NSThread callStackSymbols];
            for (NSString *line in symbols) {
                NSString *module = AFModuleNameFromStackLine(line);
                if (!module.length) continue;
                if (AFIsSelfTweakBase(module)) continue;

                BOOL isTweak = tweakBases ? [tweakBases containsObject:module] : NO;
                if (!isTweak) {
                    NSString *lower = module.lowercaseString;
                    BOOL system = [lower hasPrefix:@"lib"] || [lower hasPrefix:@"uikit"] ||
                                  [lower hasPrefix:@"foundation"] || [lower hasPrefix:@"core"] ||
                                  [lower hasPrefix:@"springboard"] || [lower hasPrefix:@"frontboard"] ||
                                  [lower hasPrefix:@"backboard"] || [lower hasPrefix:@"graphics"] ||
                                  [lower hasPrefix:@"quartz"] || [lower hasPrefix:@"dyld"] ||
                                  [lower hasPrefix:@"swift"];
                    if (system) continue;
                    if (!tweakBases) isTweak = YES;
                }
                if (!isTweak) continue;

                if (base.length == 0) base = module;
                if (frames.count < 12) [frames addObject:line];
            }

            NSString *reason = exception.reason ?: @"";
            reason = [reason stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            if (reason.length > 800) reason = [reason substringToIndex:800];

            NSMutableString *text = [NSMutableString string];
            [text appendFormat:@"time=%lld\nkind=exception\nname=%@\nreason=%@\nbase=%@\n",
             (long long)time(NULL), exception.name ?: @"", reason, base];
            if (frames.count) {
                [text appendFormat:@"frames=%@\n", [frames componentsJoinedByString:@"|"]];
            }
            [text writeToFile:AFCrashMarkerPath() atomically:YES
                     encoding:NSUTF8StringEncoding error:NULL];
            chmod(AFCrashMarkerPath().fileSystemRepresentation, 0644);
        } @catch (NSException *ignored) {
            (void)ignored;
        }
    }

    NSSetUncaughtExceptionHandler(NULL);
    if (gPreviousExceptionHandler && gPreviousExceptionHandler != AFExceptionHandler) {
        gPreviousExceptionHandler(exception);
    }
    for (size_t i = 0; i < kAFSignalCount; i++) {
        signal(kAFSignals[i], SIG_DFL);
    }
    abort();
}

void AFInstallCrashGuard(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        AFPrepareImageTable();
        gPreviousExceptionHandler = NSGetUncaughtExceptionHandler();
        NSSetUncaughtExceptionHandler(&AFExceptionHandler);

        void *alternateStack = malloc(64 * 1024);
        if (alternateStack) {
            stack_t stack = {0};
            stack.ss_sp = alternateStack;
            stack.ss_size = 64 * 1024;
            stack.ss_flags = 0;
            sigaltstack(&stack, NULL);
        }

        for (size_t i = 0; i < kAFSignalCount; i++) {
            int signalNumber = kAFSignals[i];
            struct sigaction action;
            memset(&action, 0, sizeof(action));
            action.sa_sigaction = AFSignalHandler;
            action.sa_flags = SA_SIGINFO | SA_ONSTACK;
            sigemptyset(&action.sa_mask);
            sigaction(signalNumber, &action, &gOldActions[signalNumber]);
        }
    });
}

// ===================== tweak/AFHangWatchdog.m =====================
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

// ===================== tweak/AFBridge.m =====================
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

// ===================== tweak/AFUI.m =====================
static UIWindow *gAlertWindow = nil;
static UIAlertController *gAlertController = nil;
static UIWindow *gPreviousKeyWindow = nil;
static NSDictionary *gPendingNotice = nil;

static void AFShowNoticeOnMain(NSDictionary *notice);

static void AFFinishAlert(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gAlertController = nil;
        UIWindow *window = gAlertWindow;
        gAlertWindow = nil;
        if (window) {
            window.hidden = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [window resignKeyWindow];
                if (gPreviousKeyWindow) [gPreviousKeyWindow makeKeyWindow];
                gPreviousKeyWindow = nil;
                if (gPendingNotice) {
                    NSDictionary *pending = gPendingNotice;
                    gPendingNotice = nil;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{
                        AFShowNoticeOnMain(pending);
                    });
                }
            });
        }
    });
}

static BOOL AFPresentAlert(NSString *title, NSString *message,
                           NSArray<UIAlertAction *> *actions) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            AFPresentAlert(title, message, actions);
        });
        return NO;
    }
    if (gAlertController) return NO;

    UIApplication *application = [UIApplication sharedApplication];
    if (!application) return NO;

    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UISceneActivationState state = scene.activationState;
            if (state == UISceneActivationStateForegroundActive ||
                state == UISceneActivationStateForegroundInactive) {
                window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
                break;
            }
        }
    }
    if (!window) {
        window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }

    gPreviousKeyWindow = application.keyWindow;
    window.windowLevel = UIWindowLevelAlert + 100.0;
    window.backgroundColor = [UIColor clearColor];
    window.rootViewController = [UIViewController new];
    window.hidden = NO;
    [window makeKeyAndVisible];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    for (UIAlertAction *action in actions) {
        [alert addAction:action];
    }

    gAlertWindow = window;
    gAlertController = alert;

    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    return YES;
}

static void AFShowNoticeOnMain(NSDictionary *notice) {
    if (![notice isKindOfClass:[NSDictionary class]]) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            AFShowNoticeOnMain(notice);
        });
        return;
    }
    if (gAlertController) {
        gPendingNotice = notice;
        return;
    }

    NSArray *items = [notice[@"items"] isKindOfClass:[NSArray class]] ? notice[@"items"] : @[];
    BOOL safeAll = [notice[@"safeAll"] boolValue];
    NSString *title = safeAll ? @"Auto Fix - Chế độ an toàn" : @"Auto Fix Tweak";

    NSMutableString *message = [NSMutableString string];
    NSString *description = notice[@"message"];
    if ([description isKindOfClass:[NSString class]] && description.length) {
        [message appendString:description];
    }

    if (items.count) {
        [message appendString:@"\n\nTweak đã được xử lý:"];
        NSUInteger shown = 0;
        for (NSDictionary *item in items) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            if (shown >= 6) break;
            NSString *base = item[@"base"];
            NSString *package = item[@"package"];
            NSString *detail = item[@"detail"];
            if (![base isKindOfClass:[NSString class]] || base.length == 0) continue;
            if ([package isKindOfClass:[NSString class]] && package.length) {
                [message appendFormat:@"\n- %@ (%@)", base, package];
            } else {
                [message appendFormat:@"\n- %@", base];
            }
            if ([detail isKindOfClass:[NSString class]] && detail.length) {
                [message appendFormat:@": %@", detail];
            }
            shown++;
        }
        if (items.count > shown) {
            [message appendFormat:@"\n... và %lu tweak khác",
             (unsigned long)(items.count - shown)];
        }
    }

    NSMutableArray<UIAlertAction *> *actions = [NSMutableArray array];
    if (items.count) {
        NSString *enableTitle = safeAll ? @"Bật lại tất cả" : @"Hoàn tác & Respring";
        [actions addObject:[UIAlertAction actionWithTitle:enableTitle
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
            (void)action;
            for (NSDictionary *item in items) {
                NSString *base = item[@"base"];
                if (![base isKindOfClass:[NSString class]] || base.length == 0) continue;
                AFQueueRequest([@"enable__" stringByAppendingString:base], @{@"base": base});
            }
            AFQueueRequest(@"ack", nil);
            AFQueueRequest(@"respring", nil);
            AFFinishAlert();
        }]];

        [actions addObject:[UIAlertAction actionWithTitle:@"Đóng"
                                                   style:UIAlertActionStyleCancel
                                                 handler:^(UIAlertAction *action) {
            (void)action;
            AFQueueRequest(@"ack", nil);
            AFFinishAlert();
        }]];
    } else {
        [actions addObject:[UIAlertAction actionWithTitle:@"Đóng"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
            (void)action;
            AFQueueRequest(@"ack", nil);
            AFFinishAlert();
        }]];
    }

    if (!AFPresentAlert(title, message, actions)) {
        gPendingNotice = notice;
    }
}

void AFShowNotice(NSDictionary *notice) {
    if (![notice isKindOfClass:[NSDictionary class]]) return;
    if ([NSThread isMainThread]) {
        AFShowNoticeOnMain(notice);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            AFShowNoticeOnMain(notice);
        });
    }
}

// ===================== tweak/AFCameraGuard.m =====================
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

// ===================== tweak/AFCameraRepair.m =====================
/* Cờ chống đệ quy: khi lớp sửa đang tự liệt kê thiết bị, các hook của chính
   Auto Fix phải gọi thẳng implementation gốc thay vì sửa lại kết quả. */
static _Thread_local BOOL tAFRepairGuard;
static volatile BOOL gCameraRepairEnabled = NO;

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

// ===================== tweak/AFCameraRepairHooks.xm =====================
/* Các hook dưới đây chỉ hoạt động trong tiến trình Camera/FaceTime.
   Mục tiêu: giữ tweak gây lỗi tiếp tục chạy, chỉ sửa phần camera bị nó can thiệp. */

%hook AVCaptureDevice

+ (AVCaptureDevice *)defaultDeviceWithPosition:(AVCaptureDevicePosition)position {
    AVCaptureDevice *device = %orig;
    if (device || position != AVCaptureDevicePositionFront) return device;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return device;
    AVCaptureDevice *fallback = AFFrontCameraFallbackDevice();
    if (fallback) {
        AFLog(@"CameraRepair: khôi phục defaultDeviceWithPosition:Front");
        return fallback;
    }
    return device;
}

+ (AVCaptureDevice *)defaultDeviceWithDeviceType:(AVCaptureDeviceType)deviceType
                                       mediaType:(AVMediaType)mediaType
                                        position:(AVCaptureDevicePosition)position {
    AVCaptureDevice *device = %orig;
    if (device || position != AVCaptureDevicePositionFront) return device;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return device;
    AVCaptureDevice *fallback = AFFrontCameraFallbackDevice();
    if (fallback) {
        AFLog(@"CameraRepair: khôi phục defaultDeviceWithDeviceType position:Front");
        return fallback;
    }
    return device;
}

+ (NSArray *)devicesWithMediaType:(AVMediaType)mediaType {
    NSArray *devices = %orig;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return devices;
    return AFRepairDeviceList(devices);
}

- (NSArray *)formats {
    NSArray *formats = %orig;
    if (formats.count > 0 || self.position != AVCaptureDevicePositionFront) return formats;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return formats;

    AVCaptureDevice *fallback = AFFrontCameraFallbackDevice();
    if (fallback && fallback != self) {
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
            AFLog(@"CameraRepair: khôi phục %lu format camera trước",
                  (unsigned long)altFormats.count);
            return altFormats;
        }
    }

    AVCaptureDeviceFormat *active = self.activeFormat;
    if (active) {
        AFLog(@"CameraRepair: dùng activeFormat cho camera trước");
        return @[active];
    }
    return formats;
}

%end

%hook AVCaptureDeviceDiscoverySession

- (NSArray *)devices {
    NSArray *devices = %orig;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return devices;
    return AFRepairDeviceList(devices);
}

%end

%hook AVCaptureDeviceInput

- (instancetype)initWithDevice:(AVCaptureDevice *)device error:(NSError **)error {
    id result = %orig;
    if (result || !device || device.position != AVCaptureDevicePositionFront) return result;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return result;

    AVCaptureDevice *fallback = AFFrontCameraFallbackDevice();
    if (!fallback || fallback == device) return result;

    BOOL previous = AFInCameraRepair();
    AFSetCameraRepairGuard(YES);
    id retry = [[AVCaptureDeviceInput alloc] initWithDevice:fallback error:error];
    AFSetCameraRepairGuard(previous);

    if (retry) {
        AFLog(@"CameraRepair: tạo lại input camera trước bằng thiết bị dự phòng");
        return retry;
    }
    return result;
}

%end

%hook AVCaptureSession

- (void)addInput:(AVCaptureInput *)input {
    @try {
        %orig;
    } @catch (NSException *exception) {
        AFLog(@"CameraRepair: addInput ném lỗi %@", exception.reason ?: exception.name);
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
            %orig(fresh);
            AFLog(@"CameraRepair: thêm lại input camera trước sau lỗi");
        } @catch (NSException *second) {
            AFLog(@"CameraRepair: vẫn không thêm được input camera trước: %@",
                  second.reason ?: second.name);
        }
    }
}

- (void)addOutput:(AVCaptureOutput *)output {
    @try {
        %orig;
    } @catch (NSException *exception) {
        AFLog(@"CameraRepair: addOutput ném lỗi %@", exception.reason ?: exception.name);
    }
}

- (void)startRunning {
    @try {
        %orig;
    } @catch (NSException *exception) {
        AFLog(@"CameraRepair: startRunning ném lỗi %@", exception.reason ?: exception.name);
    }
}

%end

%hook AVCaptureDevice

- (BOOL)lockForConfiguration:(NSError **)error {
    @try {
        return %orig;
    } @catch (NSException *exception) {
        AFLog(@"CameraRepair: lockForConfiguration ném lỗi %@",
              exception.reason ?: exception.name);
        if (error) {
            *error = [NSError errorWithDomain:@"AutoFixTweak.CameraRepair"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    exception.reason ?: @"camera repair"}];
        }
        return NO;
    }
}

%end

%hook AVCaptureVideoPreviewLayer

- (void)setSession:(AVCaptureSession *)session {
    @try {
        %orig;
    } @catch (NSException *exception) {
        AFLog(@"CameraRepair: preview setSession ném lỗi %@",
              exception.reason ?: exception.name);
    }
}

%end

// ===================== Tweak.xm =====================
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

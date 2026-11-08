#import "shared/AFCore.h"

#import <sys/stat.h>
#import <sys/types.h>
#import <unistd.h>
#import <fcntl.h>
#import <pthread.h>
#import <time.h>
#import <math.h>

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

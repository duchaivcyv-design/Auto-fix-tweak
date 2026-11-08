#import "shared/AFTweakScanner.h"

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

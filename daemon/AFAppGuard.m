#import "daemon/AFAppGuard.h"
#import "daemon/AFProcess.h"
#import "daemon/AFQuarantine.h"
#import "shared/AFCore.h"
#import "shared/AFTweakScanner.h"
#import "shared/AFCrashParser.h"

#import <unistd.h>
#import <pthread.h>

static NSDictionary<NSString *, NSString *> *gProcessBundleMap = nil;
static NSTimeInterval gProcessBundleMapTime = 0;

static NSLock *AFAppGuardLock(void) {
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSLock new]; });
    return lock;
}

static NSMutableArray *AFMutableArrayForKey(NSMutableDictionary *state, NSString *key) {
    id value = state[key];
    return [value isKindOfClass:[NSArray class]] ? [value mutableCopy]
                                                 : [NSMutableArray array];
}

static NSMutableDictionary *AFMutableDictForKey(NSMutableDictionary *state, NSString *key) {
    id value = state[key];
    return [value isKindOfClass:[NSDictionary class]] ? [value mutableCopy]
                                                      : [NSMutableDictionary dictionary];
}

static void AFAddApplicationAtPath(NSString *appPath, NSMutableDictionary *map) {
    if (appPath.length == 0) return;
    NSString *name = appPath.lastPathComponent.stringByDeletingPathExtension;
    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    if (![info isKindOfClass:[NSDictionary class]]) return;

    NSString *bundle = info[@"CFBundleIdentifier"];
    if (![bundle isKindOfClass:[NSString class]] || bundle.length == 0) return;

    NSString *executable = info[@"CFBundleExecutable"];
    if ([executable isKindOfClass:[NSString class]] && executable.length) {
        map[executable] = bundle;
    }
    if (name.length) map[name] = bundle;
}

static void AFRefreshProcessBundleMap(void) {
    NSTimeInterval now = AFNow();
    if (gProcessBundleMap && now - gProcessBundleMapTime < 1800) return;

    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    NSFileManager *fm = [NSFileManager defaultManager];

    for (NSString *base in @[@"/Applications", @"/System/Applications", @"/var/jb/Applications"]) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:base error:NULL];
        for (NSString *name in contents) {
            if (![name hasSuffix:@".app"]) continue;
            AFAddApplicationAtPath([base stringByAppendingPathComponent:name], map);
        }
    }

    NSString *containers = @"/var/containers/Bundle/Application";
    NSArray *uuids = [fm contentsOfDirectoryAtPath:containers error:NULL];
    for (NSString *uuid in uuids) {
        NSString *container = [containers stringByAppendingPathComponent:uuid];
        NSArray *apps = [fm contentsOfDirectoryAtPath:container error:NULL];
        for (NSString *name in apps) {
            if (![name hasSuffix:@".app"]) continue;
            AFAddApplicationAtPath([container stringByAppendingPathComponent:name], map);
        }
    }

    gProcessBundleMap = [map copy];
    gProcessBundleMapTime = now;
}

static NSString *AFBundleIDForProcess(NSString *processName) {
    if (processName.length == 0) return nil;

    NSLock *lock = AFAppGuardLock();
    [lock lock];
    AFRefreshProcessBundleMap();
    NSString *bundle = gProcessBundleMap[processName];
    if (!bundle) {
        for (NSString *key in gProcessBundleMap) {
            if ([key caseInsensitiveCompare:processName] == NSOrderedSame) {
                bundle = gProcessBundleMap[key];
                break;
            }
        }
    }
    [lock unlock];
    return bundle;
}

NSArray<NSDictionary *> *AFAppExclusionRecords(NSDictionary *state) {
    id records = state[@"exclusions"];
    return [records isKindOfClass:[NSArray class]] ? records : @[];
}

static BOOL AFExclusionPlistPathSafe(NSString *path, NSString *base) {
    if (![path isKindOfClass:[NSString class]] || path.length == 0) return NO;
    if (![path hasPrefix:@"/"] || [path containsString:@"/../"]) return NO;
    if ([path hasSuffix:@".autofixdisabled"]) return NO;
    if (![path hasSuffix:@".plist"]) return NO;

    NSString *expected = [base stringByAppendingString:@".plist"];
    if ([path.lastPathComponent caseInsensitiveCompare:expected] != NSOrderedSame) {
        return NO;
    }

    NSString *dir = path.stringByDeletingLastPathComponent;
    for (NSString *allowed in AFDynamicLibraryDirs()) {
        if ([dir isEqualToString:allowed]) return YES;
    }
    return NO;
}

static BOOL AFBundleLookValid(NSString *bundle) {
    if (![bundle isKindOfClass:[NSString class]] || bundle.length == 0 ||
        bundle.length > 200) {
        return NO;
    }
    if ([bundle containsString:@"/"] || [bundle containsString:@".."] ||
        [bundle containsString:@"\n"]) {
        return NO;
    }
    return YES;
}

NSUInteger AFSanitizeExclusionRecords(NSMutableDictionary *state) {
    NSMutableArray<NSDictionary *> *kept = [NSMutableArray array];
    for (NSDictionary *record in AFAppExclusionRecords(state)) {
        if (![record isKindOfClass:[NSDictionary class]]) continue;
        NSString *base = record[@"base"];
        NSString *bundle = record[@"bundle"];
        NSString *plist = record[@"plist"];
        if (![base isKindOfClass:[NSString class]] || base.length == 0 ||
            base.length > 200 || [base containsString:@"/"]) {
            continue;
        }
        if (!AFBundleLookValid(bundle) || !AFExclusionPlistPathSafe(plist, base)) {
            AFLogTo(AFDaemonLogPath(), @"Bỏ bản ghi loại trừ không hợp lệ: %@", base);
            continue;
        }
        [kept addObject:record];
    }
    state[@"exclusions"] = kept;
    return kept.count;
}

static BOOL AFApplyAppExclusion(NSString *base,
                                NSString *bundle,
                                NSString *processName,
                                NSString *reason,
                                NSMutableDictionary *state,
                                NSString **errorOut) {
    if (base.length == 0 || !AFBundleLookValid(bundle)) {
        if (errorOut) *errorOut = @"thiếu tên tweak hoặc bundle id";
        return NO;
    }

    for (NSDictionary *record in AFAppExclusionRecords(state)) {
        NSString *recordBase = record[@"base"];
        NSString *recordBundle = record[@"bundle"];
        if ([recordBase isKindOfClass:[NSString class]] &&
            [recordBase caseInsensitiveCompare:base] == NSOrderedSame &&
            [recordBundle isKindOfClass:[NSString class]] &&
            [recordBundle caseInsensitiveCompare:bundle] == NSOrderedSame) {
            return NO;
        }
    }

    AFTweakInfo *info = AFTweakInfoForBase(base);
    if (!info || !info.enabled || info.plistPath.length == 0) {
        if (errorOut) *errorOut = @"không tìm thấy plist của tweak đang bật";
        return NO;
    }
    if (AFIsSelfTweakBase(info.base) || AFIsWhitelistedTweakBase(info.base)) {
        if (errorOut) *errorOut = @"tweak nằm trong danh sách bảo vệ";
        return NO;
    }

    NSData *data = [NSData dataWithContentsOfFile:info.plistPath options:0 error:NULL];
    if (!data) {
        if (errorOut) *errorOut = @"không đọc được plist";
        return NO;
    }
    NSError *plistError = nil;
    id parsed = [NSPropertyListSerialization propertyListWithData:data
                                                          options:NSPropertyListMutableContainers
                                                           format:NULL
                                                            error:&plistError];
    NSMutableDictionary *root = [parsed isKindOfClass:[NSDictionary class]]
        ? [parsed mutableCopy] : nil;
    if (!root) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"plist không hợp lệ: %@",
                                   plistError.localizedDescription ?: @"?"];
        return NO;
    }

    BOOL createdExclude = NO;
    BOOL createdBundles = NO;
    NSMutableDictionary *exclude = nil;
    id existingExclude = root[@"Exclude"];
    if ([existingExclude isKindOfClass:[NSDictionary class]]) {
        exclude = [existingExclude mutableCopy];
    } else {
        exclude = [NSMutableDictionary dictionary];
        createdExclude = YES;
    }

    NSMutableArray<NSString *> *bundles = nil;
    id existingBundles = exclude[@"Bundles"];
    if ([existingBundles isKindOfClass:[NSArray class]]) {
        bundles = [existingBundles mutableCopy];
    } else {
        bundles = [NSMutableArray array];
        createdBundles = YES;
    }

    BOOL alreadyPresent = NO;
    for (NSString *value in bundles) {
        if ([value isKindOfClass:[NSString class]] &&
            [value caseInsensitiveCompare:bundle] == NSOrderedSame) {
            alreadyPresent = YES;
            break;
        }
    }
    if (!alreadyPresent) [bundles addObject:bundle];

    exclude[@"Bundles"] = bundles;
    root[@"Exclude"] = exclude;

    if (!alreadyPresent && !AFWritePlistSecure(info.plistPath, root)) {
        if (errorOut) *errorOut = @"không ghi được plist";
        return NO;
    }

    NSMutableArray *records = AFMutableArrayForKey(state, @"exclusions");
    [records addObject:@{
        @"base": info.base,
        @"package": info.package ?: @"",
        @"bundle": bundle,
        @"proc": processName ?: @"",
        @"plist": info.plistPath,
        @"reason": reason ?: @"",
        @"time": @(AFNow()),
        @"createdExclude": @(createdExclude),
        @"createdBundles": @(createdBundles)
    }];
    state[@"exclusions"] = records;

    AFLogTo(AFDaemonLogPath(), @"Loại trừ %@ khỏi app %@ (%@) - %@",
            info.base, processName ?: bundle, bundle, reason ?: @"");
    return YES;
}

NSUInteger AFRemoveAppExclusions(NSString *base,
                                 NSMutableDictionary *state,
                                 NSString **errorOut) {
    (void)errorOut;
    NSArray<NSDictionary *> *records = AFAppExclusionRecords(state);
    NSMutableArray<NSDictionary *> *kept = [NSMutableArray array];
    NSUInteger removed = 0;

    for (NSDictionary *record in records) {
        NSString *recordBase = record[@"base"];
        if (![recordBase isKindOfClass:[NSString class]]) continue;
        if (base.length &&
            [recordBase caseInsensitiveCompare:base] != NSOrderedSame) {
            [kept addObject:record];
            continue;
        }

        NSString *plist = record[@"plist"];
        NSString *bundle = record[@"bundle"];
        if (!AFFileExists(plist)) {
            removed++;
            continue;
        }

        NSData *data = [NSData dataWithContentsOfFile:plist options:0 error:NULL];
        NSError *plistError = nil;
        id parsed = data ? [NSPropertyListSerialization propertyListWithData:data
                                                                    options:NSPropertyListMutableContainers
                                                                     format:NULL
                                                                      error:&plistError] : nil;
        NSMutableDictionary *root = [parsed isKindOfClass:[NSDictionary class]]
            ? [parsed mutableCopy] : nil;
        if (!root) {
            AFLogTo(AFDaemonLogPath(), @"Không hoàn tác được loại trừ %@: plist lỗi",
                    recordBase);
            [kept addObject:record];
            continue;
        }

        id existingExclude = root[@"Exclude"];
        if ([existingExclude isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *exclude = [existingExclude mutableCopy];
            id existingBundles = exclude[@"Bundles"];
            if ([existingBundles isKindOfClass:[NSArray class]]) {
                NSMutableArray *bundles = [NSMutableArray array];
                for (id value in existingBundles) {
                    if (![value isKindOfClass:[NSString class]] ||
                        [value caseInsensitiveCompare:bundle] != NSOrderedSame) {
                        [bundles addObject:value];
                    }
                }
                if (bundles.count) {
                    exclude[@"Bundles"] = bundles;
                } else {
                    [exclude removeObjectForKey:@"Bundles"];
                }
            }
            if ([record[@"createdExclude"] boolValue] && exclude.count == 0) {
                [root removeObjectForKey:@"Exclude"];
            } else {
                root[@"Exclude"] = exclude;
            }
            if (!AFWritePlistSecure(plist, root)) {
                AFLogTo(AFDaemonLogPath(), @"Không ghi được plist khi hoàn tác: %@", plist);
                [kept addObject:record];
                continue;
            }
        }

        removed++;
        AFLogTo(AFDaemonLogPath(), @"Đã bỏ loại trừ %@ khỏi %@",
                recordBase, bundle ?: @"?");
    }

    state[@"exclusions"] = kept;
    return removed;
}

static void AFPublishAppNotice(NSMutableDictionary *state, NSString *message) {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];

    for (NSDictionary *record in AFQuarantineRecords(state)) {
        NSString *base = record[@"base"];
        if (![base isKindOfClass:[NSString class]] || base.length == 0) continue;
        NSString *reason = [record[@"reason"] isKindOfClass:[NSString class]]
            ? record[@"reason"] : @"";
        [items addObject:@{
            @"base": base,
            @"package": [record[@"package"] isKindOfClass:[NSString class]]
                ? record[@"package"] : @"",
            @"reason": reason,
            @"kind": @"quarantine",
            @"detail": reason.length ? reason : @"đã tạm tắt"
        }];
    }

    for (NSDictionary *record in AFAppExclusionRecords(state)) {
        NSString *base = record[@"base"];
        if (![base isKindOfClass:[NSString class]] || base.length == 0) continue;
        NSString *label = [record[@"proc"] isKindOfClass:[NSString class]] &&
                          [record[@"proc"] length] ? record[@"proc"] : record[@"bundle"];
        if (![label isKindOfClass:[NSString class]]) label = @"app";
        [items addObject:@{
            @"base": base,
            @"package": [record[@"package"] isKindOfClass:[NSString class]]
                ? record[@"package"] : @"",
            @"reason": [record[@"reason"] isKindOfClass:[NSString class]]
                ? record[@"reason"] : @"",
            @"kind": @"exclude",
            @"target": label,
            @"detail": [NSString stringWithFormat:@"loại trừ khỏi %@", label]
        }];
    }

    if (items.count == 0) return;

    NSTimeInterval now = AFNow();
    state[@"notice"] = @{
        @"id": @((long long)(now * 1000.0)),
        @"time": @(now),
        @"kind": @"app",
        @"message": message ?: @"Auto Fix đã xử lý tweak gây lỗi app.",
        @"items": items,
        @"safeAll": @NO,
        @"recoveryCount": @([state[@"recoveryCount"] unsignedIntegerValue])
    };
}

static NSDictionary *AFParseMarkerFile(NSString *path) {
    if (path.length == 0) return nil;
    NSString *text = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding error:NULL];
    if (text.length == 0) return nil;
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSString *line in [text componentsSeparatedByCharactersInSet:
                            [NSCharacterSet newlineCharacterSet]]) {
        NSRange separator = [line rangeOfString:@"="];
        if (separator.location == NSNotFound) continue;
        NSString *key = [line substringToIndex:separator.location];
        NSString *value = [line substringFromIndex:separator.location + 1];
        if (key.length) dict[key] = value;
    }
    double time = [dict[@"time"] doubleValue];
    if (time <= 0) {
        NSDictionary *attrs = [[NSFileManager defaultManager]
            attributesOfItemAtPath:path error:NULL];
        NSDate *modified = attrs[NSFileModificationDate];
        if (!modified) return nil;
        dict[@"time"] = @(modified.timeIntervalSince1970);
    }
    return dict;
}

static NSDictionary *AFReadCameraMarker(void) {
    static NSString *containerMarker = nil;
    static NSTimeInterval containerScanTime = 0;

    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithObject:AFCameraMarkerPath()];
    NSTimeInterval now = AFNow();

    BOOL cachedMissing = containerMarker.length > 0 && !AFFileExists(containerMarker);
    BOOL needScan = cachedMissing || (containerMarker.length == 0) ||
                    (now - containerScanTime > 1800);
    if (needScan) {
        containerScanTime = now;
        containerMarker = nil;
        NSString *containers = @"/var/mobile/Containers/Data/Application";
        NSArray *uuids = [[NSFileManager defaultManager]
                          contentsOfDirectoryAtPath:containers error:NULL];
        for (NSString *uuid in uuids) {
            if (![uuid isKindOfClass:[NSString class]] || uuid.length == 0) continue;
            NSString *candidate = [[[containers stringByAppendingPathComponent:uuid]
                stringByAppendingPathComponent:@"tmp"]
                stringByAppendingPathComponent:@"autofix_camera.txt"];
            if (AFFileExists(candidate)) {
                containerMarker = candidate;
                break;
            }
        }
    }
    if (containerMarker.length) [paths addObject:containerMarker];

    NSDictionary *best = nil;
    double bestTime = 0;
    for (NSString *path in paths) {
        NSDictionary *marker = AFParseMarkerFile(path);
        if (!marker) continue;
        double time = [marker[@"time"] doubleValue];
        if (time <= 0 || time <= bestTime) continue;
        best = marker;
        bestTime = time;
    }
    return best;
}

static BOOL AFCameraRelated(NSString *bundle, NSString *processName) {
    NSString *bundleLower = [bundle isKindOfClass:[NSString class]] ? bundle.lowercaseString : @"";
    NSString *processLower = [processName isKindOfClass:[NSString class]] ?
        processName.lowercaseString : @"";
    if ([bundleLower isEqualToString:@"com.apple.camera"] ||
        [bundleLower hasPrefix:@"com.apple.camera."]) return YES;
    if ([bundleLower containsString:@"facetime"]) return YES;
    if ([processLower containsString:@"camera"]) return YES;
    if ([processLower containsString:@"facetime"]) return YES;
    return NO;
}

static NSArray<AFTweakInfo *> *AFUniqueCameraTweaks(NSArray<NSString *> *bases,
                                                    NSDictionary *state) {
    NSMutableArray<AFTweakInfo *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *base in bases) {
        if (![base isKindOfClass:[NSString class]] || base.length == 0) continue;
        if (AFIsSelfTweakBase(base) || AFIsWhitelistedTweakBase(base)) continue;
        AFTweakInfo *info = AFTweakInfoForBase(base);
        if (!info || !info.enabled) continue;
        if (AFIsTweakQuarantined(info.base, state)) continue;
        NSString *key = info.base.lowercaseString;
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        [result addObject:info];
    }
    return result;
}

static NSArray<AFTweakInfo *> *AFOrderCameraCandidates(NSArray<AFTweakInfo *> *items,
                                                       NSString *bundle,
                                                       NSString *executable,
                                                       NSString *preferredBase) {
    NSMutableDictionary<NSString *, NSNumber *> *targets = [NSMutableDictionary dictionary];
    for (AFTweakInfo *info in items) {
        BOOL targetsBundle = AFTweakInfoExplicitlyTargetsBundle(info, bundle, executable);
        targets[info.base.lowercaseString] = @(targetsBundle);
    }

    return [items sortedArrayUsingComparator:^NSComparisonResult(AFTweakInfo *a, AFTweakInfo *b) {
        BOOL preferredA = preferredBase.length > 0 &&
            [a.base caseInsensitiveCompare:preferredBase] == NSOrderedSame;
        BOOL preferredB = preferredBase.length > 0 &&
            [b.base caseInsensitiveCompare:preferredBase] == NSOrderedSame;
        if (preferredA != preferredB) return preferredA ? NSOrderedAscending : NSOrderedDescending;

        BOOL targetA = [targets[a.base.lowercaseString] boolValue];
        BOOL targetB = [targets[b.base.lowercaseString] boolValue];
        if (targetA != targetB) return targetA ? NSOrderedAscending : NSOrderedDescending;

        if (a.installTime == b.installTime) {
            return [a.base caseInsensitiveCompare:b.base];
        }
        return a.installTime > b.installTime ? NSOrderedAscending : NSOrderedDescending;
    }];
}

static NSArray<AFTweakInfo *> *AFUntriedCameraTweaks(NSArray<AFTweakInfo *> *ordered,
                                                     NSMutableDictionary *state,
                                                     NSTimeInterval now) {
    NSMutableDictionary *tried = AFMutableDictForKey(state, @"cameraTried");
    NSMutableDictionary *pruned = [NSMutableDictionary dictionary];
    for (NSString *key in tried) {
        double time = [tried[key] doubleValue];
        if (now - time <= 6 * 3600) pruned[key] = tried[key];
    }
    state[@"cameraTried"] = pruned;

    NSMutableArray<AFTweakInfo *> *result = [NSMutableArray array];
    for (AFTweakInfo *info in ordered) {
        if (pruned[info.base.lowercaseString]) continue;
        [result addObject:info];
    }
    return result;
}

static void AFTagCameraQuarantine(NSString *base, NSMutableDictionary *state) {
    if (![base isKindOfClass:[NSString class]] || base.length == 0) return;
    NSMutableArray *records = [NSMutableArray array];
    for (NSDictionary *record in AFQuarantineRecords(state)) {
        NSMutableDictionary *copy = [record mutableCopy];
        NSString *recordBase = copy[@"base"];
        if ([recordBase isKindOfClass:[NSString class]] &&
            [recordBase caseInsensitiveCompare:base] == NSOrderedSame) {
            copy[@"camera"] = @YES;
        }
        [records addObject:copy];
    }
    state[@"quarantine"] = records;
}

static AFTweakInfo *AFQuarantineCameraTweak(AFTweakInfo *tweak,
                                            NSString *reason,
                                            NSString *processName,
                                            NSMutableDictionary *state) {
    if (!tweak || AFIsTweakQuarantined(tweak.base, state)) return nil;
    NSString *error = nil;
    if (!AFDisableTweak(tweak, reason, state, &error)) {
        AFLogTo(AFDaemonLogPath(), @"Camera: không tắt được %@: %@",
                tweak.base, error ?: @"?");
        return nil;
    }

    AFTagCameraQuarantine(tweak.base, state);
    state[@"cameraFailures"] = @0;

    NSMutableDictionary *tried = AFMutableDictForKey(state, @"cameraTried");
    tried[tweak.base.lowercaseString] = @(AFNow());
    state[@"cameraTried"] = tried;

    NSUInteger killed = AFKillProcessNamed(processName.length ? processName : @"Camera");
    AFLogTo(AFDaemonLogPath(), @"Camera: tạm tắt %@ (%@), kill %@=%lu",
            tweak.base, tweak.package ?: @"?", processName ?: @"Camera",
            (unsigned long)killed);
    return tweak;
}

static NSArray<NSString *> *AFCameraMarkerTick(NSDictionary *config,
                                               NSMutableDictionary *state,
                                               NSTimeInterval now) {
    if (![config[@"cameraGuard"] boolValue]) return @[];
    NSDictionary *marker = AFReadCameraMarker();
    if (!marker) return @[];

    double markerTime = [marker[@"time"] doubleValue];
    if (markerTime <= 0) return @[];
    double maxAge = [config[@"cameraMarkerMaxAge"] doubleValue];
    if (maxAge <= 0) maxAge = 600;
    if (now - markerTime > maxAge) return @[];
    if (markerTime <= [state[@"cameraMarkerTime"] doubleValue]) return @[];
    state[@"cameraMarkerTime"] = @(markerTime);

    NSString *basesText = marker[@"bases"];
    NSArray<NSString *> *rawBases = basesText.length
        ? [basesText componentsSeparatedByString:@"|"] : @[];

    /* Tweak đang hook thẳng vào AVFoundation là nghi phạm mạnh nhất, ưu tiên
       trước cả tweak chỉ nằm trong danh sách image đã nạp. */
    NSString *ownersText = marker[@"hookowners"];
    NSArray<NSString *> *hookOwners = ownersText.length
        ? [ownersText componentsSeparatedByString:@"|"] : @[];

    NSMutableArray<NSString *> *allBases = [rawBases mutableCopy] ?: [NSMutableArray array];
    for (NSString *owner in hookOwners) {
        if (![owner isKindOfClass:[NSString class]] || owner.length == 0) continue;
        BOOL exists = NO;
        for (NSString *base in allBases) {
            if ([base caseInsensitiveCompare:owner] == NSOrderedSame) { exists = YES; break; }
        }
        if (!exists) [allBases addObject:owner];
    }

    NSArray<AFTweakInfo *> *unique = AFUniqueCameraTweaks(allBases, state);
    if (unique.count == 0) {
        AFLogTo(AFDaemonLogPath(),
                @"Camera: phát hiện lỗi camera trước nhưng không có tweak nào đang nạp (hookowner=%@)",
                hookOwners.firstObject ?: @"?");
        return @[];
    }

    NSArray<AFTweakInfo *> *ordered = AFOrderCameraCandidates(
        unique, marker[@"bundle"] ?: @"com.apple.camera",
        marker[@"proc"] ?: @"Camera", hookOwners.firstObject);
    NSArray<AFTweakInfo *> *untried = AFUntriedCameraTweaks(ordered, state, now);
    if (untried.count == 0) {
        AFLogTo(AFDaemonLogPath(), @"Camera: đã thử tất cả tweak đang nạp");
        return @[];
    }

    NSString *detail = marker[@"reason"] ?: @"probe";
    NSString *reason = [NSString stringWithFormat:
        @"làm camera trước không hoạt động (%@)", detail];

    /* Chế độ sửa trước: lớp camera đã cố khôi phục thiết bị mà vẫn lỗi.
       Giữ tweak chạy thêm vài phiên Camera; chỉ tạm tắt khi thất bại lặp lại. */
    if ([config[@"cameraRepair"] boolValue]) {
        NSTimeInterval window = [config[@"cameraFailureWindow"] doubleValue];
        if (window <= 0) window = 1800;
        NSUInteger disableAfter = [config[@"cameraDisableAfterFailures"] unsignedIntegerValue];
        if (disableAfter < 1) disableAfter = 3;

        double lastFailure = [state[@"cameraLastFailure"] doubleValue];
        NSUInteger failures = [state[@"cameraFailures"] unsignedIntegerValue];
        if (lastFailure <= 0 || now - lastFailure > window) failures = 0;
        failures += 1;
        state[@"cameraFailures"] = @(failures);
        state[@"cameraLastFailure"] = @(now);

        AFLogTo(AFDaemonLogPath(),
                @"Camera: lớp sửa chưa khắc phục được (lần %lu/%lu, hookowner=%@)",
                (unsigned long)failures, (unsigned long)disableAfter,
                hookOwners.firstObject ?: @"?");

        if (![config[@"cameraNeverDisable"] boolValue] && failures >= disableAfter) {
            AFTweakInfo *picked = AFQuarantineCameraTweak(
                untried.firstObject, reason, marker[@"proc"] ?: @"Camera", state);
            return picked ? @[picked.base] : @[];
        }

        if (failures == 1) {
            AFPublishAppNotice(state,
                @"Auto Fix đang sửa camera trước và vẫn giữ tweak hoạt động. Hãy thử lại Camera.");
        }
        return @[];
    }

    AFTweakInfo *picked = AFQuarantineCameraTweak(
        untried.firstObject, reason, marker[@"proc"] ?: @"Camera", state);
    return picked ? @[picked.base] : @[];
}

AFAppGuardResult AFAppGuardTick(NSDictionary *config, NSMutableDictionary *state) {
    BOOL appGuardEnabled = [config[@"appGuardEnabled"] boolValue];
    BOOL cameraGuardEnabled = [config[@"cameraGuard"] boolValue];
    if (!appGuardEnabled && !cameraGuardEnabled) return AFAppGuardResultNone;

    NSTimeInterval now = AFNow();

    BOOL changed = NO;
    BOOL needRespring = NO;
    NSUInteger addedExclusions = 0;
    NSMutableArray<NSString *> *quarantinedBases = [NSMutableArray array];
    NSMutableArray<NSString *> *cameraBases = [NSMutableArray array];

    if (cameraGuardEnabled) {
        /* Camera cần phản ứng trong vài giây, không chờ nhịp quét crash 30 giây. */
        NSTimeInterval lastCameraScan = [state[@"cameraScan"] doubleValue];
        if (lastCameraScan <= 0 || now - lastCameraScan >= 3) {
            state[@"cameraScan"] = @(now);
            NSArray<NSString *> *handled = AFCameraMarkerTick(config, state, now);
            if (handled.count) {
                [cameraBases addObjectsFromArray:handled];
                changed = YES;
            }
        }
    }

    NSTimeInterval lastScan = [state[@"appGuardScan"] doubleValue];
    if (appGuardEnabled && lastScan > 0 && now - lastScan < 30) {
        if (!changed) return AFAppGuardResultNone;
        AFPublishAppNotice(state, [NSString stringWithFormat:
            @"Auto Fix đã tạm tắt %@ vì làm camera trước không hoạt động. Mở lại Camera để kiểm tra; có thể bật lại từ thông báo.",
            [cameraBases componentsJoinedByString:@", "]]);
        return AFAppGuardResultChanged;
    }

    if (appGuardEnabled) state[@"appGuardScan"] = @(now);

    if (!appGuardEnabled) {
        if (changed) {
            AFPublishAppNotice(state, [NSString stringWithFormat:
                @"Auto Fix đã tạm tắt %@ vì làm camera trước không hoạt động. Mở lại Camera để kiểm tra; có thể bật lại từ thông báo.",
                [cameraBases componentsJoinedByString:@", "]]);
            return AFAppGuardResultChanged;
        }
        return AFAppGuardResultNone;
    }

    NSTimeInterval window = [config[@"appCrashWindow"] doubleValue];
    if (window <= 0) window = 900;
    NSUInteger threshold = [config[@"appCrashThreshold"] unsignedIntegerValue];
    if (threshold < 2) threshold = 2;
    NSUInteger escalate = [config[@"appCrashEscalate"] unsignedIntegerValue];
    if (escalate <= threshold) escalate = threshold + 1;
    NSUInteger multiThreshold = [config[@"appMultiBundleThreshold"] unsignedIntegerValue];
    if (multiThreshold < 2) multiThreshold = 3;

    NSTimeInterval maxAge = lastScan > 0 ? 6 * 3600 : 2 * 3600;
    NSArray<NSDictionary *> *candidates = AFCrashReportCandidates(maxAge);

    NSMutableDictionary *processed = AFMutableDictForKey(state, @"appProcessed");
    NSMutableArray *crashLog = AFMutableArrayForKey(state, @"appCrashLog");

    NSMutableDictionary *prunedProcessed = [NSMutableDictionary dictionary];
    for (NSString *path in processed) {
        double t = [processed[path] doubleValue];
        if (now - t <= 7 * 86400) prunedProcessed[path] = processed[path];
    }
    processed = prunedProcessed;

    NSMutableArray *prunedLog = [NSMutableArray array];
    for (NSDictionary *entry in crashLog) {
        double t = [entry[@"time"] doubleValue];
        if (now - t <= 72 * 3600) [prunedLog addObject:entry];
    }
    crashLog = prunedLog;

    NSUInteger parsed = 0;
    for (NSDictionary *candidate in candidates) {
        NSString *candidatePath = candidate[@"path"];
        NSTimeInterval candidateTime = [candidate[@"time"] doubleValue];
        if (![candidatePath isKindOfClass:[NSString class]]) continue;

        NSNumber *previous = processed[candidatePath];
        if (previous && previous.doubleValue >= candidateTime) continue;
        if (parsed >= 12) break;
        parsed++;

        AFCrashInfo *info = AFParseCrashReport(candidatePath);
        if (!info) {
            processed[candidatePath] = @(candidateTime);
            continue;
        }
        processed[info.path ?: candidatePath] = @(info.time);

        if (info.procName.length == 0 && info.bundleID.length == 0) continue;
        if ([info.procName caseInsensitiveCompare:@"SpringBoard"] == NSOrderedSame) {
            continue;
        }
        if ([info.path.lastPathComponent hasPrefix:@"SpringBoard"]) continue;

        NSString *bundle = info.bundleID.length ? info.bundleID :
                           AFBundleIDForProcess(info.procName);

        /* Camera/FaceTime: ưu tiên tắt hẳn tweak thủ phạm vì loader không hỗ trợ Exclude. */
        if (AFCameraRelated(bundle, info.procName)) {
            NSMutableArray<NSString *> *reportBases = [NSMutableArray array];
            if (info.suspectBase.length) [reportBases addObject:info.suspectBase];
            if (info.loadedTweakBases.count) {
                [reportBases addObjectsFromArray:info.loadedTweakBases];
            }
            NSArray<AFTweakInfo *> *unique = AFUniqueCameraTweaks(reportBases, state);
            NSArray<AFTweakInfo *> *ordered = AFOrderCameraCandidates(
                unique, AFBundleLookValid(bundle) ? bundle : @"com.apple.camera",
                info.procName, info.suspectBase);
            NSArray<AFTweakInfo *> *untried = AFUntriedCameraTweaks(ordered, state, now);
            AFTweakInfo *pick = untried.firstObject;
            if (pick) {
                NSString *reason = [NSString stringWithFormat:@"gây crash %@",
                    info.procName.length ? info.procName : @"Camera"];
                AFTweakInfo *done = AFQuarantineCameraTweak(
                    pick, reason,
                    info.procName.length ? info.procName : @"Camera", state);
                if (done) {
                    AFTagCameraQuarantine(done.base, state);
                    [cameraBases addObject:done.base];
                    changed = YES;
                }
            } else {
                AFLogTo(AFDaemonLogPath(),
                        @"Camera crash nhưng không chọn được tweak (loaded=%lu)",
                        (unsigned long)info.loadedTweakBases.count);
            }
            continue;
        }

        NSString *base = info.suspectBase;
        if (base.length == 0) continue;
        if (AFIsSelfTweakBase(base) || AFIsWhitelistedTweakBase(base)) continue;

        AFTweakInfo *tweak = AFTweakInfoForBase(base);
        if (!tweak || !tweak.enabled) continue;

        if (!AFBundleLookValid(bundle)) {
            AFLogTo(AFDaemonLogPath(),
                    @"Crash %@ do %@ nhưng không xác định được bundle id",
                    info.procName, info.suspectBase);
            continue;
        }

        [crashLog addObject:@{
            @"base": tweak.base,
            @"bundle": bundle,
            @"proc": info.procName ?: @"",
            @"time": @(info.time),
            @"path": info.path ?: @""
        }];

        NSUInteger same = 0;
        for (NSDictionary *entry in crashLog) {
            double t = [entry[@"time"] doubleValue];
            if (now - t > window) continue;
            NSString *entryBase = entry[@"base"];
            NSString *entryBundle = entry[@"bundle"];
            if (![entryBase isKindOfClass:[NSString class]] ||
                ![entryBundle isKindOfClass:[NSString class]]) continue;
            if ([entryBase caseInsensitiveCompare:tweak.base] != NSOrderedSame) continue;
            if ([entryBundle caseInsensitiveCompare:bundle] != NSOrderedSame) continue;
            same++;
        }

        if (same >= escalate) {
            if (!AFIsTweakQuarantined(tweak.base, state)) {
                NSString *error = nil;
                NSString *reason = [NSString stringWithFormat:
                    @"vẫn crash %@ sau khi loại trừ", info.procName];
                if (AFDisableTweak(tweak, reason, state, &error)) {
                    [quarantinedBases addObject:tweak.base];
                    changed = YES;
                    needRespring = YES;
                } else if (error.length) {
                    AFLogTo(AFDaemonLogPath(), @"Không tắt được %@: %@",
                            tweak.base, error);
                }
            }
            continue;
        }

        if (same >= threshold) {
            NSString *error = nil;
            NSString *reason = info.watchdog
                ? [NSString stringWithFormat:@"làm %@ bị watchdog timeout", info.procName]
                : [NSString stringWithFormat:@"gây crash %@", info.procName];
            if (AFApplyAppExclusion(tweak.base, bundle, info.procName, reason,
                                    state, &error)) {
                changed = YES;
                addedExclusions++;
            } else if (error.length) {
                AFLogTo(AFDaemonLogPath(), @"Không loại trừ được %@: %@",
                        tweak.base, error);
            }
        }
    }

    /* Tweak gây crash ở nhiều app khác nhau: tắt hẳn thay vì loại trừ từng app. */
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *bundlesByBase =
        [NSMutableDictionary dictionary];
    for (NSDictionary *entry in crashLog) {
        double t = [entry[@"time"] doubleValue];
        if (now - t > 1800) continue;
        NSString *entryBase = entry[@"base"];
        NSString *entryBundle = entry[@"bundle"];
        if (![entryBase isKindOfClass:[NSString class]] ||
            ![entryBundle isKindOfClass:[NSString class]]) continue;
        NSString *key = entryBase.lowercaseString;
        NSMutableSet *set = bundlesByBase[key];
        if (!set) {
            set = [NSMutableSet set];
            bundlesByBase[key] = set;
        }
        [set addObject:entryBundle.lowercaseString];
    }

    for (NSString *key in bundlesByBase) {
        if (bundlesByBase[key].count < multiThreshold) continue;
        AFTweakInfo *tweak = AFTweakInfoForBase(key);
        if (!tweak || !tweak.enabled) continue;
        if (AFIsTweakQuarantined(tweak.base, state)) continue;

        NSString *error = nil;
        NSString *reason = [NSString stringWithFormat:
            @"gây crash ở %lu app khác nhau trong 30 phút",
            (unsigned long)bundlesByBase[key].count];
        if (AFDisableTweak(tweak, reason, state, &error)) {
            [quarantinedBases addObject:tweak.base];
            changed = YES;
            needRespring = YES;
            AFLogTo(AFDaemonLogPath(), @"Tắt %@ vì crash nhiều app", tweak.base);
        } else if (error.length) {
            AFLogTo(AFDaemonLogPath(), @"Không tắt được %@: %@", tweak.base, error);
        }
    }

    state[@"appProcessed"] = processed;
    state[@"appCrashLog"] = crashLog;

    if (changed) {
        NSMutableString *message = [NSMutableString string];
        if (cameraBases.count) {
            [message appendFormat:
                @"Auto Fix đã tạm tắt %@ vì làm Camera/FaceTime lỗi. Mở lại Camera để kiểm tra; có thể bật lại từ thông báo.",
                [cameraBases componentsJoinedByString:@", "]];
        }
        if (addedExclusions > 0) {
            if (message.length) [message appendString:@" "];
            [message appendFormat:
                @"Auto Fix phát hiện app bị crash do tweak can thiệp. Đã loại trừ tweak khỏi %lu app bị ảnh hưởng; tweak vẫn chạy ở các app khác.",
                (unsigned long)addedExclusions];
        }
        if (quarantinedBases.count) {
            if (message.length) [message appendString:@" "];
            [message appendFormat:
                @"Tweak %@ gây crash ở nhiều app nên đã bị tạm tắt toàn bộ.",
                [quarantinedBases componentsJoinedByString:@", "]];
        }
        AFPublishAppNotice(state, message);
        return AFAppGuardResultChanged |
               (needRespring ? AFAppGuardResultNeedRespring : 0);
    }

    return AFAppGuardResultNone;
}

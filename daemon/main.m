#import <Foundation/Foundation.h>

#import "shared/AFCore.h"
#import "shared/AFTweakScanner.h"
#import "shared/AFCrashParser.h"
#import "daemon/AFProcess.h"
#import "daemon/AFQuarantine.h"
#import "daemon/AFAppGuard.h"

#import <dispatch/dispatch.h>
#import <unistd.h>
#import <signal.h>
#import <stdlib.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <spawn.h>
#import <errno.h>
#import <string.h>
#import <math.h>

static NSMutableDictionary *gState = nil;
static pid_t gLastSpringBoardPID = 0;
static NSMutableArray<NSNumber *> *gRestartTimes = nil;
static NSTimeInterval gLastRecoveryTime = 0;
static NSTimeInterval gLastSnapshotTime = 0;
static double gStableSeconds = 0;
static NSUInteger gRecoveryCount = 0;
static BOOL gIgnoreNextRestart = NO;
static BOOL gRespringing = NO;
static dispatch_queue_t gWorkQueue = nil;
static dispatch_source_t gTimer = nil;

static void AFSaveState(void) {
    if (!gState) return;
    gState[@"recoveryCount"] = @(gRecoveryCount);
    gState[@"lastRecoveryTime"] = @(gLastRecoveryTime);
    AFWritePlistSecure(AFDaemonStatePath(), gState);
}

static NSMutableDictionary *AFLoadDaemonState(void) {
    NSDictionary *saved = AFReadPlist(AFDaemonStatePath());
    NSMutableDictionary *state = saved ? [saved mutableCopy]
                                       : [NSMutableDictionary dictionary];
    if ([state[@"quarantine"] isKindOfClass:[NSArray class]]) {
        state[@"quarantine"] = [state[@"quarantine"] mutableCopy];
    } else {
        state[@"quarantine"] = [NSMutableArray array];
    }
    AFSanitizeQuarantineRecords(state);
    AFSanitizeExclusionRecords(state);

    /* Bản mới đổi cách xử lý camera: bỏ danh sách "đã thử" của bản cũ,
       nếu không thủ phạm sẽ bị bỏ qua tới 6 giờ. */
    NSString *storedVersion = state[@"version"];
    if (![storedVersion isKindOfClass:[NSString class]] ||
        ![storedVersion isEqualToString:AFVersion]) {
        [state removeObjectForKey:@"cameraTried"];
        [state removeObjectForKey:@"cameraMarkerTime"];
        [state removeObjectForKey:@"cameraFailures"];
        [state removeObjectForKey:@"cameraLastFailure"];
        [state removeObjectForKey:@"staticConflictScan"];
        [state removeObjectForKey:@"staticConflicts"];
        [state removeObjectForKey:@"conflictScan"];
        [state removeObjectForKey:@"loadFailureScan"];
        [state removeObjectForKey:@"loadFailureHandled"];
        state[@"version"] = AFVersion;

        /* Bản mới sửa camera thay vì tắt tweak: trả lại các tweak từng bị
           tạm tắt vì camera để chúng chạy với lớp sửa mới. Nếu vẫn lỗi sau
           nhiều lần, daemon sẽ tạm tắt lại theo ngưỡng cấu hình. */
        for (NSDictionary *record in [AFQuarantineRecords(state) copy]) {
            if (![record[@"camera"] boolValue]) continue;
            NSString *base = record[@"base"];
            if ([base isKindOfClass:[NSString class]] && base.length) {
                AFEnableTweak(base, state, NULL);
            }
        }
    }
    return state;
}

/* Chạy trước khi gỡ gói: trả lại mọi tweak đã tạm tắt và hoàn tác Exclude. */
static int AFRestoreAll(void) {
    NSMutableDictionary *state = AFLoadDaemonState();
    NSUInteger restored = 0;
    for (NSDictionary *record in [AFQuarantineRecords(state) copy]) {
        NSString *base = record[@"base"];
        if (![base isKindOfClass:[NSString class]] || base.length == 0) continue;
        if (AFEnableTweak(base, state, NULL)) restored++;
    }
    NSUInteger exclusions = AFRemoveAppExclusions(nil, state, NULL);
    AFWritePlistSecure(AFDaemonStatePath(), state);
    printf("AutoFixDaemon --restore-all: khoi phuc %lu tweak, hoan tac %lu loai tru app\n",
           (unsigned long)restored, (unsigned long)exclusions);
    return 0;
}

static NSUInteger AFRestartCount(NSTimeInterval window) {
    NSTimeInterval now = AFNow();
    NSUInteger count = 0;
    for (NSNumber *value in gRestartTimes) {
        if (now - value.doubleValue <= window) count++;
    }
    return count;
}

static void AFPruneRestarts(NSTimeInterval now) {
    NSMutableArray *kept = [NSMutableArray array];
    for (NSNumber *value in gRestartTimes) {
        if (now - value.doubleValue <= 300) [kept addObject:value];
    }
    gRestartTimes = kept;
}

static NSTimeInterval gDaemonStartTime = 0;
static NSTimeInterval gLastSafeModeCheck = 0;

static BOOL AFHeartbeatFresh(NSTimeInterval now) {
    NSDictionary *attributes = [[NSFileManager defaultManager]
        attributesOfItemAtPath:AFTweakStatePath() error:NULL];
    NSDate *modified = attributes[NSFileModificationDate];
    if (!modified) return NO;
    return now - modified.timeIntervalSince1970 < 40;
}

static NSSet<NSString *> *AFQuarantinedBaseSet(void) {
    NSMutableSet *set = [NSMutableSet set];
    for (NSDictionary *record in AFQuarantineRecords(gState)) {
        NSString *base = record[@"base"];
        if ([base isKindOfClass:[NSString class]] && base.length) {
            [set addObject:base.lowercaseString];
        }
    }
    return set;
}

static BOOL AFValidBaseName(NSString *base) {
    if (![base isKindOfClass:[NSString class]] || base.length == 0 || base.length > 200) {
        return NO;
    }
    if ([base containsString:@"/"] || [base containsString:@".."]) return NO;
    return YES;
}

static int AFKillallSpringBoard(void) {
    const char *paths[] = {
        "/var/jb/usr/bin/killall", "/var/jb/bin/killall",
        "/usr/bin/killall", "/bin/killall"
    };
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
        const char *path = paths[i];
        if (access(path, X_OK) != 0) continue;
        const char *argv[] = {path, "-9", "SpringBoard", NULL};
        pid_t child = 0;
        int spawnError = posix_spawn(&child, path, NULL, NULL,
                                     (char * const *)argv, NULL);
        if (spawnError != 0) {
            AFLogTo(AFDaemonLogPath(), @"posix_spawn(%s) lỗi: %s",
                    path, strerror(spawnError));
            continue;
        }
        int status = 0;
        waitpid(child, &status, 0);
        return 0;
    }
    return -1;
}

static void AFRespring(NSString *reason) {
    if (gRespringing) return;
    pid_t pid = AFSpringBoardPID();
    if (pid <= 0) {
        AFLogTo(AFDaemonLogPath(), @"Không tìm thấy SpringBoard để respring");
        return;
    }

    gRespringing = YES;
    gIgnoreNextRestart = YES;
    AFLogTo(AFDaemonLogPath(), @"Respring SpringBoard (pid %d) - %@", pid, reason ?: @"");

    if (kill(pid, SIGKILL) == 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)),
                       gWorkQueue, ^{
            gRespringing = NO;
        });
        return;
    }

    gIgnoreNextRestart = NO;
    AFLogTo(AFDaemonLogPath(), @"kill(SpringBoard) thất bại: %s", strerror(errno));
    if (AFKillallSpringBoard() != 0) {
        AFLogTo(AFDaemonLogPath(), @"Không thể respring SpringBoard");
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)),
                   gWorkQueue, ^{
        gRespringing = NO;
    });
}

static void AFPerformRecovery(NSDictionary *config,
                              NSString *kind,
                              NSString *extraBase,
                              NSString *reasonText) {
    NSTimeInterval now = AFNow();
    if (now - gLastRecoveryTime < 20) return;

    NSSet<NSString *> *quarantined = AFQuarantinedBaseSet();
    NSArray<AFTweakInfo *> *allTweaks = AFScanTweaks();
    NSMutableDictionary<NSString *, AFTweakInfo *> *byBase = [NSMutableDictionary dictionary];
    for (AFTweakInfo *info in allTweaks) {
        if (info.base.length) byBase[info.base.lowercaseString] = info;
    }

    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    void (^addCandidate)(NSString *, NSString *, NSInteger) =
        ^(NSString *base, NSString *reason, NSInteger priority) {
        if (!AFValidBaseName(base)) return;
        NSString *key = base.lowercaseString;
        if ([seen containsObject:key]) return;
        if (AFIsSelfTweakBase(base) || AFIsWhitelistedTweakBase(base)) return;
        if ([quarantined containsObject:key]) return;

        AFTweakInfo *info = byBase[key];
        if (!info || !info.enabled) return;

        [seen addObject:key];
        [candidates addObject:@{
            @"base": info.base,
            @"reason": reason ?: @"",
            @"priority": @(priority),
            @"installTime": @(info.installTime),
            @"mtime": @(info.mtime)
        }];
    };

    if (extraBase.length) {
        addCandidate(extraBase, @"watchdog báo SpringBoard treo", 0);
    }

    AFCrashInfo *marker = AFReadCrashMarker();
    if (marker && now - marker.time <= 900 && marker.suspectBase.length) {
        addCandidate(marker.suspectBase, @"crash signal của SpringBoard", 1);
    }

    AFCrashInfo *hangMarker = AFReadHangMarker();
    if (hangMarker && now - hangMarker.time <= 900 && hangMarker.suspectBase.length) {
        addCandidate(hangMarker.suspectBase, @"SpringBoard treo main thread", 1);
    }

    AFCrashInfo *report = AFNewestSpringBoardCrash(900);
    if (report && report.suspectBase.length) {
        addCandidate(report.suspectBase, @"báo cáo crash SpringBoard", 1);
    }

    if (candidates.count == 0) {
        NSDictionary *lastGood = AFLastGoodManifest();
        NSDictionary *lastGoodTweaks = [lastGood[@"tweaks"] isKindOfClass:[NSDictionary class]]
            ? lastGood[@"tweaks"] : @{};

        for (AFTweakInfo *info in allTweaks) {
            if (!info.enabled) continue;
            if (AFIsSelfTweakBase(info.base) || AFIsWhitelistedTweakBase(info.base)) continue;
            if ([quarantined containsObject:info.base.lowercaseString]) continue;

            NSDictionary *previous = lastGoodTweaks[info.base];
            if (![previous isKindOfClass:[NSDictionary class]]) {
                addCandidate(info.base, @"mới cài đặt hoặc chưa có trong trạng thái ổn định", 2);
            } else {
                double previousInstall = [previous[@"installTime"] doubleValue];
                double previousMTime = [previous[@"mtime"] doubleValue];
                if (fabs(info.installTime - previousInstall) > 2.0 ||
                    fabs(info.mtime - previousMTime) > 2.0) {
                    addCandidate(info.base, @"đã thay đổi so với trạng thái ổn định", 2);
                }
            }
        }
    }

    if (candidates.count == 0) {
        NSArray<AFTweakInfo *> *recent = AFRecentlyInstalledTweaks(
            allTweaks, now - 7 * 86400, quarantined);
        for (NSUInteger i = 0; i < recent.count && i < 2; i++) {
            AFTweakInfo *info = recent[i];
            addCandidate(info.base, @"cài đặt gần đây", 3);
        }
    }

    NSUInteger maxRecoveries = [config[@"maxRecoveries"] unsignedIntegerValue];
    if (maxRecoveries == 0) maxRecoveries = 3;
    BOOL allowSafeAll = [config[@"allowSafeAll"] boolValue];
    BOOL safeAll = allowSafeAll && gRecoveryCount >= maxRecoveries;

    if (safeAll || (candidates.count == 0 && allowSafeAll)) {
        safeAll = YES;
        [candidates removeAllObjects];
        [seen removeAllObjects];
        for (AFTweakInfo *info in allTweaks) {
            if (!info.enabled) continue;
            if (AFIsSelfTweakBase(info.base) || AFIsWhitelistedTweakBase(info.base)) continue;
            if ([quarantined containsObject:info.base.lowercaseString]) continue;
            addCandidate(info.base,
                         @"chế độ an toàn sau nhiều lần khôi phục thất bại", 4);
        }
    }

    [candidates sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger priorityA = [a[@"priority"] integerValue];
        NSInteger priorityB = [b[@"priority"] integerValue];
        if (priorityA != priorityB) {
            return priorityA < priorityB ? NSOrderedAscending : NSOrderedDescending;
        }
        double installA = [a[@"installTime"] doubleValue];
        double installB = [b[@"installTime"] doubleValue];
        if (installA != installB) {
            return installA > installB ? NSOrderedAscending : NSOrderedDescending;
        }
        double mtimeA = [a[@"mtime"] doubleValue];
        double mtimeB = [b[@"mtime"] doubleValue];
        if (mtimeA != mtimeB) {
            return mtimeA > mtimeB ? NSOrderedAscending : NSOrderedDescending;
        }
        return NSOrderedSame;
    }];

    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (NSDictionary *candidate in candidates) {
        if (!safeAll && items.count >= 3) break;
        NSString *base = candidate[@"base"];
        AFTweakInfo *info = byBase[base.lowercaseString];
        if (!info || !info.enabled) continue;

        NSString *error = nil;
        if (AFDisableTweak(info, candidate[@"reason"], gState, &error)) {
            [items addObject:@{
                @"base": info.base,
                @"package": info.package ?: @"",
                @"reason": candidate[@"reason"] ?: @"",
                @"kind": @"quarantine",
                @"detail": candidate[@"reason"] ?: @"đã tạm tắt"
            }];
        } else if (error.length) {
            AFLogTo(AFDaemonLogPath(), @"Không tắt được %@: %@", base, error);
        }
    }

    NSMutableSet<NSString *> *listed = [NSMutableSet set];
    for (NSDictionary *item in items) [listed addObject:[item[@"base"] lowercaseString]];
    for (NSDictionary *record in AFQuarantineRecords(gState)) {
        NSString *base = record[@"base"];
        if (![base isKindOfClass:[NSString class]] || base.length == 0) continue;
        if ([listed containsObject:base.lowercaseString]) continue;
        [listed addObject:base.lowercaseString];
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

    for (NSDictionary *record in AFAppExclusionRecords(gState)) {
        NSString *base = record[@"base"];
        if (![base isKindOfClass:[NSString class]] || base.length == 0) continue;
        if ([listed containsObject:base.lowercaseString]) continue;
        [listed addObject:base.lowercaseString];
        NSString *label = record[@"proc"];
        if (![label isKindOfClass:[NSString class]] || label.length == 0) {
            label = record[@"bundle"];
        }
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

    gRecoveryCount++;
    gLastRecoveryTime = now;
    if (kind.length == 0) kind = @"loop";

    NSMutableString *message = [NSMutableString string];
    if (reasonText.length) {
        [message appendString:reasonText];
    } else {
        [message appendString:@"Phát hiện SpringBoard gặp lỗi khởi động lại."];
    }

    if (safeAll) {
        [message appendString:@"\nAuto Fix đã thử khôi phục nhưng vẫn lỗi nên bật chế độ an toàn: tạm tắt toàn bộ tweak không thiết yếu. Hãy bật lại từng tweak để tìm thủ phạm."];
    } else if (items.count) {
        [message appendString:@"\nAuto Fix đã xử lý tweak nghi ngờ và respring để khôi phục."];
    } else {
        [message appendString:@"\nAuto Fix chưa xác định được tweak gây lỗi. Thiết bị sẽ tiếp tục được theo dõi."];
    }

    gState[@"notice"] = @{
        @"id": @(now),
        @"time": @(now),
        @"kind": kind,
        @"message": message,
        @"items": items,
        @"safeAll": @(safeAll),
        @"recoveryCount": @(gRecoveryCount)
    };
    gState[@"lastAnalysis"] = @{
        @"time": @(now),
        @"kind": kind,
        @"reason": reasonText ?: @"",
        @"candidates": candidates,
        @"quarantinedNow": items
    };
    AFSaveState();

    AFLogTo(AFDaemonLogPath(), @"Recovery #%lu (%@): tắt %lu tweak, safeAll=%d",
            (unsigned long)gRecoveryCount, kind, (unsigned long)items.count, safeAll);

    if (items.count) {
        [gRestartTimes removeAllObjects];
        AFRespring(@"khôi phục tự động");
    }
}

static BOOL AFProcessRequests(NSDictionary *config) {
    BOOL wantRespring = NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:AFRequestsDir() error:NULL];
    NSArray *sorted = [files sortedArrayUsingSelector:@selector(compare:)];

    for (NSString *file in sorted) {
        if (![file hasSuffix:@".req"]) continue;
        NSString *full = [AFRequestsDir() stringByAppendingPathComponent:file];
        NSString *name = [file substringToIndex:file.length - [@".req" length]];
        if (name.length == 0 || name.length > 160 || [name containsString:@"/"]) {
            [fm removeItemAtPath:full error:NULL];
            continue;
        }

        struct stat st;
        if (lstat(full.fileSystemRepresentation, &st) != 0 ||
            !S_ISREG(st.st_mode) || st.st_uid != 501) {
            AFLogTo(AFDaemonLogPath(), @"Bỏ qua request không hợp lệ: %@", file);
            [fm removeItemAtPath:full error:NULL];
            continue;
        }

        NSDictionary *request = AFReadPlist(full);
        if (![request isKindOfClass:[NSDictionary class]]) request = @{};
        [fm removeItemAtPath:full error:NULL];

        if ([name isEqualToString:@"ack"]) {
            [gState removeObjectForKey:@"notice"];
            AFSaveState();
        } else if ([name isEqualToString:@"respring"]) {
            wantRespring = YES;
        } else if ([name isEqualToString:@"recover"]) {
            AFPerformRecovery(config, @"manual", nil,
                @"Yêu cầu khôi phục thủ công từ Auto Fix.");
        } else if ([name isEqualToString:@"hang"]) {
            NSString *base = [request[@"base"] isKindOfClass:[NSString class]]
                ? request[@"base"] : @"";
            AFPerformRecovery(config, @"hang", base,
                @"SpringBoard bị treo: main thread không phản hồi trong thời gian dài.");
        } else if ([name hasPrefix:@"enable__"] || [name hasPrefix:@"disable__"]) {
            BOOL enable = [name hasPrefix:@"enable__"];
            NSString *prefix = enable ? @"enable__" : @"disable__";
            NSString *base = [name substringFromIndex:prefix.length];
            NSString *payloadBase = [request[@"base"] isKindOfClass:[NSString class]]
                ? request[@"base"] : nil;
            if (payloadBase.length) base = payloadBase;

            if (!AFValidBaseName(base)) {
                AFLogTo(AFDaemonLogPath(), @"Tên tweak không hợp lệ trong yêu cầu: %@", name);
                continue;
            }

            NSString *error = nil;
            if (enable) {
                NSString *enableError = nil;
                BOOL restoredQuarantine = AFEnableTweak(base, gState, &enableError);
                NSUInteger removedExclusions = AFRemoveAppExclusions(base, gState, NULL);
                if (restoredQuarantine || removedExclusions > 0) {
                    gRecoveryCount = 0;
                    [gState removeObjectForKey:@"cameraTried"];
                    [gState removeObjectForKey:@"cameraFailures"];
                    [gState removeObjectForKey:@"cameraLastFailure"];
                    [gState removeObjectForKey:@"notice"];
                    AFSaveState();
                    AFLogTo(AFDaemonLogPath(),
                            @"Đã bật lại %@ theo yêu cầu (quarantine=%d, bỏ loại trừ=%lu)",
                            base, restoredQuarantine, (unsigned long)removedExclusions);
                } else if (enableError.length || error.length) {
                    AFLogTo(AFDaemonLogPath(), @"Không bật lại được %@: %@", base,
                            enableError.length ? enableError : error);
                }
            } else {
                AFTweakInfo *info = AFTweakInfoForBase(base);
                if (info && AFDisableTweak(info, @"người dùng yêu cầu", gState, &error)) {
                    AFSaveState();
                    AFLogTo(AFDaemonLogPath(), @"Đã tắt %@ theo yêu cầu", base);
                } else if (error.length) {
                    AFLogTo(AFDaemonLogPath(), @"Không tắt được %@: %@", base, error);
                }
            }
        } else {
            AFLogTo(AFDaemonLogPath(), @"Bỏ qua yêu cầu không rõ: %@", name);
        }
    }

    return wantRespring;
}

static NSMutableArray<NSDictionary *> *AFNoticeItemsFromState(void) {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (NSDictionary *record in AFQuarantineRecords(gState)) {
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
    for (NSDictionary *record in AFAppExclusionRecords(gState)) {
        NSString *base = record[@"base"];
        if (![base isKindOfClass:[NSString class]] || base.length == 0) continue;
        NSString *label = record[@"proc"];
        if (![label isKindOfClass:[NSString class]] || label.length == 0) {
            label = record[@"bundle"];
        }
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
    return items;
}

/* Tweak bị dyld từ chối nạp (missing dependency, sai kiến trúc, chữ ký hỏng)
   làm SpringBoard/app kẹt ở màn hình đen hoặc crash lúc khởi động. */
static void AFLoadFailureGuard(NSDictionary *config) {
    if (![config[@"loadFailureGuard"] boolValue]) return;

    NSTimeInterval now = AFNow();
    double lastScan = [gState[@"loadFailureScan"] doubleValue];
    if (lastScan > 0 && now - lastScan < 60) return;
    gState[@"loadFailureScan"] = @(now);

    NSDictionary *saved = [gState[@"loadFailureHandled"] isKindOfClass:[NSDictionary class]]
        ? gState[@"loadFailureHandled"] : @{};
    NSMutableDictionary *handled = [NSMutableDictionary dictionary];
    for (NSString *path in saved) {
        if (now - [saved[path] doubleValue] <= 86400) handled[path] = saved[path];
    }

    NSUInteger parsed = 0;
    for (NSDictionary *candidate in AFCrashReportCandidates(3600)) {
        if (parsed >= 6) break;
        NSString *path = candidate[@"path"];
        if (![path isKindOfClass:[NSString class]]) continue;
        if (handled[path]) continue;
        if (lastScan > 0 && [candidate[@"time"] doubleValue] <= lastScan - 120) continue;
        parsed++;

        AFCrashInfo *info = AFParseCrashReport(path);
        if (!info) continue;

        NSString *base = AFLoadFailureTweakBase(path);
        if (base.length == 0) continue;
        handled[path] = @(now);

        if (AFIsTweakQuarantined(base, gState)) continue;
        AFTweakInfo *tweak = AFTweakInfoForBase(base);
        if (!tweak || !tweak.enabled) continue;
        if (info.time > 0 && tweak.installTime > info.time + 120) continue;

        NSString *procName = info.procName.length ? info.procName : @"SpringBoard";
        NSString *reason = [NSString stringWithFormat:
            @"không nạp được vào %@ (lỗi dyld)", procName];
        AFLogTo(AFDaemonLogPath(), @"Lỗi nạp tweak: %@ -> %@ (%@)",
                base, reason, path.lastPathComponent ?: @"?");
        AFPerformRecovery(config, @"loadfail", base,
            [NSString stringWithFormat:
             @"Tweak %@ không nạp được (Library not loaded/Symbol not found) nên Auto Fix đã tạm tắt để %@ khởi động bình thường.",
             base, procName]);
        break;
    }

    gState[@"loadFailureHandled"] = handled;
}

static void AFSafeModeGuard(NSDictionary *config) {
    if (![config[@"safeModeGuard"] boolValue]) return;

    NSTimeInterval now = AFNow();
    if (now - gDaemonStartTime < 180) return;
    if (now - gLastSafeModeCheck < 30) return;
    gLastSafeModeCheck = now;

    NSDictionary *attributes = [[NSFileManager defaultManager]
        attributesOfItemAtPath:AFTweakStatePath() error:NULL];
    NSDate *modified = attributes[NSFileModificationDate];
    if (!modified) return;

    NSTimeInterval heartbeat = modified.timeIntervalSince1970;
    double grace = [config[@"safeModeGrace"] doubleValue];
    if (grace <= 0) grace = 90;

    if (now - heartbeat < grace) {
        if (gState[@"safeMode"]) {
            [gState removeObjectForKey:@"safeMode"];
            AFSaveState();
            AFLogTo(AFDaemonLogPath(), @"Tweak đã nạp lại, thoát trạng thái Safe Mode");
        }
        return;
    }
    if (AFSpringBoardPID() <= 0) return;

    NSDictionary *safeMode = [gState[@"safeMode"] isKindOfClass:[NSDictionary class]]
        ? gState[@"safeMode"] : nil;
    NSUInteger attempts = [safeMode[@"attempts"] unsignedIntegerValue];
    double lastAttempt = [safeMode[@"last"] doubleValue];
    if (lastAttempt > 0 && now - lastAttempt < 1800) return;
    if (attempts >= 2 && lastAttempt > 0 && now - lastAttempt < 6 * 3600) return;

    AFCrashInfo *report = AFNewestSpringBoardCrash(1800);
    AFCrashInfo *marker = AFReadCrashMarker();
    NSString *base = report.suspectBase;
    if (base.length == 0 && marker && now - marker.time <= 1800) {
        base = marker.suspectBase;
    }
    if (base.length == 0) {
        AFLogTo(AFDaemonLogPath(),
                @"SpringBoard không nạp tweak nhưng không có crash report để xác định thủ phạm");
        return;
    }
    if (AFIsTweakQuarantined(base, gState)) return;

    AFTweakInfo *info = AFTweakInfoForBase(base);
    if (!info || !info.enabled) return;

    NSString *error = nil;
    if (!AFDisableTweak(info, @"SpringBoard rơi vào Safe Mode", gState, &error)) {
        AFLogTo(AFDaemonLogPath(), @"Không thoát được Safe Mode: %@", error ?: @"?");
        return;
    }

    gRecoveryCount++;
    gLastRecoveryTime = now;
    gState[@"safeMode"] = @{@"last": @(now), @"attempts": @(attempts + 1)};

    NSString *message = [NSString stringWithFormat:
        @"Phát hiện SpringBoard đang ở Safe Mode (tweak không được nạp). Auto Fix đã tắt %@ và respring để thoát Safe Mode.",
        info.base];
    gState[@"notice"] = @{
        @"id": @((long long)(now * 1000.0)),
        @"time": @(now),
        @"kind": @"safemode",
        @"message": message,
        @"items": AFNoticeItemsFromState(),
        @"safeAll": @NO,
        @"recoveryCount": @(gRecoveryCount)
    };
    AFSaveState();
    AFLogTo(AFDaemonLogPath(), @"Safe Mode: tắt %@ và respring", info.base);
    AFRespring(@"thoát Safe Mode");
}

static void AFTick(void) {
    @autoreleasepool {
        @try {
            AFEnsureStateDir();
            chmod(AFRequestsDir().fileSystemRepresentation, 0777);

            NSDictionary *config = AFLoadConfig();
            BOOL wantRespring = AFProcessRequests(config);

            AFAppGuardResult appGuard = AFAppGuardTick(config, gState);
            if (appGuard & AFAppGuardResultChanged) {
                AFSaveState();
                if (appGuard & AFAppGuardResultNeedRespring) wantRespring = YES;
            }
            AFSafeModeGuard(config);
            AFLoadFailureGuard(config);

            pid_t springBoard = AFSpringBoardPID();
            NSTimeInterval now = AFNow();

            if (springBoard != gLastSpringBoardPID) {
                if (gLastSpringBoardPID != 0) {
                    if (gIgnoreNextRestart) {
                        gIgnoreNextRestart = NO;
                    } else {
                        [gRestartTimes addObject:@(now)];
                    }
                    AFLogTo(AFDaemonLogPath(), @"SpringBoard đổi PID: %d -> %d",
                            gLastSpringBoardPID, springBoard);
                }
                gLastSpringBoardPID = springBoard;
            }
            AFPruneRestarts(now);

            if ([config[@"enabled"] boolValue]) {
                NSUInteger window = (NSUInteger)[config[@"loopWindow"] doubleValue];
                if (window == 0) window = 45;
                NSUInteger threshold = [config[@"loopCount"] unsignedIntegerValue];
                if (threshold < 2) threshold = 3;

                NSUInteger restartCount = AFRestartCount((NSTimeInterval)window);
                if (restartCount >= threshold && now - gLastRecoveryTime > 25) {
                    NSString *reason = [NSString stringWithFormat:
                        @"Phát hiện SpringBoard khởi động lại %lu lần trong %lu giây (vòng lặp respring).",
                        (unsigned long)restartCount, (unsigned long)window];
                    AFPerformRecovery(config, @"loop", nil, reason);
                    wantRespring = NO;
                }

                BOOL heartbeatFresh = AFHeartbeatFresh(now);
                if (heartbeatFresh && AFRestartCount(120) == 0 &&
                    now - gLastRecoveryTime > 120) {
                    gStableSeconds += 1.5;
                    if (gStableSeconds >= 90 && now - gLastSnapshotTime > 60) {
                        NSDictionary *manifest = AFBuildManifest(AFScanTweaks());
                        if (AFSaveLastGoodManifest(manifest)) {
                            gLastSnapshotTime = now;
                            AFLogTo(AFDaemonLogPath(),
                                    @"Đã lưu trạng thái ổn định (%lu tweak)",
                                    (unsigned long)manifest.count);
                        }
                    }
                    if (gStableSeconds >= 600 && gRecoveryCount > 0) {
                        gRecoveryCount = 0;
                        AFSaveState();
                        AFLogTo(AFDaemonLogPath(),
                                @"Thiết bị ổn định, đặt lại bộ đếm khôi phục");
                    }
                } else {
                    gStableSeconds = 0;
                }
            }

            if (wantRespring) {
                AFRespring(@"yêu cầu từ giao diện");
            }
        } @catch (NSException *exception) {
            AFLogTo(AFDaemonLogPath(), @"Lỗi vòng lặp daemon: %@",
                    exception.reason ?: exception.name);
        }
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (geteuid() != 0) {
            fprintf(stderr, "AutoFixDaemon phải chạy bằng quyền root\n");
            return 1;
        }
        signal(SIGPIPE, SIG_IGN);

        AFEnsureStateDir();
        chmod(AFRequestsDir().fileSystemRepresentation, 0777);
        chown(AFRequestsDir().fileSystemRepresentation, 501, 501);

        if (argc > 1 && strcmp(argv[1], "--restore-all") == 0) {
            return AFRestoreAll();
        }

        if (!AFReadPlist(AFConfigPath())) {
            AFWritePlist(AFConfigPath(), AFDefaultConfig());
        }

        gRestartTimes = [NSMutableArray array];
        gState = AFLoadDaemonState();
        gRecoveryCount = [gState[@"recoveryCount"] unsignedIntegerValue];
        gLastRecoveryTime = [gState[@"lastRecoveryTime"] doubleValue];

        AFLogTo(AFDaemonLogPath(), @"AutoFixDaemon %@ khởi động (rootless=%@)",
                AFVersion, AFIsRootless() ? @"có" : @"không");

        gDaemonStartTime = AFNow();
        gWorkQueue = dispatch_queue_create("com.minhhai.autofixtweakd.work",
                                           DISPATCH_QUEUE_SERIAL);
        gLastSpringBoardPID = AFSpringBoardPID();

        gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gWorkQueue);
        dispatch_source_set_timer(gTimer,
            dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
            (uint64_t)(1.5 * NSEC_PER_SEC), (uint64_t)(0.5 * NSEC_PER_SEC));
        dispatch_source_set_event_handler(gTimer, ^{
            AFTick();
        });
        dispatch_resume(gTimer);

        dispatch_main();
    }
    return 0;
}

#import "daemon/AFQuarantine.h"
#import "shared/AFCore.h"

#import <stdio.h>
#import <errno.h>
#import <string.h>

NSArray<NSDictionary *> *AFQuarantineRecords(NSDictionary *state) {
    id records = state[@"quarantine"];
    return [records isKindOfClass:[NSArray class]] ? records : @[];
}

BOOL AFIsTweakQuarantined(NSString *base, NSDictionary *state) {
    if (base.length == 0) return NO;
    for (NSDictionary *record in AFQuarantineRecords(state)) {
        NSString *recordBase = record[@"base"];
        if ([recordBase caseInsensitiveCompare:base] == NSOrderedSame) return YES;
    }
    return NO;
}

BOOL AFQuarantinePathSafe(NSString *path, BOOL disabled) {
    if (![path isKindOfClass:[NSString class]] || path.length == 0) return NO;
    if (![path hasPrefix:@"/"] || [path containsString:@"/../"] ||
        [path hasSuffix:@"/.."] ) {
        return NO;
    }
    BOOL hasSuffix = [path hasSuffix:@".autofixdisabled"];
    if (disabled != hasSuffix) return NO;

    NSString *dir = path.stringByDeletingLastPathComponent;
    for (NSString *allowed in AFDynamicLibraryDirs()) {
        if ([dir isEqualToString:allowed]) return YES;
    }
    return NO;
}

NSUInteger AFSanitizeQuarantineRecords(NSMutableDictionary *state) {
    NSArray *records = AFQuarantineRecords(state);
    NSMutableArray<NSDictionary *> *kept = [NSMutableArray array];
    for (NSDictionary *record in records) {
        if (![record isKindOfClass:[NSDictionary class]]) continue;
        NSString *base = record[@"base"];
        if (![base isKindOfClass:[NSString class]] || base.length == 0 ||
            base.length > 200 || [base containsString:@"/"] ||
            [base containsString:@".."]) {
            AFLogTo(AFDaemonLogPath(), @"Bỏ bản ghi quarantine không hợp lệ (base)");
            continue;
        }

        BOOL valid = YES;
        NSString *plist = record[@"plist"];
        NSString *plistDisabled = record[@"plistDisabled"];
        if (plist || plistDisabled) {
            valid = AFQuarantinePathSafe(plist, NO) &&
                    AFQuarantinePathSafe(plistDisabled, YES);
        }
        NSString *dylib = record[@"dylib"];
        NSString *dylibDisabled = record[@"dylibDisabled"];
        if (dylib || dylibDisabled) {
            valid = valid && AFQuarantinePathSafe(dylib, NO) &&
                    AFQuarantinePathSafe(dylibDisabled, YES);
        }
        if (!(plist || plistDisabled || dylib || dylibDisabled)) valid = NO;
        if (!valid) {
            AFLogTo(AFDaemonLogPath(), @"Bỏ bản ghi quarantine không hợp lệ: %@", base);
            continue;
        }
        [kept addObject:record];
    }
    state[@"quarantine"] = kept;
    return kept.count;
}

static BOOL AFRenameFile(NSString *from, NSString *to, NSString **errorOut) {
    if (!AFFileExists(from)) return NO;
    if (AFFileExists(to)) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"đích đã tồn tại: %@", to];
        return NO;
    }
    if (rename(from.fileSystemRepresentation, to.fileSystemRepresentation) == 0) {
        return YES;
    }
    if (errorOut) {
        *errorOut = [NSString stringWithFormat:@"rename %@ -> %@: %s",
                     from, to, strerror(errno)];
    }
    return NO;
}

BOOL AFDisableTweak(AFTweakInfo *info,
                    NSString *reason,
                    NSMutableDictionary *state,
                    NSString **errorOut) {
    if (!info || info.base.length == 0) {
        if (errorOut) *errorOut = @"thiếu thông tin tweak";
        return NO;
    }
    if (AFIsSelfTweakBase(info.base) || AFIsWhitelistedTweakBase(info.base)) {
        if (errorOut) *errorOut = @"tweak nằm trong danh sách bảo vệ";
        return NO;
    }
    if (!info.enabled) {
        if (errorOut) *errorOut = @"tweak đã bị tắt trước đó";
        return NO;
    }
    if (AFIsTweakQuarantined(info.base, state)) return YES;

    NSMutableDictionary *record = [NSMutableDictionary dictionary];
    record[@"base"] = info.base;
    record[@"time"] = @(AFNow());
    record[@"reason"] = reason ?: @"";
    if (info.package.length) record[@"package"] = info.package;

    NSString *error = nil;
    if (info.plistPath.length) {
        NSString *destination = [info.plistPath stringByAppendingString:@".autofixdisabled"];
        if (AFRenameFile(info.plistPath, destination, &error)) {
            record[@"plist"] = info.plistPath;
            record[@"plistDisabled"] = destination;
        } else if (error.length) {
            AFLogTo(AFDaemonLogPath(), @"Không tắt được plist %@: %@", info.plistPath, error);
        }
    }
    if (info.dylibPath.length) {
        NSString *destination = [info.dylibPath stringByAppendingString:@".autofixdisabled"];
        NSString *dylibError = nil;
        if (AFRenameFile(info.dylibPath, destination, &dylibError)) {
            record[@"dylib"] = info.dylibPath;
            record[@"dylibDisabled"] = destination;
        } else if (dylibError.length) {
            AFLogTo(AFDaemonLogPath(), @"Không tắt được dylib %@: %@", info.dylibPath, dylibError);
        }
    }

    if (!record[@"plist"] && !record[@"dylib"]) {
        if (errorOut) *errorOut = error.length ? error : @"không đổi tên được file nào";
        return NO;
    }

    NSMutableArray *records = [AFQuarantineRecords(state) mutableCopy];
    [records addObject:record];
    state[@"quarantine"] = records;

    AFLogTo(AFDaemonLogPath(), @"Đã tắt tweak %@ (%@) - %@",
            info.base, info.package ?: @"không rõ package", reason ?: @"");
    return YES;
}

static BOOL AFRestoreFile(NSString *disabledPath, NSString *originalPath, NSString **errorOut) {
    if (disabledPath.length == 0 || originalPath.length == 0) return NO;
    if (!AFFileExists(disabledPath)) return NO;
    if (AFFileExists(originalPath)) {
        AFLogTo(AFDaemonLogPath(), @"Bỏ qua khôi phục vì file gốc đã tồn tại: %@", originalPath);
        return NO;
    }
    if (rename(disabledPath.fileSystemRepresentation, originalPath.fileSystemRepresentation) == 0) {
        return YES;
    }
    if (errorOut) {
        *errorOut = [NSString stringWithFormat:@"restore %@: %s",
                     originalPath, strerror(errno)];
    }
    return NO;
}

static NSArray<AFTweakInfo *> *AFTweaksForBaseScan(NSString *base) {
    NSMutableArray *matches = [NSMutableArray array];
    for (AFTweakInfo *info in AFScanTweaks()) {
        if ([info.base caseInsensitiveCompare:base] == NSOrderedSame) [matches addObject:info];
    }
    return matches;
}

BOOL AFEnableTweak(NSString *base, NSMutableDictionary *state, NSString **errorOut) {
    if (base.length == 0) {
        if (errorOut) *errorOut = @"thiếu tên tweak";
        return NO;
    }

    NSMutableArray *records = [AFQuarantineRecords(state) mutableCopy];
    NSInteger foundIndex = NSNotFound;
    for (NSUInteger i = 0; i < records.count; i++) {
        NSString *recordBase = records[i][@"base"];
        if ([recordBase caseInsensitiveCompare:base] == NSOrderedSame) {
            foundIndex = (NSInteger)i;
            break;
        }
    }

    if (foundIndex == NSNotFound) {
        BOOL restored = NO;
        NSString *error = nil;
        for (AFTweakInfo *info in AFTweaksForBaseScan(base)) {
            if (info.disabledPlistPath.length && info.plistPath.length == 0) {
                NSString *original = info.disabledPlistPath;
                original = [original substringToIndex:original.length -
                            [@".autofixdisabled" length]];
                if (AFRestoreFile(info.disabledPlistPath, original, &error)) restored = YES;
            }
            if (info.disabledDylibPath.length && info.dylibPath.length == 0) {
                NSString *original = info.disabledDylibPath;
                original = [original substringToIndex:original.length -
                            [@".autofixdisabled" length]];
                if (AFRestoreFile(info.disabledDylibPath, original, &error)) restored = YES;
            }
        }
        if (!restored && errorOut) *errorOut = @"không tìm thấy bản ghi quarantine";
        return restored;
    }

    NSMutableDictionary *record = [records[(NSUInteger)foundIndex] mutableCopy];
    if ((record[@"plist"] || record[@"plistDisabled"]) &&
        !(AFQuarantinePathSafe(record[@"plist"], NO) &&
          AFQuarantinePathSafe(record[@"plistDisabled"], YES))) {
        if (errorOut) *errorOut = @"đường dẫn plist không hợp lệ";
        return NO;
    }
    if ((record[@"dylib"] || record[@"dylibDisabled"]) &&
        !(AFQuarantinePathSafe(record[@"dylib"], NO) &&
          AFQuarantinePathSafe(record[@"dylibDisabled"], YES))) {
        if (errorOut) *errorOut = @"đường dẫn dylib không hợp lệ";
        return NO;
    }

    NSString *error = nil;
    BOOL restored = NO;
    if (AFRestoreFile(record[@"plistDisabled"], record[@"plist"], &error)) restored = YES;
    if (AFRestoreFile(record[@"dylibDisabled"], record[@"dylib"], &error)) restored = YES;

    if (!restored) {
        if (errorOut) *errorOut = error.length ? error : @"không khôi phục được file";
        return NO;
    }

    [records removeObjectAtIndex:(NSUInteger)foundIndex];
    state[@"quarantine"] = records;

    AFLogTo(AFDaemonLogPath(), @"Đã bật lại tweak %@%@", record[@"base"] ?: base,
            record[@"package"] ? [NSString stringWithFormat:@" (%@)", record[@"package"]] : @"");
    return YES;
}

#import "shared/AFCrashParser.h"
#import "shared/AFCore.h"

#import <sys/stat.h>

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

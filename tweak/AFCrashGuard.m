#import "tweak/AFCrashGuard.h"
#import "shared/AFCore.h"
#import "shared/AFTweakScanner.h"

#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <signal.h>
#import <sys/ucontext.h>
#import <sys/stat.h>
#import <unistd.h>
#import <fcntl.h>
#import <stdlib.h>
#import <string.h>
#import <stdio.h>
#import <time.h>

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
        AFImageRange *ranges = calloc(imageCount > 0 ? imageCount : 1, sizeof(AFImageRange));
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
            struct sigaction action = {0};
            action.sa_sigaction = AFSignalHandler;
            action.sa_flags = SA_SIGINFO | SA_ONSTACK;
            sigemptyset(&action.sa_mask);
            sigaction(signalNumber, &action, &gOldActions[signalNumber]);
        }
    });
}

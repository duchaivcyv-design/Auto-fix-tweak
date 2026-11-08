#import "tweak/AFUI.h"
#import "tweak/AFBridge.h"
#import "shared/AFCore.h"

#import <UIKit/UIKit.h>

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

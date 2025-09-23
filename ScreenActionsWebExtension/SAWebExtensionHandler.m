//
//  SAWebExtensionHandler.m
//  ScreenActionsWebExtension
//
//  Created by . . on 9/22/25.
//

@import Foundation;
@import SafariServices;
@import os.log;

#if __has_include("ScreenActionsWebExtension-Swift.h")
#import "ScreenActionsWebExtension-Swift.h"
#elif __has_include("ScreenActionsWebExtension2-Swift.h")
#import "ScreenActionsWebExtension2-Swift.h"
#endif

static os_log_t SAWebLog(void) {
    static os_log_t log; static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.conornolan.Screen-Actions.WebExtension", "native"); });
    return log;
}

@interface SAWebExtensionHandler : NSObject
@end

@implementation SAWebExtensionHandler

+ (void)load { os_log(SAWebLog(), "[SA] Obj-C principal loaded"); }

- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    os_log(SAWebLog(), "[SA] beginRequest items=%{public}lu", (unsigned long)context.inputItems.count);

    NSExtensionItem *item = (NSExtensionItem *)context.inputItems.firstObject;
    NSDictionary *userInfo = item.userInfo ?: @{};
    id body = userInfo[SFExtensionMessageKey];

    if (![body isKindOfClass:[NSDictionary class]]) {
        os_log(SAWebLog(), "[SA] bad message body");
        [self reply:context payload:@{@"ok": @NO, @"message": @"Bad message."}];
        return;
    }

    NSDictionary *dict = (NSDictionary *)body;
    NSString *action = [dict[@"action"] isKindOfClass:[NSString class]] ? dict[@"action"] : @"";
    NSDictionary *payload = [dict[@"payload"] isKindOfClass:[NSDictionary class]] ? dict[@"payload"] : @{};
    os_log(SAWebLog(), "[SA] action=%{public}@ keys=%{public}@", action, [[payload allKeys] componentsJoinedByString:@","]);

    if (![SAWebBridge respondsToSelector:@selector(handle:payload:completion:)]) {
        os_log(SAWebLog(), "[SA] SAWebBridge missing");
        [self reply:context payload:@{@"ok": @NO, @"message": @"Bridge unavailable."}];
        return;
    }

    [SAWebBridge handle:action payload:payload completion:^(NSDictionary *response) {
        NSDictionary *out = [response isKindOfClass:[NSDictionary class]] ? response : @{@"ok": @NO, @"message": @"No response"};
        // If the bridge asks us to open the app, do it here.
        NSString *open = [out objectForKey:@"openURL"];
        if ([open isKindOfClass:[NSString class]] && open.length > 0) {
            NSURL *url = [NSURL URLWithString:open];
            if (url) {
                [context openURL:url completionHandler:^(BOOL success) {
                    os_log(SAWebLog(), "[SA] openURL(%{public}@) success=%{public}d", open, success);
                }];
            }
        }
        [self reply:context payload:out];
    }];
}

- (void)reply:(NSExtensionContext *)context payload:(NSDictionary *)payload {
    NSExtensionItem *response = [NSExtensionItem new];
    response.userInfo = @{ SFExtensionMessageKey: payload ?: @{} };
    [context completeRequestReturningItems:@[response] completionHandler:nil];
}

@end

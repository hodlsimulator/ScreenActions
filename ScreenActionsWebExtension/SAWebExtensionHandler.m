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
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.conornolan.Screen-Actions.WebExtension", "native");
    });
    return log;
}

@interface SAWebExtensionHandler : NSObject <NSExtensionRequestHandling>
@end

@implementation SAWebExtensionHandler

+ (void)load {
    os_log(SAWebLog(), "[SA] Obj-C principal loaded");
}

- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    os_log(SAWebLog(), "[SA] beginRequest");
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

    os_log(SAWebLog(), "[SA] action=%{public}@", action);

    [SAWebBridge handle:action payload:payload completion:^(NSDictionary *response) {
        [self reply:context payload:response ?: @{@"ok": @NO, @"message": @"No response"}];
    }];
}

- (void)reply:(NSExtensionContext *)context payload:(NSDictionary *)payload {
    NSExtensionItem *response = [[NSExtensionItem alloc] init];
    response.userInfo = @{ SFExtensionMessageKey: payload ?: @{} };
    [context completeRequestReturningItems:@[response] completionHandler:nil];
}

@end

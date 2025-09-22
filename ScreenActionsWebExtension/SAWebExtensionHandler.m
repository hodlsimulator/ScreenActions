//
//  SAWebExtensionHandler.m
//  ScreenActionsWebExtension
//
//  Created by . . on 9/22/25.
//

@import Foundation;
@import SafariServices;

// Import the auto-generated Swift header for this target.
// Xcode emits "ScreenActionsWebExtension-Swift.h" (or "...WebExtension2-Swift.h" if that’s your target name).
#if __has_include("ScreenActionsWebExtension-Swift.h")
#import "ScreenActionsWebExtension-Swift.h"
#elif __has_include("ScreenActionsWebExtension2-Swift.h")
#import "ScreenActionsWebExtension2-Swift.h"
#else
#warning "Build once so Xcode generates the <TargetName>-Swift.h header, then recompile."
#endif

@interface SAWebExtensionHandler : NSObject <NSExtensionRequestHandling>
@end

@implementation SAWebExtensionHandler

- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    NSExtensionItem *item = (NSExtensionItem *)context.inputItems.firstObject;
    NSDictionary *userInfo = item.userInfo ?: @{};
    id body = userInfo[SFExtensionMessageKey];
    if (![body isKindOfClass:[NSDictionary class]]) {
        [self reply:context payload:@{@"ok": @NO, @"message": @"Bad message."}];
        return;
    }

    NSDictionary *dict = (NSDictionary *)body;
    NSString *action = [dict[@"action"] isKindOfClass:[NSString class]] ? dict[@"action"] : @"";
    NSDictionary *payload = [dict[@"payload"] isKindOfClass:[NSDictionary class]] ? dict[@"payload"] : @{};

    // SAWebBridge is the Swift class annotated @objc(SAWebBridge)
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


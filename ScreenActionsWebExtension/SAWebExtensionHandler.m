//
//  SAWebExtensionHandler.m
//  ScreenActionsWebExtension
//
//  Created by . . on 9/22/25.
//
//  Objective-C principal that **conforms** to NSExtensionRequestHandling
//  and forwards to the Swift handler.
//

#import <Foundation/Foundation.h>
#import <SafariServices/SafariServices.h>
#import "ScreenActionsWebExtension-Swift.h" // auto-generated for this target

@interface SAWebExtensionHandler : NSObject <NSExtensionRequestHandling>
@end

@implementation SAWebExtensionHandler

// Safari calls this entrypoint when JS uses runtime.sendNativeMessage(...)
- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context
{
    // Forward to the Swift implementation (annotated @objc(SafariWebExtensionHandler)).
    SafariWebExtensionHandler *swiftHandler = [SafariWebExtensionHandler new];
    [swiftHandler beginRequestWithExtensionContext:context];
}

@end

//
//  SAWebExtensionHandler.m
//  ScreenActionsWebExtension
//
//  Created by . . on 9/22/25.
//

#import <Foundation/Foundation.h>
#import <SafariServices/SafariServices.h>
#import "ScreenActionsWebExtension-Swift.h" // auto-generated for this target

@interface SAWebExtensionHandler : NSObject <NSExtensionRequestHandling>
@end

@implementation SAWebExtensionHandler

// NOTE: The Objective-C selector is *beginRequestWithExtensionContext:*
// We forward to your Swift handler (class name exposed via @objc(SafariWebExtensionHandler)).
- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    SafariWebExtensionHandler *swiftHandler = [SafariWebExtensionHandler new];
    [swiftHandler beginRequestWithExtensionContext:context];
}

@end

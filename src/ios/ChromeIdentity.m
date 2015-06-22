// Copyright (c) 2013 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Cordova/CDVPlugin.h>
#import <Foundation/Foundation.h>
#import <GoogleSignIn/GoogleSignIn.h>
#import <GoogleOpenSource/GoogleOpenSource.h>
#import "AppDelegate.h"

#if CHROME_IDENTITY_VERBOSE_LOGGING
#define VERBOSE_LOG NSLog
#else
#define VERBOSE_LOG(args...) do {} while (false)
#endif

@interface ChromeIdentity : CDVPlugin <GIDSignInDelegate, GIDSignInUIDelegate>
@property (nonatomic, copy) NSString* callbackId;
@property BOOL interactive;
@end

static void swizzleMethod(Class class, SEL destinationSelector, SEL sourceSelector);

@implementation AppDelegate (IdentityUrlHandling)

+ (void)load
{
    // Add a necessary method to AppDelegate.
    swizzleMethod([AppDelegate class], @selector(application:openURL:sourceApplication:annotation:), @selector(identity_application:openURL:sourceApplication:annotation:));
}

- (BOOL)identity_application: (UIApplication *)application
                     openURL: (NSURL *)url
           sourceApplication: (NSString *)sourceApplication
                  annotation: (id)annotation {
    [self identity_application:application openURL:url sourceApplication:sourceApplication annotation:annotation];
    return [[GIDSignIn sharedInstance] handleURL:url
                               sourceApplication:sourceApplication
                                      annotation:annotation];
}

@end

@implementation ChromeIdentity

- (void)pluginInitialize
{
    GIDSignIn *signIn = [GIDSignIn sharedInstance];
    signIn.shouldFetchBasicProfile = YES;
    signIn.allowsSignInWithWebView = YES;
    // Apple will not approve apps that use safari to login
    signIn.allowsSignInWithBrowser = NO;
    [signIn setDelegate:self];
    [signIn setUiDelegate: self];
}

- (void)getAuthToken:(CDVInvokedUrlCommand*)command
{
    // Save the callback id for later.
    [self setCallbackId:[command callbackId]];
    self.interactive = [[command argumentAtIndex:0] boolValue];
    NSString* clientId = [command argumentAtIndex:1];
    NSArray* scopes = [command argumentAtIndex:2];

    // Extract the OAuth2 data.
    GIDSignIn *signIn = [GIDSignIn sharedInstance];
    [signIn setClientID:clientId];
    [signIn setScopes:scopes];

    // Authenticate!
    if (self.interactive) {
        [signIn signIn];
    } else {
        [signIn signInSilently];
    }
}

- (void)removeCachedAuthToken:(CDVInvokedUrlCommand*)command
{
    //NSString *token = [command argumentAtIndex:0];
    BOOL signOut = [[command argumentAtIndex:1] boolValue];
    //GIDGoogleUser *googleUser = [[GIDSignIn sharedInstance] currentUser];
    //GIDAuthentication *authentication = [googleUser authentication];

    // If the token to revoke is the same as the one we have cached, trigger a refresh.

    // TODO - not sure how to handle this with the google sign-in,
    // @see https://github.com/MobileChromeApps/cordova-plugin-chrome-apps-identity/issues/5#issuecomment-113340923
    // properties are read-only
    //    if ([[authentication accessToken] isEqualToString:token]) {
    //        [authentication setAccessToken:nil];
    //        [authentication authorizeRequest:nil completionHandler:nil];
    //    }

    if (signOut) {
        // save callbackId, to be used in signIn: didDisconnectWithUser
        [self setCallbackId:[command callbackId]];
        [[GIDSignIn sharedInstance] disconnect];

    } else {
        // Call the callback.
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [[self commandDelegate] sendPluginResult:pluginResult callbackId:[command callbackId]];
    }
}

- (void)getAccounts:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_INVALID_ACTION messageAsString:@"getAccounts not supported on iOS."];
    [[self commandDelegate] sendPluginResult:pluginResult callbackId:[command callbackId]];
}

#pragma mark GIDSignInDelegate

- (void)signIn:(GIDSignIn *)signIn didSignInForUser:(GIDGoogleUser *)user withError:(NSError *)error {
    NSString* callbackId = self.callbackId;
    CDVPluginResult *pluginResult;
    self.callbackId = nil;

    if (user == nil) {
        // an error on non-interactive mode should not return user cancelled, so we'll return:
        // -2 : "The request requires options.interactive=true"
        int errorCode = self.interactive ? -4 : -2;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsInt: errorCode];

    } else {
        // Compile the results.
        NSDictionary *resultDictionary = [[NSMutableDictionary alloc] init];
        [resultDictionary setValue:[user.profile email] forKey:@"account"];
        [resultDictionary setValue:[user.authentication accessToken] forKey:@"token"];

        // Pass the results to the callback.
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:resultDictionary];
    }
    [[self commandDelegate] sendPluginResult:pluginResult callbackId:callbackId];
}

- (void)signIn:(GIDSignIn *)signIn didDisconnectWithUser:(GIDGoogleUser *)user withError:(NSError *)error {
    NSString* callbackId = self.callbackId;
    CDVPluginResult *pluginResult;
    self.callbackId = nil;

    if (error == nil) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsInt: (int)error.code];
    }

    [[self commandDelegate] sendPluginResult:pluginResult callbackId: callbackId];
}

#pragma mark GIDSignInUIDelegate

- (void)signIn:(GIDSignIn *)signIn presentViewController:(UIViewController *)viewController {
    [[self viewController] presentViewController:viewController animated:YES completion:nil];
};

- (void)signIn:(GIDSignIn *)signIn dismissViewController:(UIViewController *)viewController {
    [viewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark Swizzling

@end

static void swizzleMethod(Class class, SEL destinationSelector, SEL sourceSelector)
{
    Method destinationMethod = class_getInstanceMethod(class, destinationSelector);
    Method sourceMethod = class_getInstanceMethod(class, sourceSelector);

    // If the method doesn't exist, add it.  If it does exist, replace it with the given implementation.
    if (class_addMethod(class, destinationSelector, method_getImplementation(sourceMethod), method_getTypeEncoding(sourceMethod))) {
        class_replaceMethod(class, destinationSelector, method_getImplementation(destinationMethod), method_getTypeEncoding(destinationMethod));
    } else {
        method_exchangeImplementations(destinationMethod, sourceMethod);
    }
}

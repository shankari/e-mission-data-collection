    //
//  AppDelegate.m
//  CFC_Tracker
//
//  Created by Kalyanaraman Shankari on 1/30/15.
//  Copyright (c) 2015 Kalyanaraman Shankari. All rights reserved.
//

#import "BEMAppDelegate.h"
#import "LocalNotificationManager.h"
#import "BEMConnectionSettings.h"
#import "AuthCompletionHandler.h"
#import "BEMRemotePushNotificationHandler.h"
#import "DataUtils.h"
#import "LocationTrackingConfig.h"
#import "ConfigManager.h"
#import "BEMServerSyncConfigManager.h"
#import "BEMServerSyncPlugin.h"
#import "Cordova/CDVConfigParser.h"
#import <Parse/Parse.h>
#import <objc/runtime.h>

@implementation AppDelegate (datacollection)

+ (BOOL)didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    ParseClientConfiguration* newConfig = [ParseClientConfiguration configurationWithBlock:^(id<ParseMutableClientConfiguration> configuration) {
        configuration.applicationId = [[ConnectionSettings sharedInstance] getParseAppID];
        configuration.clientKey = [[ConnectionSettings sharedInstance] getParseClientID];
        configuration.server = @"https://parseapi.back4app.com";
        NSLog(@"At the end of the config block, configuration = %@", configuration);
    }];
    
    if ([Parse currentConfiguration] == NULL) {
        NSLog(@"currentConfiguration = NULL, going ahead with config");
        [Parse initializeWithConfiguration:newConfig];
    } else {
        NSLog(@"currentConfiguration != NULL, skipping double config");
    }
    
    if ([UIApplication instancesRespondToSelector:@selector(registerUserNotificationSettings:)]) {
        [[UIApplication sharedApplication] registerUserNotificationSettings:[UIUserNotificationSettings
                settingsForTypes:UIUserNotificationTypeAlert|UIUserNotificationTypeBadge
                categories:nil]];
    }
    
    if ([BEMServerSyncConfigManager instance].ios_use_remote_push) {
        // NOP - this is handled in javascript
    } else {
        [BEMServerSyncPlugin applySync];
    }
    
    [LocalNotificationManager addNotification:[NSString stringWithFormat:
                                               @"Initialized remote push notification handler %@, finished registering for notifications ",
                                                [BEMRemotePushNotificationHandler instance]]
                                       showUI:FALSE];

    return YES;
}


- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    [LocalNotificationManager addNotification:[NSString stringWithFormat:
                                               @"Application went to the background"]];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    [LocalNotificationManager addNotification:[NSString stringWithFormat:
                                               @"Application will enter the foreground"]];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    [LocalNotificationManager addNotification:[NSString stringWithFormat:
                                               @"Application is about to terminate"]];
    [LocalNotificationManager showNotificationAfterSecs:[NSString stringWithFormat:
                                                         @"Please don't force-kill. It actually increases battery drain because we don't get silent push notifications and can't stop tracking properly. Click to relaunch."]
                                              secsLater:60];
}

- (void)application:(UIApplication*)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    if ([BEMServerSyncConfigManager instance].ios_use_remote_push == NO) {
        [AppDelegate launchTripEndCheckAndRemoteSync:completionHandler];
    } else {
        [LocalNotificationManager addNotification:[NSString stringWithFormat:
                                                   @"Received background fetch call, ignoring"]
                                           showUI:FALSE];
        completionHandler(UIBackgroundFetchResultNewData);
    }
}

// TODO: Figure out better solution for this.
// Maybe a separate plist instead of putting it into the config.xml?

+ (NSString*) getReqConsent
{
    NSString* path = [[NSBundle mainBundle] pathForResource:@"config.xml" ofType:nil];
    NSURL* url = [NSURL fileURLWithPath:path];

    NSXMLParser* configParser = [[NSXMLParser alloc] initWithContentsOfURL:url];
    if (configParser == nil) {
        NSLog(@"Failed to initialize XML parser.");
        return NULL;
    }
    CDVConfigParser* delegate = [[CDVConfigParser alloc] init];
    [configParser setDelegate:((id < NSXMLParserDelegate >)delegate)];
    [configParser parse];
    return [delegate.settings objectForKey:[@"emSensorDataCollectionProtocolApprovalDate" lowercaseString]];
}

+ (void) launchTripEndCheckAndRemoteSync:(void (^)(UIBackgroundFetchResult))completionHandler {
    [LocalNotificationManager addNotification:[NSString stringWithFormat:
                                               @"Received background sync call when useRemotePush = %@, about to check whether a trip has ended", @([BEMServerSyncConfigManager instance].ios_use_remote_push)]
                                       showUI:FALSE];
    NSLog(@"About to check whether a trip has ended");
    NSDictionary* localUserInfo = @{@"handler": completionHandler};
    [[AuthCompletionHandler sharedInstance] getValidAuth:^(GTMOAuth2Authentication *auth, NSError *error) {
        /*
         * Note that we do not condition any further tasks on this refresh. That is because, in general, we expect that
         * the token refreshed at this time will be used to push the next set of values. This is just pre-emptive refreshing,
         * to increase the chance that we will finish pushing our data within the 30 sec interval.
         */
        if (error == NULL) {
            GTMOAuth2Authentication* currAuth = [AuthCompletionHandler sharedInstance].currAuth;
            [LocalNotificationManager addNotification:[NSString stringWithFormat:
                                                       @"Finished refreshing token in background, new expiry is %@", currAuth.expirationDate]
                                               showUI:FALSE];
        } else {
            [LocalNotificationManager addNotification:[NSString stringWithFormat:
                                                       @"Error %@ while refreshing token in background", error]
                                               showUI:TRUE];
        }
    } forceRefresh:TRUE];
    [[NSNotificationCenter defaultCenter] postNotificationName:CFCTransitionNotificationName object:CFCTransitionRecievedSilentPush userInfo:localUserInfo];
    [AppDelegate checkNativeConsent];
}

+ (void) checkNativeConsent {
    BOOL isConsented = [ConfigManager isConsented:[AppDelegate getReqConsent]];
    if (!isConsented) {
        [LocalNotificationManager showNotification:@"New data collection terms - collection paused until consent"];
    }
}

@end

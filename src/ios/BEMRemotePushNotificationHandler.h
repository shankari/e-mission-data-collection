#import "BEMServerSyncCommunicationHelper.h"

@interface BEMRemotePushNotificationHandler : NSObject
+ (BEMRemotePushNotificationHandler*) instance;
- (void) handleNotifications:(NSNotification*)note;
@property NSMutableArray* silentPushHandlerList;

@end

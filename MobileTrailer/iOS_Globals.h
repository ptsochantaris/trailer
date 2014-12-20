
@import UIKit;

// C duplicates to remove when everything is ported
#define COLOR_CLASS UIColor
#define FONT_CLASS UIFont
#define MAKECOLOR(R,G,B,A) [COLOR_CLASS colorWithRed:R green:G blue:B alpha:A]
//

#define REFRESH_STARTED_NOTIFICATION @"RefreshStartedNotification"
#define REFRESH_ENDED_NOTIFICATION @"RefreshEndedNotification"
#define RECEIVED_NOTIFICATION_KEY @"ReceivedNotificationKey"

#import "GlobalsObjC.h"

#import "iOS_AppDelegate.h"
extern iOS_AppDelegate *app;

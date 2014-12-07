#import "API.h"

@interface iOS_AppDelegate : UIResponder <UIApplicationDelegate, UIPopoverControllerDelegate, UISplitViewControllerDelegate>

@property (strong, nonatomic) UIWindow *window;

typedef void (^backgroundFetchCompletionCallback)(UIBackgroundFetchResult result);

@property (nonatomic) BOOL preferencesDirty, isRefreshing, lastUpdateFailed, enteringForeground;
@property (nonatomic) NSDate *lastSuccessfulRefresh, *lastRepoCheck;
@property (nonatomic) NSTimer *refreshTimer;
@property (nonatomic,copy) backgroundFetchCompletionCallback backgroundCallback;

- (void)postNotificationOfType:(PRNotificationType)type forItem:(id)item;

- (BOOL)startRefresh;

- (void)refreshMainList;

- (void)shareFromView:(UIViewController *)view buttonItem:(UIBarButtonItem *)button url:(NSURL *)url;

@end


@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

typedef void (^backgroundFetchCompletionCallback)(UIBackgroundFetchResult result);

@property (nonatomic) API *api;
@property (nonatomic) DataManager *dataManager;
@property (nonatomic) BOOL preferencesDirty, isRefreshing, lastUpdateFailed, enteringForeground;
@property (nonatomic) NSDate *lastSuccessfulRefresh, *lastRepoCheck;
@property (nonatomic) NSTimer *refreshTimer;
@property (nonatomic,copy) backgroundFetchCompletionCallback backgroundCallback;
@property (nonatomic) NSString *currentAppVersion;

+ (AppDelegate *)shared;

- (void)postNotificationOfType:(PRNotificationType)type forItem:(id)item;

- (void)startRefresh;

@end

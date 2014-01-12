
@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

typedef void (^backgroundFetchCompletionCallback)(UIBackgroundFetchResult result);

@property (nonatomic) API *api;
@property (nonatomic) DataManager *dataManager;
@property (nonatomic) BOOL preferencesDirty, isRefreshing, lastUpdateFailed;
@property (nonatomic) NSDate *lastSuccessfulRefresh;
@property (nonatomic) NSTimer *refreshTimer;
@property (nonatomic,copy) backgroundFetchCompletionCallback backgroundCallback;

+ (AppDelegate *)shared;

- (void)postNotificationOfType:(PRNotificationType)type forItem:(id)item;

- (void)startRefresh;

- (void)updateBadge;

@end

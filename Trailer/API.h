
#define TRAILER_GITHUB_REPO @"http://dev.housetrip.com/trailer/"
#define LOW_API_WARNING 0.10

typedef enum {
	kNewComment = 0,
	kNewPr = 1,
	kPrMerged = 2,
	kNewMention = 4,
	kPrClosed = 5,
	kNewRepoSubscribed = 6
} PRNotificationType;

typedef enum {
	kCreationDate = 0,
	kRecentActivity = 1,
	kTitle = 2,
	kRepository = 3
} PRSortingMethod;

typedef enum {
	kRepoAutoSubscribeNone = 0,
	kRepoAutoSubscribeParentsOnly = 1,
	kRepoDontAutoSubscribeAll = 2,
} PRSubscriptionPolicy;

#define PULL_REQUEST_ID_KEY @"pullRequestIdKey"
#define COMMENT_ID_KEY @"commentIdKey"
#define NOTIFICATION_URL_KEY @"urlKey"

#define RATE_UPDATE_NOTIFICATION @"RateUpdateNotification"

#define NETWORK_TIMEOUT 60.0

@interface API : NSObject

@property (nonatomic) NSString *resetDate;
@property (nonatomic) float requestsLimit, requestsRemaining;
@property (nonatomic) Reachability *reachability;

- (void)updateLimitFromServer;

- (void) fetchRepositoriesAndCallback:(void(^)(BOOL success))callback;

- (void) fetchPullRequestsForActiveReposAndCallback:(void(^)(BOOL success))callback;

- (void) getRateLimitAndCallback:(void(^)(long long remaining, long long limit, long long reset))callback;

- (void)testApiAndCallback:(void(^)(NSError *error))callback;

- (void)expireOldImageCacheEntries;

- (void)clearImageCache;

- (void)restartNotifier;

- (BOOL)haveCachedImage:(NSString *)path
                forSize:(CGSize)imageSize
     tryLoadAndCallback:(void(^)(id image))callbackOrNil;

@end

#import "Reachability.h"

#define LOW_API_WARNING 0.20

#define kPullRequestConditionOpen 0
#define kPullRequestConditionClosed 1
#define kPullRequestConditionMerged 2

#define kPullRequestSectionNone 0
#define kPullRequestSectionMine 1
#define kPullRequestSectionParticipated 2
#define kPullRequestSectionMerged 3
#define kPullRequestSectionClosed 4
#define kPullRequestSectionAll 5

#define kStatusFilterAll 0
#define kStatusFilterInclude 1
#define kStatusFilterExclude 2

#define kPullRequestSectionNames @[@"", @"Mine", @"Participated", @"Recently Merged", @"Recently Closed", @"All Pull Requests"]

typedef NS_ENUM(NSInteger, PostSyncAction) {
	kPostSyncDoNothing = 0,
	kPostSyncDelete,
	kPostSyncNoteNew,
	kPostSyncNoteUpdated
};

typedef NS_ENUM(NSInteger, PRNotificationType) {
	kNewComment = 0,
	kNewPr,
	kPrMerged,
	kPrReopened,
	kNewMention,
	kPrClosed,
	kNewRepoSubscribed,
	kNewRepoAnnouncement,
	kNewPrAssigned
};

typedef NS_ENUM(NSInteger, PRSortingMethod) {
	kCreationDate = 0,
	kRecentActivity,
	kTitle,
	kRepository,
};

typedef NS_ENUM(NSInteger, PRSubscriptionPolicy) {
	kRepoAutoSubscribeNone = 0,
	kRepoAutoSubscribeParentsOnly,
	kRepoDontAutoSubscribeAll,
};

typedef NS_ENUM(NSInteger, PRHandlingPolicy) {
	kPullRequestHandlingKeepMine = 0,
	kPullRequestHandlingKeepAll,
	kPullRequestHandlingKeepNone,
};

typedef void (^completionBlockType)();

#define PULL_REQUEST_ID_KEY @"pullRequestIdKey"
#define COMMENT_ID_KEY @"commentIdKey"
#define NOTIFICATION_URL_KEY @"urlKey"

#define API_USAGE_UPDATE @"RateUpdateNotification"

#define NETWORK_TIMEOUT 120.0
#define BACKOFF_STEP 120.0

@class ApiServer;

@interface API : NSObject

@property (nonatomic) Reachability *reachability;
@property (nonatomic) long successfulRefreshesSinceLastStatusCheck, successfulRefreshesSinceLastLabelCheck;

- (void)updateLimitsFromServer;

- (void)fetchRepositoriesToMoc:(NSManagedObjectContext *)moc
				   andCallback:(completionBlockType)callback;

- (void)fetchPullRequestsForActiveReposAndCallback:(completionBlockType)callback;

- (void)getRateLimitFromServer:(ApiServer *)apiServer
				   andCallback:(void(^)(long long remaining, long long limit, long long reset))callback;

- (void)testApiToServer:(ApiServer *)apiServer andCallback:(void (^)(NSError *))callback;

- (void)expireOldImageCacheEntries;

- (void)clearImageCache;

- (NSString *)lastUpdateDescription;

- (BOOL)haveCachedAvatar:(NSString *)path
	  tryLoadAndCallback:(void(^)(IMAGE_CLASS *image))callbackOrNil;

@end

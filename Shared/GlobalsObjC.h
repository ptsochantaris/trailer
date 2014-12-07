
@import CoreData;

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
#define DARK_MODE_CHANGED @"DarkModeChangedNotificationKey"

#define NETWORK_TIMEOUT 120.0
#define BACKOFF_STEP 120.0
#define STATUSITEM_PADDING 1.0

void DLog(NSString *format, ...);
extern NSString *currentAppVersion;

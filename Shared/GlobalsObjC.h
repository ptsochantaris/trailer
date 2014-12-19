
@import CoreData;

typedef NS_ENUM(NSInteger, PullRequestCondition) {
	kPullRequestConditionOpen = 0,
	kPullRequestConditionClosed,
	kPullRequestConditionMerged
};

typedef NS_ENUM(NSInteger, PullRequestSection) {
	kPullRequestSectionNone = 0,
	kPullRequestSectionMine,
	kPullRequestSectionParticipated,
	kPullRequestSectionMerged,
	kPullRequestSectionClosed,
	kPullRequestSectionAll
};

typedef NS_ENUM(NSInteger, StatusFilter) {
	kStatusFilterAll = 0,
	kStatusFilterInclude,
	kStatusFilterExclude
};

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

#define PULL_REQUEST_ID_KEY @"pullRequestIdKey"
#define COMMENT_ID_KEY @"commentIdKey"
#define NOTIFICATION_URL_KEY @"urlKey"
#define API_USAGE_UPDATE @"RateUpdateNotification"
#define DARK_MODE_CHANGED @"DarkModeChangedNotificationKey"
#define PR_ITEM_FOCUSED_STATE_KEY @"PrItemFocusedStateKey"
#define UPDATE_VIBRANCY_NOTIFICATION @"UpdateVibrancyNotfication"

extern CGFloat LOW_API_WARNING;
extern NSTimeInterval NETWORK_TIMEOUT;
extern NSTimeInterval BACKOFF_STEP;

#define CALLBACK if(callback) callback

void DLog(NSString *format, ...);
extern NSString *currentAppVersion;
extern NSArray *kPullRequestSectionNames;
extern NSStringDrawingOptions stringDrawingOptions;

#import "Reachability.h"

@class API;
extern API *api;

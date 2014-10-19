
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

@class PRComment, PRStatus;

@interface PullRequest : DataItem

@property (nonatomic, retain) NSString * url;
@property (nonatomic, retain) NSNumber * number;
@property (nonatomic, retain) NSString * state;
@property (nonatomic, retain) NSString * title;
@property (nonatomic, retain) NSString * body;
@property (nonatomic, retain) NSString * issueCommentLink;
@property (nonatomic, retain) NSString * reviewCommentLink;
@property (nonatomic, retain) NSString * statusesLink;
@property (nonatomic, retain) NSDate * updatedAt;
@property (nonatomic, retain) NSNumber * serverId;
@property (nonatomic, retain) NSNumber * postSyncAction;
@property (nonatomic, retain) NSString * webUrl;
@property (nonatomic, retain) NSNumber * userId;
@property (nonatomic, retain) NSString * userAvatarUrl;
@property (nonatomic, retain) NSString * userLogin;
@property (nonatomic, retain) NSString * repoName;
@property (nonatomic, retain) NSDate * latestReadCommentDate;
@property (nonatomic, retain) NSNumber * condition;
@property (nonatomic, retain) NSNumber * mergeable;
@property (nonatomic, retain) NSNumber * reopened;
@property (nonatomic, retain) NSNumber * assignedToMe;
@property (nonatomic, retain) NSNumber * isNewAssignment;

@property (nonatomic, retain) NSString * issueUrl;

@property (nonatomic, retain) NSNumber * totalComments;
@property (nonatomic, retain) NSNumber * unreadComments;

@property (nonatomic, retain) NSNumber * sectionIndex;
@property (nonatomic, readonly) NSString * sectionName;

@property (nonatomic, retain) NSSet *comments;
@property (nonatomic, retain) Repo *repo;
@property (nonatomic, retain) NSSet *statuses;

+ (PullRequest *)pullRequestWithInfo:(NSDictionary*)info fromServer:(ApiServer *)apiServer;

+ (NSFetchRequest *)requestForPullRequestsWithFilter:(NSString *)filter;

+ (NSArray *)allMergedRequestsInMoc:(NSManagedObjectContext *)moc;

+ (NSArray *)allClosedRequestsInMoc:(NSManagedObjectContext *)moc;

+ (NSUInteger)countOpenRequestsInMoc:(NSManagedObjectContext *)moc;

+ (NSInteger)badgeCountInMoc:(NSManagedObjectContext *)moc;

- (void)catchUpWithComments;

- (BOOL)isMine;

- (BOOL)refersToMe;

- (BOOL)commentedByMe;

- (BOOL)markUnmergeable;

- (void)postProcess;

- (NSMutableAttributedString *)subtitleWithFont:(FONT_CLASS *)font;

- (NSString *)accessibleSubtitle;

- (NSArray *)displayedStatuses;

- (NSString *)urlForOpening;

@end

@interface PullRequest (CoreDataGeneratedAccessors)

- (void)addCommentsObject:(PRComment *)value;
- (void)removeCommentsObject:(PRComment *)value;
- (void)addComments:(NSSet *)values;
- (void)removeComments:(NSSet *)values;

- (void)addStatusesObject:(PRStatus *)value;
- (void)removeStatusesObject:(PRStatus *)value;
- (void)addStatuses:(NSSet *)values;
- (void)removeStatuses:(NSSet *)values;

@end

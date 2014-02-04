
#define kPullRequestConditionOpen 0
#define kPullRequestConditionClosed 1
#define kPullRequestConditionMerged 2

#define kPullRequestSectionMine 0
#define kPullRequestSectionParticipated 1
#define kPullRequestSectionMerged 2
#define kPullRequestSectionClosed 3
#define kPullRequestSectionAll 4

#define kPullRequestSectionNames @[@"Mine", @"Participated", @"Recently Merged", @"Recently Closed", @"All Pull Requests"]

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
@property (nonatomic, retain) NSNumber *repoId;
@property (nonatomic, retain) NSNumber *condition;
@property (nonatomic, retain) NSNumber *mergeable;

@property (nonatomic, retain) NSNumber *totalComments;
@property (nonatomic, retain) NSNumber *unreadComments;

@property (nonatomic, retain) NSNumber *sectionIndex;
@property (nonatomic, readonly) NSString *sectionName;

+ (PullRequest *)pullRequestWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext *)moc;

+ (PullRequest *)pullRequestWithUrl:(NSString *)url moc:(NSManagedObjectContext *)moc;

+ (NSFetchRequest *)requestForPullRequestsWithFilter:(NSString *)filter;

+ (NSArray *)allMergedRequestsInMoc:(NSManagedObjectContext *)moc;

+ (NSArray *)allClosedRequestsInMoc:(NSManagedObjectContext *)moc;

+ (NSUInteger)countOpenRequestsInMoc:(NSManagedObjectContext *)moc;

- (void)catchUpWithComments;

- (BOOL)isMine;

- (BOOL)refersToMe;

- (BOOL)commentedByMe;

- (void)postProcess;

- (NSString *)subtitle;

- (NSArray *)displayedStatuses;

@end

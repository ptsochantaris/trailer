
@interface PRComment : DataItem

@property (nonatomic, retain) NSNumber * serverId;
@property (nonatomic, retain) NSNumber * postSyncAction;
@property (nonatomic, retain) NSDate * updatedAt;
@property (nonatomic, retain) NSNumber * position;
@property (nonatomic, retain) NSString * body;
@property (nonatomic, retain) NSString * userName;
@property (nonatomic, retain) NSString * avatarUrl;
@property (nonatomic, retain) NSString * path;
@property (nonatomic, retain) NSString * url;
@property (nonatomic, retain) NSString * pullRequestUrl;
@property (nonatomic, retain) NSString * webUrl;
@property (nonatomic, retain) NSNumber * userId;

+ (PRComment *)commentWithInfo:(NSDictionary *)info moc:(NSManagedObjectContext *)moc;

+ (void)removeCommentsWithPullRequestURL:(NSString *)url inMoc:(NSManagedObjectContext *)moc;

+ (NSArray *)commentsForPullRequestUrl:(NSString *)url inMoc:(NSManagedObjectContext *)moc;

- (BOOL)isMine;

- (BOOL)refersToMe;

@end

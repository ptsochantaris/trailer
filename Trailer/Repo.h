
@interface Repo : DataItem

@property (nonatomic, retain) NSString * fullName;
@property (nonatomic, retain) NSString * webUrl;
@property (nonatomic, retain) NSNumber * fork;
@property (nonatomic, retain) NSNumber * hidden;
@property (nonatomic, retain) NSNumber * dirty;
@property (nonatomic, retain) NSDate * lastDirtied;
@property (nonatomic, retain) NSNumber * inaccessible;

+ (Repo*)repoWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext *)moc;

+ (NSArray *)visibleReposInMoc:(NSManagedObjectContext *)moc;

+ (NSUInteger)countVisibleReposInMoc:(NSManagedObjectContext *)moc;

+ (NSArray *)syncableReposInMoc:(NSManagedObjectContext *)moc;

+ (NSArray *)unsyncableReposInMoc:(NSManagedObjectContext *)moc;

+ (NSArray *)inaccessibleReposInMoc:(NSManagedObjectContext *)moc;

+ (void)markDirtyReposWithIds:(NSSet *)ids inMoc:(NSManagedObjectContext *)moc;

- (void)removeAllRelatedPullRequests;

@end

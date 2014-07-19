
@interface Repo : DataItem

@property (nonatomic, retain) NSString * fullName;
@property (nonatomic, retain) NSString * webUrl;
@property (nonatomic, retain) NSNumber * fork;
@property (nonatomic, retain) NSNumber * hidden;
@property (nonatomic, retain) NSNumber * dirty;

+ (Repo*)repoWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext *)moc;

+ (NSArray *)visibleReposInMoc:(NSManagedObjectContext *)moc;

+ (NSUInteger)countVisibleReposInMoc:(NSManagedObjectContext *)moc;

+ (NSArray *)dirtyReposInMoc:(NSManagedObjectContext *)moc;

+ (NSArray *)hiddenReposInMoc:(NSManagedObjectContext *)moc;

+ (void)markDirtyReposWithIds:(NSSet *)ids inMoc:(NSManagedObjectContext *)moc;

- (void)removeAllRelatedPullRequests;

@end

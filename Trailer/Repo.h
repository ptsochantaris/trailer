
@interface Repo : DataItem

@property (nonatomic, retain) NSString * fullName;
@property (nonatomic, retain) NSString * webUrl;
@property (nonatomic, retain) NSNumber * fork;
@property (nonatomic, retain) NSNumber * hidden;

+ (Repo*)repoWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext *)moc;

+ (NSArray *)visibleReposInMoc:(NSManagedObjectContext *)moc;

+ (NSUInteger)countVisibleReposInMoc:(NSManagedObjectContext *)moc;

@end

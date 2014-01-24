
@interface Repo : DataItem

@property (nonatomic, retain) NSString * fullName;
@property (nonatomic, retain) NSNumber * active;
@property (nonatomic, retain) NSNumber * fork;

+ (Repo*)repoWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext *)moc;

+ (NSArray *)activeReposInMoc:(NSManagedObjectContext *)moc;

@end


@interface Repo : DataItem

@property (nonatomic, retain) NSString * fullName;
@property (nonatomic, retain) NSNumber * active;

+(Repo*)repoWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext *)moc;

+(NSArray*)allReposSortedByField:(NSString*)fieldName withTitleFilter:(NSString *)titleFilterOrNil inMoc:(NSManagedObjectContext *)moc;

+(NSArray*)activeReposInMoc:(NSManagedObjectContext *)moc;

@end

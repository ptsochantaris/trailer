
@interface Repo : DataItem

@property (nonatomic, retain) NSString * fullName;
@property (nonatomic, retain) NSString * webUrl;
@property (nonatomic, retain) NSNumber * fork;

+ (Repo*)repoWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext *)moc;

@end

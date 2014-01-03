
@interface Org : DataItem

@property (nonatomic, retain) NSString * avatarUrl;
@property (nonatomic, retain) NSString * login;

+(Org*)orgWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext*)moc;

@end

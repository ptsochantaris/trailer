
enum PostSyncAction {
	kPostSyncDoNothing = 0,
	kPostSyncDelete = 1,
	kPostSyncNoteNew = 2,
	kPostSyncNoteUpdated = 3
	};

@interface DataItem : NSManagedObject

@property (nonatomic, retain) NSNumber * serverId;
@property (nonatomic, retain) NSNumber * postSyncAction;
@property (nonatomic, retain) NSDate * updatedAt, * createdAt;

+(id)itemOfType:(NSString*)type serverId:(NSNumber*)serverId moc:(NSManagedObjectContext*)moc;

+(NSArray *)allItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+(id)itemWithInfo:(NSDictionary*)info type:(NSString*)type moc:(NSManagedObjectContext*)moc;

+(void)nukeDeletedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+(NSUInteger)countItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+(NSArray*)newOrUpdatedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+(NSArray*)updatedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+(NSArray*)newItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+(NSArray*)itemsOfType:(NSString *)type surviving:(BOOL)survivingItems inMoc:(NSManagedObjectContext *)moc;

@end

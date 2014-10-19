
enum PostSyncAction {
	kPostSyncDoNothing = 0,
	kPostSyncDelete,
	kPostSyncNoteNew,
	kPostSyncNoteUpdated
	};

@interface DataItem : NSManagedObject

@property (nonatomic, retain) NSNumber * serverId;
@property (nonatomic, retain) NSNumber * postSyncAction;
@property (nonatomic, retain) NSDate * updatedAt, * createdAt;
@property (nonatomic, retain) ApiServer *apiServer;

+ (NSArray *)allItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+ (NSArray *)allItemsOfType:(NSString *)type fromServer:(ApiServer *)apiServer;

+ (id)itemWithInfo:(NSDictionary*)info type:(NSString*)type fromServer:(ApiServer *)apiServer;

+ (NSArray*)itemsOfType:(NSString *)type surviving:(BOOL)survivingItems inMoc:(NSManagedObjectContext *)moc;

+ (NSArray*)newOrUpdatedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+ (NSArray*)updatedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+ (NSArray*)newItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+ (void)nukeDeletedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+ (NSUInteger)countItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

@end

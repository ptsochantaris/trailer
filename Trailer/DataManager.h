
@interface DataManager : NSObject

// Core Data
@property (readonly, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (readonly, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (nonatomic) BOOL justMigrated;

- (BOOL)saveDB;

- (void)sendNotifications;

- (NSDictionary *)infoForType:(PRNotificationType)type item:(id)item;

- (void)postMigrationTasks;

- (void)postProcessAllPrs;

@end

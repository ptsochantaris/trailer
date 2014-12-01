#import "API.h"

@interface DataManager : NSObject

@property (nonatomic) NSManagedObjectContext *managedObjectContext;

- (BOOL)saveDB;

- (void)sendNotifications;

- (void)deleteEverything;

- (NSDictionary *)infoForType:(PRNotificationType)type item:(id)item;

- (void)postMigrationTasks;

- (void)postProcessAllPrs;

- (NSAttributedString *)reasonForEmptyWithFilter:(NSString *)filterValueOrNil;

- (NSManagedObjectID *)idForUriPath:(NSString *)uriPath;

- (NSManagedObjectContext *)tempContext;

@end

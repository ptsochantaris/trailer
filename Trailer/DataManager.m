
@implementation DataManager

@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize managedObjectContext = _managedObjectContext;

-(void)sendNotifications
{
	NSArray *latestPrs = [PullRequest newItemsOfType:@"PullRequest" inMoc:self.managedObjectContext];
	for(PullRequest *r in latestPrs)
	{
		[[AppDelegate shared] postNotificationOfType:kNewPr forItem:r];
		r.postSyncAction = @(kPostSyncDoNothing);
	}

	NSArray *latestComments = [PRComment newItemsOfType:@"PRComment" inMoc:self.managedObjectContext];
	for(PRComment *c in latestComments)
	{
		PullRequest *r = [PullRequest pullRequestWithUrl:c.pullRequestUrl moc:self.managedObjectContext];
		if([Settings shared].showCommentsEverywhere || r.isMine || r.commentedByMe)
		{
			if(![c.userId.stringValue isEqualToString:[Settings shared].localUserId])
			{
				[[AppDelegate shared] postNotificationOfType:kNewComment forItem:c];
			}
		}
		c.postSyncAction = @(kPostSyncDoNothing);
	}
}

// Returns the directory the application uses to store the Core Data store file. This code uses a directory named "com.housetrip.Trailer" in the user's Application Support directory.
- (NSURL *)applicationFilesDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *appSupportURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
    appSupportURL = [appSupportURL URLByAppendingPathComponent:@"com.housetrip.Trailer"];
	DLog(@"Files in %@",appSupportURL);
	return appSupportURL;
}

// Creates if necessary and returns the managed object model for the application.
- (NSManagedObjectModel *)managedObjectModel
{
    if (_managedObjectModel) {
        return _managedObjectModel;
    }

    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Trailer" withExtension:@"momd"];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

// Returns the persistent store coordinator for the application. This implementation creates and return a coordinator, having added the store for the application to it. (The directory for the store is created, if necessary.)
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (_persistentStoreCoordinator) {
        return _persistentStoreCoordinator;
    }

    NSManagedObjectModel *mom = [self managedObjectModel];
	NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:mom];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *applicationFilesDirectory = [self applicationFilesDirectory];
    NSError *error = nil;

    NSDictionary *properties = [applicationFilesDirectory resourceValuesForKeys:@[NSURLIsDirectoryKey] error:&error];

    if (!properties) {
        BOOL ok = NO;
        if ([error code] == NSFileReadNoSuchFileError) {
            ok = [fileManager createDirectoryAtPath:[applicationFilesDirectory path] withIntermediateDirectories:YES attributes:nil error:&error];
        }
        if (!ok) {
			DLog(@"%@",error);
            return nil;
        }
    } else {
        if (![properties[NSURLIsDirectoryKey] boolValue]) {
            // Customize and localize this error.
            NSString *failureDescription = [NSString stringWithFormat:@"Expected a folder to store application data, found a file (%@).", [applicationFilesDirectory path]];

            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            [dict setValue:failureDescription forKey:NSLocalizedDescriptionKey];
            error = [NSError errorWithDomain:@"YOUR_ERROR_DOMAIN" code:101 userInfo:dict];

			DLog(@"%@",error);
            return nil;
        }
    }

	NSURL *sqlStore = [applicationFilesDirectory URLByAppendingPathComponent:@"Trailer.sqlite"];

#ifdef __MAC_OS_X_VERSION_MIN_REQUIRED
	// migrate to SQLite if needed
    NSURL *xmlStore = [applicationFilesDirectory URLByAppendingPathComponent:@"Trailer.storedata"];
	if([fileManager fileExistsAtPath:xmlStore.path])
	{
		DLog(@"MIGRATING TO SQLITE");
		[self removeDatabaseFiles];

		NSPersistentStore *xml = [coordinator addPersistentStoreWithType:NSXMLStoreType
														   configuration:nil
																	 URL:xmlStore
																 options:@{ NSMigratePersistentStoresAutomaticallyOption: @YES,
																			NSInferMappingModelAutomaticallyOption: @YES }
																   error:nil];

		if([coordinator migratePersistentStore:xml
										 toURL:sqlStore
									   options:nil
									  withType:NSSQLiteStoreType
										 error:nil])
		{
			[fileManager removeItemAtURL:xmlStore error:nil];
			DLog(@"Deleted old XML store");
		}
		self.justMigrated = YES;
	}
	else
	{
#endif
		NSDictionary *m = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType URL:sqlStore error:&error];
		self.justMigrated = ![mom isConfiguration:nil compatibleWithStoreMetadata:m];

		if(![self addStorePath:sqlStore toCoordinator:coordinator])
		{
			DLog(@"Failed to migrate/load DB store - will nuke it and retry");
			[[NSFileManager defaultManager] removeItemAtURL:sqlStore error:nil];
			if(![self addStorePath:sqlStore toCoordinator:coordinator])
			{
				DLog(@"Catastrophic failure, app is probably corrupted and needs reinstall");
				abort();
			}
		}
#ifdef __MAC_OS_X_VERSION_MIN_REQUIRED
	}
#endif
    _persistentStoreCoordinator = coordinator;

    return _persistentStoreCoordinator;
}

- (BOOL)addStorePath:(NSURL *)sqlStore toCoordinator:(NSPersistentStoreCoordinator *)coordinator
{
	NSError *error = nil;
	NSPersistentStore *store = [coordinator addPersistentStoreWithType:NSSQLiteStoreType
														 configuration:nil
																   URL:sqlStore
															   options:@{ NSMigratePersistentStoresAutomaticallyOption: @YES,
																		  NSInferMappingModelAutomaticallyOption: @YES }
																 error:&error];
	if(error) DLog(@"%@",error);
	return store!=nil;
}

- (void)removeDatabaseFiles
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *documentsDirectory = [self applicationFilesDirectory].path;
    NSArray *files = [fm contentsOfDirectoryAtPath:documentsDirectory error:nil];
    for(NSString *file in files)
    {
        if([file rangeOfString:@"Trailer.sqlite"].location!=NSNotFound)
        {
            DLog(@"Removing old database file: %@",file);
            [fm removeItemAtPath:[documentsDirectory stringByAppendingPathComponent:file] error:nil];
        }
    }
}

// Returns the managed object context for the application (which is already bound to the persistent store coordinator for the application.)
- (NSManagedObjectContext *)managedObjectContext
{
    if (_managedObjectContext) {
        return _managedObjectContext;
    }

    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (!coordinator) {
		NSFileManager *fm = [NSFileManager defaultManager];
		NSURL *applicationFilesDirectory = [self applicationFilesDirectory];
		NSURL *url = [applicationFilesDirectory URLByAppendingPathComponent:@"Trailer.storedata"];
		[fm removeItemAtURL:url error:nil];
        return self.managedObjectContext;
    }
    _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
	_managedObjectContext.undoManager = nil;
    [_managedObjectContext setPersistentStoreCoordinator:coordinator];

    return _managedObjectContext;
}

- (BOOL)saveDB
{
	if(self.managedObjectContext.hasChanges)
		return [self.managedObjectContext save:nil];
	return YES;
}

- (NSDictionary *)infoForType:(PRNotificationType)type item:(id)item
{
	switch (type)
	{
		case kNewComment:
			return @{COMMENT_ID_KEY:[item serverId]};
		case kNewPr:
			return @{PULL_REQUEST_ID_KEY:[item serverId]};
		case kPrMerged:
			return @{NOTIFICATION_URL_KEY:[item webUrl]};
		default:
			return nil;
	}
}

@end

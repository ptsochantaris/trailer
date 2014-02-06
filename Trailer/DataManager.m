
@implementation DataManager

@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize managedObjectContext = _managedObjectContext;

- (id)init
{
    self = [super init];
    if (self)
	{
		//
		// will leave this in for a while to clear databases from orphaned PRStatus objects
		//
		NSArray *statuses = [DataItem allItemsOfType:@"PRStatus" inMoc:self.managedObjectContext];
		for(PRStatus *s in statuses)
		{
			PullRequest *r = [PullRequest itemOfType:@"PullRequest" serverId:s.pullRequestId moc:self.managedObjectContext];
			if(!r)
			{
				DLog(@"Deleting orphaned PRStatus item %@",s.serverId);
				[self.managedObjectContext deleteObject:s];
			}
		}
    }
    return self;
}

- (void)sendNotifications
{
	NSManagedObjectContext *mainContext = self.managedObjectContext;

	NSArray *latestPrs = [PullRequest newItemsOfType:@"PullRequest" inMoc:mainContext];
	for(PullRequest *r in latestPrs)
	{
		if(!r.isMine)
			[[AppDelegate shared] postNotificationOfType:kNewPr forItem:r];
		r.postSyncAction = @(kPostSyncDoNothing);
	}

	NSArray *latestComments = [PRComment newItemsOfType:@"PRComment" inMoc:mainContext];
	for(PRComment *c in latestComments)
	{
		PullRequest *r = [PullRequest pullRequestWithUrl:c.pullRequestUrl moc:mainContext];
		if(r.postSyncAction.integerValue == kPostSyncNoteUpdated)
		{
			if(c.refersToMe)
			{
				[[AppDelegate shared] postNotificationOfType:kNewMention forItem:c];
			}
			else if([Settings shared].showCommentsEverywhere || r.isMine || r.commentedByMe)
			{
				if(![c.userId.stringValue isEqualToString:[Settings shared].localUserId])
				{
					[[AppDelegate shared] postNotificationOfType:kNewComment forItem:c];
				}
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
			[self removeDatabaseFiles];
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
		case kNewMention:
		case kNewComment:
			return @{COMMENT_ID_KEY:[item serverId]};
		case kNewPr:
			return @{PULL_REQUEST_ID_KEY:[item serverId]};
		case kPrClosed:
		case kPrMerged:
			return @{NOTIFICATION_URL_KEY:[item webUrl], PULL_REQUEST_ID_KEY:[item serverId]};
		default:
			return nil;
	}
}

- (void)postMigrationTasks
{
	if(self.justMigrated)
	{
		DLog(@"FORCING ALL PRS TO BE REFETCHED");
		NSArray *prs = [PullRequest allItemsOfType:@"PullRequest" inMoc:self.managedObjectContext];
		for(PullRequest *r in prs) r.updatedAt = [NSDate distantPast];
		self.justMigrated = NO;
	}
}

- (void)postProcessAllPrs
{
	NSArray *prs = [PullRequest allItemsOfType:@"PullRequest" inMoc:self.managedObjectContext];
	for(PullRequest *r in prs) [r postProcess];
}

- (NSAttributedString *)reasonForEmptyWithFilter:(NSString *)filterValueOrNil
{
	COLOR_CLASS *messageColor = [COLOR_CLASS lightGrayColor];
	NSUInteger openRequests = [PullRequest countOpenRequestsInMoc:self.managedObjectContext];
	NSString *message;

	if([AppDelegate shared].isRefreshing)
	{
		message = @"Refreshing PR information, please wait a moment...";
	}
	else if(filterValueOrNil.length)
	{
		message = @"There are no PRs matching this filter.";
	}
	else if(openRequests>0)
	{
		message = [NSString stringWithFormat:@"%ld PRs are hidden by your settings.",(unsigned long)openRequests];
	}
	else if([Repo countActiveReposInMoc:self.managedObjectContext]==0)
	{
		messageColor = [COLOR_CLASS colorWithRed:0.8 green:0.0 blue:0.0 alpha:1.0];
		message = @"There are no active repositories, please add or activate some.";
	}
	else if(openRequests==0)
	{
		message = @"There are no open PRs for your selected repositories.";
	}

	NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
#ifdef __MAC_OS_X_VERSION_MIN_REQUIRED
	paragraphStyle.alignment = NSCenterTextAlignment;
	return [[NSAttributedString alloc] initWithString:message
										   attributes:@{ NSForegroundColorAttributeName: messageColor,
														 NSParagraphStyleAttributeName: paragraphStyle }];
#else
	paragraphStyle.alignment = NSTextAlignmentCenter;
	return [[NSAttributedString alloc] initWithString:message
										   attributes:@{ NSForegroundColorAttributeName: messageColor,
														 NSParagraphStyleAttributeName: paragraphStyle,
														 NSFontAttributeName: [UIFont systemFontOfSize:[UIFont smallSystemFontSize]] }];
#endif
}

@end

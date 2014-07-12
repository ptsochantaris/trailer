
@implementation DataManager

@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize managedObjectContext = _managedObjectContext;

- (id)init
{
    self = [super init];
    if (self)
	{
		if([self versionBumpOccured])
		{
			DLog(@"VERSION UPDATE MAINTENANCE NEEDED");
			[self performVersionChangedTasks];
			[self versionBumpComplete];
		}

		for(Repo *r in [Repo allItemsOfType:@"Repo" inMoc:self.managedObjectContext])
		{
			r.dirty = @(YES);
		}
    }
    return self;
}

- (void)performVersionChangedTasks
{
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

- (void)sendNotifications
{
	NSManagedObjectContext *mainContext = self.managedObjectContext;

	NSArray *latestPrs = [PullRequest newItemsOfType:@"PullRequest" inMoc:mainContext];
	for(PullRequest *r in latestPrs)
	{
		if(!r.isMine)
		{
			[[AppDelegate shared] postNotificationOfType:kNewPr forItem:r];
		}
		r.postSyncAction = @(kPostSyncDoNothing);
	}

	latestPrs = [PullRequest updatedItemsOfType:@"PullRequest" inMoc:mainContext];
	for(PullRequest *r in latestPrs)
	{
		if(r.reopened.boolValue)
		{
			if(!r.isMine)
			{
				[[AppDelegate shared] postNotificationOfType:kPrReopened forItem:r];
			}
			r.reopened = @NO;
		}
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
															   options:@{ NSMigratePersistentStoresAutomaticallyOption:@YES,
																		  NSInferMappingModelAutomaticallyOption:@YES,
																		  NSSQLitePragmasOption:@{ @"synchronous":@"OFF",
																								   @"fullfsync":@"0" } }
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
	[self wipeApiMarkers];
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
	if(_managedObjectContext.hasChanges)
		return [_managedObjectContext save:nil];
	return YES;
}

- (void)deleteEverything
{
	@autoreleasepool
	{
		NSManagedObjectContext *tempMoc = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
		tempMoc.parentContext = self.managedObjectContext;
		tempMoc.undoManager = nil;

		for (NSString *entityName in self.managedObjectModel.entitiesByName)
		{
			@autoreleasepool
			{
				NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:entityName];
				fetchRequest.includesPropertyValues = NO;
				fetchRequest.includesSubentities = NO;

				for (NSManagedObject *managedObject in [tempMoc executeFetchRequest:fetchRequest error:nil])
					[tempMoc deleteObject:managedObject];
			}
		}

		[tempMoc save:nil];
	}
	[self saveDB];

	[self wipeApiMarkers];
}

- (void)wipeApiMarkers
{
	// because these control the DB state with the event feed, needs to be reset
	[Settings shared].latestReceivedEventEtag = nil;
	[Settings shared].latestReceivedEventDateProcessed = nil;
	[Settings shared].latestUserEventEtag = nil;
	[Settings shared].latestUserEventDateProcessed = nil;
}

- (NSDictionary *)infoForType:(PRNotificationType)type item:(id)item
{
	switch (type)
	{
		case kNewMention:
		case kNewComment:
			return @{COMMENT_ID_KEY:[item serverId]};
		case kNewPr:
		case kPrReopened:
			return @{PULL_REQUEST_ID_KEY:[item serverId]};
		case kPrClosed:
		case kPrMerged:
			return @{NOTIFICATION_URL_KEY:[item webUrl], PULL_REQUEST_ID_KEY:[item serverId]};
		case kNewRepoSubscribed:
		case kNewRepoAnnouncement:
			return @{NOTIFICATION_URL_KEY:[item webUrl] };
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
	else if([Repo countVisibleReposInMoc:self.managedObjectContext]==0)
	{
		messageColor = MAKECOLOR(0.8, 0.0, 0.0, 1.0);
		message = @"There are no watched repositories, please watch or unhide some.";
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

/////////////////////////////////////////////////////////////////////

#define LAST_RUN_VERSION_KEY @"LAST_RUN_VERSION"
- (void)versionBumpComplete
{
	NSString *currentAppVersion = [AppDelegate shared].currentAppVersion;
	[[NSUserDefaults standardUserDefaults] setObject:currentAppVersion forKey:LAST_RUN_VERSION_KEY];
}
- (BOOL)versionBumpOccured
{
	NSString *currentAppVersion = [AppDelegate shared].currentAppVersion;
	return !([[[NSUserDefaults standardUserDefaults] objectForKey:LAST_RUN_VERSION_KEY] isEqualToString:currentAppVersion]);
}

@end

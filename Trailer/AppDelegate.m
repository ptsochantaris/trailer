//
//  AppDelegate.m
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@implementation AppDelegate

@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize managedObjectContext = _managedObjectContext;

static AppDelegate *_static_shared_ref;
+(AppDelegate *)shared { return _static_shared_ref; }

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	//NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
	//[[NSUserDefaults standardUserDefaults] removePersistentDomainForName:appDomain];

	SUUpdater *s = [SUUpdater sharedUpdater];
	if(!s.updateInProgress)
	{
		[s checkForUpdatesInBackground];
	}
	[s setUpdateCheckInterval:28800.0]; // 8 hours
	s.automaticallyChecksForUpdates = YES;

	[NSThread setThreadPriority:0.0];

	_static_shared_ref = self;

	self.api = [[API alloc] init];

	[self setupSortMethodMenu];

	[self updateStatusItem];

	[self startRateLimitHandling];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(defaultsUpdated)
												 name:NSUserDefaultsDidChangeNotification
											   object:nil];

	[[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];

	NSString *currentAppVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
	[self.versionNumber setStringValue:currentAppVersion];

	if(self.api.authToken.length)
	{
		[self.githubTokenHolder setStringValue:self.api.authToken];
		[self startRefresh];
	}
	else
	{
		[self preferencesSelected:nil];
	}

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(networkStateChanged)
												 name:kReachabilityChangedNotification
											   object:nil];

	//PullRequest *pr = [[PullRequest allItemsOfType:@"PullRequest" inMoc:self.managedObjectContext] lastObject];
	//pr.merged = @(YES);
}

- (void)setupSortMethodMenu
{
	NSMenu *m = [[NSMenu alloc] initWithTitle:@"Sorting"];
	if(self.api.sortDescending)
	{
		[m addItemWithTitle:@"Newest First" action:@selector(sortMethodChanged:) keyEquivalent:@""];
		[m addItemWithTitle:@"Most Recently Active" action:@selector(sortMethodChanged:) keyEquivalent:@""];
		[m addItemWithTitle:@"Reverse Alphabetically" action:@selector(sortMethodChanged:) keyEquivalent:@""];
	}
	else
	{
		[m addItemWithTitle:@"Oldest First" action:@selector(sortMethodChanged:) keyEquivalent:@""];
		[m addItemWithTitle:@"Inactive For Longest" action:@selector(sortMethodChanged:) keyEquivalent:@""];
		[m addItemWithTitle:@"Alphabetically" action:@selector(sortMethodChanged:) keyEquivalent:@""];
	}
	self.sortModeSelect.menu = m;
	[self.sortModeSelect selectItemAtIndex:self.api.sortMethod];
}

- (IBAction)dontKeepMyPrsSelected:(NSButton *)sender
{
	BOOL dontKeep = (sender.integerValue==1);
	self.api.dontKeepMyPrs = dontKeep;
}

- (IBAction)hidePrsSelected:(NSButton *)sender
{
	BOOL show = (sender.integerValue==1);
	self.api.shouldHideUncommentedRequests = show;
	[self updateStatusItem];
}

- (IBAction)showAllCommentsSelected:(NSButton *)sender
{
	BOOL show = (sender.integerValue==1);
	self.api.showCommentsEverywhere = show;
	[self updateStatusItem];
}

- (IBAction)sortOrderSelected:(NSButton *)sender
{
	BOOL descending = (sender.integerValue==1);
	self.api.sortDescending = descending;
	[self setupSortMethodMenu];
	[self updateStatusItem];
}

- (IBAction)sortMethodChanged:(id)sender
{
	self.api.sortMethod = self.sortModeSelect.indexOfSelectedItem;
	[self updateStatusItem];
}

- (IBAction)showCreationSelected:(NSButton *)sender
{
	BOOL show = (sender.integerValue==1);
	self.api.showCreatedInsteadOfUpdated = show;
	[self updateStatusItem];
}


- (IBAction)launchAtStartSelected:(NSButton *)sender
{
	if(sender.integerValue==1)
	{
		[self addAppAsLoginItem];
	}
	else
	{
		[self deleteAppFromLoginItem];
	}
}

-(BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
	return YES;
}

#define PULL_REQUEST_ID_KEY @"pullRequestIdKey"
#define COMMENT_ID_KEY @"commentIdKey"
#define NOTIFICATION_URL_KEY @"urlKey"

-(void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
	switch (notification.activationType)
	{
		case NSUserNotificationActivationTypeActionButtonClicked:
		case NSUserNotificationActivationTypeContentsClicked:
		{
			[[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:notification];

			NSString *urlToOpen = notification.userInfo[NOTIFICATION_URL_KEY];
			if(!urlToOpen)
			{
				NSNumber *itemId = notification.userInfo[PULL_REQUEST_ID_KEY];
				PullRequest *pullRequest = nil;
				if(itemId) // it's a pull request
				{
					pullRequest = [PullRequest itemOfType:@"PullRequest" serverId:itemId moc:self.managedObjectContext];
					urlToOpen = pullRequest.webUrl;
				}
				else // it's a comment
				{
					itemId = notification.userInfo[COMMENT_ID_KEY];
					PRComment *c = [PRComment itemOfType:@"PRComment" serverId:itemId moc:self.managedObjectContext];
					urlToOpen = c.webUrl;
					pullRequest = [PullRequest pullRequestWithUrl:c.pullRequestUrl moc:self.managedObjectContext];
				}
				[pullRequest catchUpWithComments];
			}

			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlToOpen]];

			[self updateStatusItem];

			break;
		}
		default: break;
	}
}

-(void)postNotificationOfType:(PRNotificationType)type forItem:(id)item
{
	if(self.preferencesDirty) return;

	NSUserNotification *notification = [[NSUserNotification alloc] init];

	switch (type)
	{
		case kNewComment:
		{
			notification.title = @"New PR Comment";
			notification.informativeText = [item body];
			PullRequest *associatedRequest = [PullRequest pullRequestWithUrl:[item pullRequestUrl] moc:self.managedObjectContext];
			notification.userInfo = @{COMMENT_ID_KEY:[item serverId]};
			notification.subtitle = associatedRequest.title;
			break;
		}
		case kNewPr:
		{
			notification.title = @"New PR";
			notification.userInfo = @{PULL_REQUEST_ID_KEY:[item serverId]};
			notification.subtitle = [item title];
			break;
		}
		case kPrMerged:
		{
			notification.title = @"PR Merged!";
			notification.userInfo = @{NOTIFICATION_URL_KEY:[item webUrl]};
			notification.subtitle = [item title];
			break;
		}
	}

    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}

- (void)prItemSelected:(PRItemView *)item
{
	PullRequest *r = [PullRequest itemOfType:@"PullRequest" serverId:item.userInfo moc:self.managedObjectContext];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:r.webUrl]];
	[r catchUpWithComments];
	[self updateStatusItem];
}

- (void)statusItemTapped:(StatusItem *)statusItem
{
	self.statusItemView.highlighted = YES;
	if(!self.isRefreshing)
	{
		NSString *prefix;
		if(self.api.localUser)
		{
			prefix = [NSString stringWithFormat:@"Refresh %@",self.api.localUser];
		}
		else
		{
			prefix = @"Refresh";
		}
		if(self.lastUpdateFailed)
		{
			self.refreshNow.title = [prefix stringByAppendingString:@" (last update failed!)"];
		}
		else
		{
			long ago = (long)[[NSDate date] timeIntervalSinceDate:self.lastSuccessfulRefresh];
			if(ago<10)
			{
				self.refreshNow.title = [prefix stringByAppendingString:@" (just updated)"];
			}
			else
			{
				self.refreshNow.title = [NSString stringWithFormat:@"%@ (updated %ld seconds ago)",prefix,(long)ago];
			}
		}
	}

	NSScreen *screen = [NSScreen mainScreen];
	NSWindow *window = [[[NSApplication sharedApplication] currentEvent] window];
	CGFloat H = screen.visibleFrame.size.height;
	CGFloat X = [window frame].origin.x;
	CGFloat rightSide = screen.visibleFrame.origin.x+screen.visibleFrame.size.width;
	CGFloat overflow = (X+MENU_WIDTH)-rightSide;
	if(overflow>0) X -= overflow;
	// TODO: trim height if list is shorter

	CGRect frame = CGRectMake(X, H, MENU_WIDTH, H);
	[self.mainMenu setLevel:NSFloatingWindowLevel];
	[self.mainMenu setFrame:frame display:YES];
	[self.mainMenu makeKeyAndOrderFront:self];
}

- (void)closeMenu
{
	self.statusItemView.highlighted = NO;
}

- (void)sectionHeaderRemoveSelectedFrom:(SectionHeader *)header
{
	[self closeMenu];

	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:@"Clear all merged PRs?"];
		[alert setInformativeText:[NSString stringWithFormat:@"This will clear all the merged PRs from your list.  This action cannot be undone, are you sure?"]];
		[alert addButtonWithTitle:@"No"];
		[alert addButtonWithTitle:@"Yes"];
		NSInteger selected = [alert runModal];
		if(selected==NSAlertSecondButtonReturn)
		{
			[self removeAllMergedRequests];
		}
	});
}

- (void)removeAllMergedRequests
{
	NSArray *mergedRequests = [PullRequest allMergedRequestsInMoc:self.managedObjectContext];
	for(PullRequest *r in mergedRequests)
		[self.managedObjectContext deleteObject:r];
	[self saveDB];
	[self updateStatusItem];
}

- (void)unPinSelectedFrom:(NSMenuItem *)item
{
	PullRequest *r = [PullRequest itemOfType:@"PullRequest" serverId:item.representedObject moc:self.managedObjectContext];
	[self.managedObjectContext deleteObject:r];
	[self saveDB];
	[self updateStatusItem];
}

- (NSInteger)buildPrMenuItemsFromList:(NSArray *)pullRequests
{
	NSMutableArray *menuItems = [NSMutableArray array];

	// above it have a single view with search and options

	SectionHeader *myHeader = [[SectionHeader alloc] initWithRemoveAllDelegate:nil title:@"Mine"];
	SectionHeader *participatedHeader = [[SectionHeader alloc] initWithRemoveAllDelegate:nil title:@"Participated"];
	SectionHeader *mergedHeader = [[SectionHeader alloc] initWithRemoveAllDelegate:self title:@"Recently Merged"];
	SectionHeader *allHeader = [[SectionHeader alloc] initWithRemoveAllDelegate:nil title:@"All Pull Requests"];

	[menuItems addObject:myHeader];
	[menuItems addObject:participatedHeader];
	[menuItems addObject:mergedHeader];
	[menuItems addObject:allHeader];

	NSInteger unreadCommentCount = 0;
	NSInteger myIndex = 1, myCount = 0;
	NSInteger participatedIndex = myIndex+1, participatedCount = 0;
	NSInteger mergedIndex = participatedIndex+1, mergedCount = 0;
	NSInteger allIndex = mergedIndex+1, allCount = 0;

	for(PullRequest *r in pullRequests)
	{
		if(self.api.shouldHideUncommentedRequests)
			if(r.unreadCommentCount==0)
				continue;

		PRItemView *item = [[PRItemView alloc] init];
		item.userInfo = r.serverId;
		item.delegate = self;
		[item setPullRequest:r];
		if(r.merged.boolValue)
		{
			mergedCount++;
			[menuItems insertObject:item atIndex:mergedIndex++];
		}
		else if(r.isMine)
		{
			myCount++;
			[menuItems insertObject:item atIndex:myIndex++];
			unreadCommentCount += [r unreadCommentCount];
			participatedIndex++;
			mergedIndex++;
		}
		else if(r.commentedByMe)
		{
			participatedCount++;
			[menuItems insertObject:item atIndex:participatedIndex++];
			unreadCommentCount += [r unreadCommentCount];
			mergedIndex++;
		}
		else // all other pull requests
		{
			allCount++;
			[menuItems insertObject:item atIndex:allIndex];
			if([AppDelegate shared].api.showCommentsEverywhere)
				unreadCommentCount += [r unreadCommentCount];
		}
		allIndex++;
	}

	if(!myCount) [menuItems removeObject:myHeader];
	if(!participatedCount) [menuItems removeObject:participatedHeader];
	if(!mergedCount) [menuItems removeObject:mergedHeader];
	if(!allCount) [menuItems removeObject:allHeader];

	CGFloat top = 0;
	NSClipView *clip = [[NSClipView alloc] initWithFrame:CGRectZero];
	for(NSView *v in menuItems)
	{
		CGFloat H = v.frame.size.height;
		v.frame = CGRectMake(0, top, MENU_WIDTH, H);
		top += H;
		[clip addSubview:v];
	}
	clip.frame = CGRectMake(0, 0, MENU_WIDTH, top);
	self.scrollView.contentView = clip;

	return unreadCommentCount;
}

- (void)defaultsUpdated
{
	if(self.api.localUser)
		self.githubDetailsBox.title = [NSString stringWithFormat:@"Repositories for %@",self.api.localUser];
	else
		self.githubDetailsBox.title = @"Your Repositories";
}

- (void)startRateLimitHandling
{
	[self.apiLoad setIndeterminate:YES];
	[self.apiLoad stopAnimation:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(apiUsageUpdate:) name:RATE_UPDATE_NOTIFICATION object:nil];
	if(self.api.authToken.length)
	{
		[self updateLimitFromServer];
	}
}

- (void)updateLimitFromServer
{
	[self.api getRateLimitAndCallback:^(long long remaining, long long limit, long long reset) {
		if(reset>=0)
		{
			[[NSNotificationCenter defaultCenter] postNotificationName:RATE_UPDATE_NOTIFICATION
																object:nil
															  userInfo:@{
																		 RATE_UPDATE_NOTIFICATION_LIMIT_KEY:@(limit),
																		 RATE_UPDATE_NOTIFICATION_REMAINING_KEY:@(remaining)
																		 }];
		}
	}];
}

- (void)apiUsageUpdate:(NSNotification *)n
{
	[self.apiLoad setIndeterminate:NO];
	long long remaining = [n.userInfo[RATE_UPDATE_NOTIFICATION_REMAINING_KEY] longLongValue];
	long long limit = [n.userInfo[RATE_UPDATE_NOTIFICATION_LIMIT_KEY] longLongValue];
	self.apiLoad.maxValue = limit;
	self.apiLoad.doubleValue = limit-remaining;
}

- (IBAction)refreshReposSelected:(NSButton *)sender
{
	[self prepareForRefresh];
	[self controlTextDidChange:nil];

	NSArray *items = [PullRequest itemsOfType:@"Repo" surviving:YES inMoc:self.managedObjectContext];
	for(DataItem *i in items) i.postSyncAction = @(kPostSyncDelete);

	items = [PullRequest itemsOfType:@"Org" surviving:YES inMoc:self.managedObjectContext];
	for(DataItem *i in items) i.postSyncAction = @(kPostSyncDelete);

	[self.api fetchRepositoriesAndCallback:^(BOOL success) {

		if(!success)
		{
            NSError *error = [NSError errorWithDomain:@"YOUR_ERROR_DOMAIN"
												 code:101
											 userInfo:@{NSLocalizedDescriptionKey:@"Error while fetching data from GitHub, please check that the token you have provided is correct and that you have a working network connection"}];
            [[NSApplication sharedApplication] presentError:error];
		}
		else
		{
			[DataItem nukeDeletedItemsOfType:@"Repo" inMoc:self.managedObjectContext];
			[DataItem nukeDeletedItemsOfType:@"Org" inMoc:self.managedObjectContext];
		}
		[self completeRefresh];
	}];
}

-(void)controlTextDidChange:(NSNotification *)obj
{
	if(obj.object==self.githubTokenHolder)
	{
		NSString *newToken = [self.githubTokenHolder.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		NSString *oldToken = self.api.authToken;
		if(newToken.length>0)
		{
			self.refreshButton.enabled = YES;
			self.api.authToken = newToken;
		}
		else
		{
			self.refreshButton.enabled = NO;
			self.api.authToken = nil;
		}
		if(newToken && oldToken && ![newToken isEqualToString:oldToken])
		{
			[self reset];
		}
	}
	else if(obj.object==self.repoFilter)
	{
		[self.projectsTable reloadData];
	}
}

- (void)reset
{
	self.preferencesDirty = YES;
	self.lastSuccessfulRefresh = nil;
	[DataItem deleteAllObjectsInContext:self.managedObjectContext
							 usingModel:self.managedObjectModel];
	[self.projectsTable reloadData];
	[self updateStatusItem];
}

- (IBAction)markAllReadSelected:(NSMenuItem *)sender
{
	for(PullRequest *r in [self pullRequestList])
		[r catchUpWithComments];
	[self updateStatusItem];
}

- (IBAction)preferencesSelected:(NSMenuItem *)sender
{
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;

	[self updateLimitFromServer];

	[self.sortModeSelect selectItemAtIndex:self.api.sortMethod];

	if([self isAppLoginItem])
		[self.launchAtStartup setIntegerValue:1];
	else
		[self.launchAtStartup setIntegerValue:0];

	if(self.api.shouldHideUncommentedRequests)
		[self.hideUncommentedPrs setIntegerValue:1];
	else
		[self.hideUncommentedPrs setIntegerValue:0];

	if(self.api.dontKeepMyPrs)
		[self.dontKeepMyPrs setIntegerValue:1];
	else
		[self.dontKeepMyPrs setIntegerValue:0];

	if(self.api.showCommentsEverywhere)
		[self.showAllComments setIntegerValue:1];
	else
		[self.showAllComments setIntegerValue:0];

	if(self.api.sortDescending)
		[self.sortingOrder setIntegerValue:1];
	else
		[self.sortingOrder setIntegerValue:0];

	if(self.api.showCreatedInsteadOfUpdated)
		[self.showCreationDates setIntegerValue:1];
	else
		[self.showCreationDates setIntegerValue:0];

	[self.refreshDurationStepper setFloatValue:self.api.refreshPeriod];
	[self refreshDurationChanged:nil];

	[self.preferencesWindow setLevel:NSFloatingWindowLevel];
	[self.preferencesWindow makeKeyAndOrderFront:self];
}

- (IBAction)createTokenSelected:(NSButton *)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/settings/tokens/new"]];
}

- (IBAction)viewExistingTokensSelected:(NSButton *)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/settings/applications"]];
}

/////////////////////////////////// Repo table

- (NSArray *)getFileterdRepos
{
	NSArray *allRepos = [Repo allReposSortedByField:@"fullName"
									withTitleFilter:self.repoFilter.stringValue
											  inMoc:self.managedObjectContext];
	return allRepos;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSArray *allRepos = [self getFileterdRepos];
	Repo *r = allRepos[row];

	NSButtonCell *cell = [tableColumn dataCellForRow:row];
	cell.title = r.fullName;
	if(r.active.boolValue)
	{
		cell.state = NSOnState;
	}
	else
	{
		cell.state = NSOffState;
	}
	return cell;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [self getFileterdRepos].count;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSArray *allRepos = [self getFileterdRepos];
	Repo *r = allRepos[row];
	r.active = @([object boolValue]);
	[self saveDB];
	self.preferencesDirty = YES;
}

/////////////////////////////////// Core Data

// Returns the directory the application uses to store the Core Data store file. This code uses a directory named "com.housetrip.Trailer" in the user's Application Support directory.
- (NSURL *)applicationFilesDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *appSupportURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
    appSupportURL = [appSupportURL URLByAppendingPathComponent:@"com.housetrip.Trailer"];
	NSLog(@"Files in %@",appSupportURL);
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
    if (!mom) {
        NSLog(@"%@:%@ No model to generate a store from", [self class], NSStringFromSelector(_cmd));
        return nil;
    }

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
            [[NSApplication sharedApplication] presentError:error];
            return nil;
        }
    } else {
        if (![properties[NSURLIsDirectoryKey] boolValue]) {
            // Customize and localize this error.
            NSString *failureDescription = [NSString stringWithFormat:@"Expected a folder to store application data, found a file (%@).", [applicationFilesDirectory path]];
            
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            [dict setValue:failureDescription forKey:NSLocalizedDescriptionKey];
            error = [NSError errorWithDomain:@"YOUR_ERROR_DOMAIN" code:101 userInfo:dict];
            
            [[NSApplication sharedApplication] presentError:error];
            return nil;
        }
    }
    
    NSURL *url = [applicationFilesDirectory URLByAppendingPathComponent:@"Trailer.storedata"];
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:mom];
    if (![coordinator addPersistentStoreWithType:NSXMLStoreType configuration:nil URL:url options:nil error:&error]) {
        [[NSApplication sharedApplication] presentError:error];
        return nil;
    }
    _persistentStoreCoordinator = coordinator;
    
    return _persistentStoreCoordinator;
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

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    // Save changes in the application's managed object context before the application terminates.
    
    if (!_managedObjectContext) {
        return NSTerminateNow;
    }
    
    if (![[self managedObjectContext] commitEditing]) {
        NSLog(@"%@:%@ unable to commit editing to terminate", [self class], NSStringFromSelector(_cmd));
        return NSTerminateCancel;
    }
    
    if (![[self managedObjectContext] hasChanges]) {
        return NSTerminateNow;
    }

	[self saveDB];
    return NSTerminateNow;
}

- (void)saveDB
{
	if(self.managedObjectContext.hasChanges)
		[self.managedObjectContext save:nil];
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
	
}

- (void)windowDidResignKey:(NSNotification *)notification
{
	if([notification object]==self.mainMenu)
	{
		[self closeMenu];
	}
}

- (void)windowDidResignMain:(NSNotification *)notification
{
	if([notification object]==self.mainMenu)
	{
		[self closeMenu];
	}
}

-(void)windowWillClose:(NSNotification *)notification
{
	if([notification object]==self.preferencesWindow)
	{
		[self controlTextDidChange:nil];
		if(self.api.authToken.length && self.preferencesDirty)
		{
			[self startRefresh];
		}
		else
		{
			if(!self.refreshTimer && self.api.refreshPeriod>0.0)
			{
				[self startRefreshIfItIsDue];
			}
		}
	}
}

- (void)networkStateChanged
{
	if([self.api.reachability currentReachabilityStatus]!=NotReachable)
	{
		NSLog(@"Network is back");
		[self startRefreshIfItIsDue];
	}
}

- (void)startRefreshIfItIsDue
{
	if(self.lastSuccessfulRefresh)
	{
		NSTimeInterval howLongAgo = [[NSDate date] timeIntervalSinceDate:self.lastSuccessfulRefresh];
		if(howLongAgo>self.api.refreshPeriod)
		{
			[self startRefresh];
		}
		else
		{
			NSTimeInterval howLongUntilNextSync = self.api.refreshPeriod-howLongAgo;
			NSLog(@"No need to refresh yet, will refresh in %f",howLongUntilNextSync);
			self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:howLongUntilNextSync
																 target:self
															   selector:@selector(refreshTimerDone)
															   userInfo:nil
																repeats:NO];
		}
	}
	else
	{
		[self startRefresh];
	}
}

- (IBAction)refreshNowSelected:(NSMenuItem *)sender
{
	NSArray *activeRepos = [Repo activeReposInMoc:self.managedObjectContext];
	if(activeRepos.count==0)
	{
		[self preferencesSelected:nil];
		return;
	}
	[self startRefresh];
}

- (void)checkApiUsage
{
	if(self.apiLoad.maxValue-self.apiLoad.doubleValue==0)
	{
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Your API request usage is over the limit!"];
        [alert setInformativeText:[NSString stringWithFormat:@"Your request cannot be completed until GitHub resets your hourly API allowance at %@.\n\nIf you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.\n\nYou can check your API usage at any time from the bottom of the preferences pane at any time.",self.api.resetDate]];
        [alert addButtonWithTitle:@"OK"];
		[alert runModal];
		return;
	}
	else if((self.apiLoad.doubleValue/self.apiLoad.maxValue)>LOW_API_WARNING)
	{
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Your API request usage is close to full"];
        [alert setInformativeText:[NSString stringWithFormat:@"Try to make fewer manual refreshes, increasing the automatic refresh time, or reducing the number of repos you are monitoring.\n\nYour allowance will be reset by Github on %@.\n\nYou can check your API usage from the bottom of the preferences pane.",self.api.resetDate]];
        [alert addButtonWithTitle:@"OK"];
		[alert runModal];
	}
}

-(void)prepareForRefresh
{
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;

	[self.refreshButton setEnabled:NO];
	[self.projectsTable setEnabled:NO];
	[self.selectAll setEnabled:NO];
	[self.clearAll setEnabled:NO];
	[self.githubTokenHolder setEnabled:NO];
	[self.activityDisplay startAnimation:nil];
	[self updateStatusItem];
}

-(void)completeRefresh
{
	[self.refreshButton setEnabled:YES];
	[self.projectsTable setEnabled:YES];
	[self.selectAll setEnabled:YES];
	[self.githubTokenHolder setEnabled:YES];
	[self.clearAll setEnabled:YES];
	[self.activityDisplay stopAnimation:nil];
	[self saveDB];
	[self.projectsTable reloadData];
	[self updateStatusItem];
	[self checkApiUsage];
	[self sendNotifications];
}

-(BOOL)isRefreshing
{
	return self.refreshNow.target==nil;
}

-(void)startRefresh
{
	if(self.isRefreshing) return;
	NSLog(@"Starting refresh");
	[self prepareForRefresh];
	id oldTarget = self.refreshNow.target;
	SEL oldAction = self.refreshNow.action;

	if(self.api.localUser)
		self.refreshNow.title = [NSString stringWithFormat:@"Refreshing %@...",self.api.localUser];
	else
		self.refreshNow.title = @"Refreshing...";

	[self.refreshNow setAction:nil];
	[self.refreshNow setTarget:nil];

	[self updateStatusItem];

	[self.api fetchPullRequestsForActiveReposAndCallback:^(BOOL success) {
		self.refreshNow.target = oldTarget;
		self.refreshNow.action = oldAction;
		self.lastUpdateFailed = !success;
		[self completeRefresh];
		if(success)
		{
			self.lastSuccessfulRefresh = [NSDate date];
			self.preferencesDirty = NO;
		}
		self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:self.api.refreshPeriod
															 target:self
														   selector:@selector(refreshTimerDone)
														   userInfo:nil
															repeats:NO];
		NSLog(@"Refresh done");
	}];
}


- (IBAction)refreshDurationChanged:(NSStepper *)sender
{
	self.api.refreshPeriod = self.refreshDurationStepper.floatValue;
	[self.refreshDurationLabel setStringValue:[NSString stringWithFormat:@"Automatically refresh every %ld seconds",(long)self.refreshDurationStepper.integerValue]];
}

-(void)refreshTimerDone
{
	if(self.api.localUserId && self.api.authToken.length)
	{
		[self startRefresh];
	}
}

-(void)sendNotifications
{
	NSArray *latestPrs = [PullRequest newItemsOfType:@"PullRequest" inMoc:self.managedObjectContext];
	for(PullRequest *r in latestPrs)
	{
		[self postNotificationOfType:kNewPr forItem:r];
		r.postSyncAction = @(kPostSyncDoNothing);
	}

	NSArray *latestComments = [PRComment newItemsOfType:@"PRComment" inMoc:self.managedObjectContext];
	for(PRComment *c in latestComments)
	{
		PullRequest *r = [PullRequest pullRequestWithUrl:c.pullRequestUrl moc:self.managedObjectContext];
		if(self.api.showCommentsEverywhere || r.isMine || r.commentedByMe)
		{
			if(![c.userId.stringValue isEqualToString:self.api.localUserId])
			{
				[self postNotificationOfType:kNewComment forItem:c];
			}
		}
		c.postSyncAction = @(kPostSyncDoNothing);
	}
	[self saveDB];
}

- (NSArray *)pullRequestList
{
	NSString *sortCriterion;
	switch (self.api.sortMethod) {
		case kCreationDate: sortCriterion = @"createdAt"; break;
		case kRecentActivity: sortCriterion = @"updatedAt"; break;
		case kTitle: sortCriterion = @"title"; break;
	}
	NSArray *pullRequests = [PullRequest pullRequestsSortedByField:sortCriterion
														 ascending:!self.api.sortDescending
															 inMoc:self.managedObjectContext];
	return pullRequests;
}

- (void)updateStatusItem
{
	NSArray *pullRequests = [self pullRequestList];
	NSString *countString = [NSString stringWithFormat:@"%ld",[PullRequest countUnmergedRequestsInMoc:self.managedObjectContext]];
	NSInteger newCommentCount = [self buildPrMenuItemsFromList:pullRequests];

	NSLog(@"Updating status item with %@ total PRs",countString);

	NSDictionary *attributes;
	if(self.lastUpdateFailed)
	{
		countString = @"X";
		attributes = @{
					   NSFontAttributeName: [NSFont boldSystemFontOfSize:11.0],
					   NSForegroundColorAttributeName: [NSColor colorWithRed:0.8 green:0.0 blue:0.0 alpha:1.0],
					   };
	}
	else if(newCommentCount)
	{
		attributes = @{
					   NSFontAttributeName: [NSFont systemFontOfSize:11.0],
					   NSForegroundColorAttributeName: [NSColor colorWithRed:0.8 green:0.0 blue:0.0 alpha:1.0],
					   };
	}
	else if(self.isRefreshing)
	{
		attributes = @{
					   NSFontAttributeName: [NSFont systemFontOfSize:11.0],
					   NSForegroundColorAttributeName: [NSColor grayColor],
					   };
	}
	else
	{
		attributes = @{
					   NSFontAttributeName: [NSFont systemFontOfSize:11.0],
					   NSForegroundColorAttributeName: [NSColor blackColor],
					   };
	}

	CGFloat width = [countString sizeWithAttributes:attributes].width;

	NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
	CGFloat H = statusBar.thickness;
	CGFloat length = H+width+STATUSITEM_PADDING*3;
	if(!self.statusItem) self.statusItem = [statusBar statusItemWithLength:NSVariableStatusItemLength];

	self.statusItemView = [[StatusItem alloc] initWithFrame:CGRectMake(0, 0, length, H)
													  label:countString
												 attributes:attributes
												   delegate:self];
	self.statusItem.view = self.statusItemView;
	self.statusItem.highlightMode = YES;
}

- (IBAction)selectAllSelected:(NSButton *)sender
{
	NSArray *allRepos = [self getFileterdRepos];
	for(Repo *r in allRepos)
	{
		r.active = @YES;
	}
	[self saveDB];
	[self.projectsTable reloadData];
	self.preferencesDirty = YES;
}

- (IBAction)clearallSelected:(NSButton *)sender
{
	NSArray *allRepos = [self getFileterdRepos];
	for(Repo *r in allRepos)
	{
		r.active = @NO;
	}
	[self saveDB];
	[self.projectsTable reloadData];
	self.preferencesDirty = YES;
}

//////////////// launch at startup from: http://cocoatutorial.grapewave.com/tag/lssharedfilelistitemresolve/

-(void) addAppAsLoginItem
{
	NSString * appPath = [[NSBundle mainBundle] bundlePath];

	// This will retrieve the path for the application
	// For example, /Applications/test.app
	CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];

	// Create a reference to the shared file list.
	// We are adding it to the current user only.
	// If we want to add it all users, use
	// kLSSharedFileListGlobalLoginItems instead of
	//kLSSharedFileListSessionLoginItems
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
	if (loginItems) {
		//Insert an item to the list.
		LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(loginItems,
																	 kLSSharedFileListItemLast, NULL, NULL,
																	 url, NULL, NULL);
		if (item){
			CFRelease(item);
		}
		CFRelease(loginItems);
	}
}

-(BOOL)isAppLoginItem
{
	NSString * appPath = [[NSBundle mainBundle] bundlePath];

	// This will retrieve the path for the application
	// For example, /Applications/test.app
	CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];

	// Create a reference to the shared file list.
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);

	if (loginItems) {
		UInt32 seedValue;
		//Retrieve the list of Login Items and cast them to
		// a NSArray so that it will be easier to iterate.
		NSArray  *loginItemsArray = (__bridge_transfer NSArray *)LSSharedFileListCopySnapshot(loginItems, &seedValue);
		for(int i = 0 ; i< [loginItemsArray count]; i++){
			LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)[loginItemsArray objectAtIndex:i];
			//Resolve the item with URL
			if (LSSharedFileListItemResolve(itemRef, 0, (CFURLRef*) &url, NULL) == noErr) {
				NSURL *uu = (__bridge NSURL*)url;
				if ([[uu path] compare:appPath] == NSOrderedSame){
					return YES;
				}
			}
		}
	}
	return NO;
}

-(void) deleteAppFromLoginItem
{
	NSString * appPath = [[NSBundle mainBundle] bundlePath];

	// This will retrieve the path for the application
	// For example, /Applications/test.app
	CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];

	// Create a reference to the shared file list.
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);

	if (loginItems) {
		UInt32 seedValue;
		//Retrieve the list of Login Items and cast them to
		// a NSArray so that it will be easier to iterate.
		NSArray  *loginItemsArray = (__bridge_transfer NSArray *)LSSharedFileListCopySnapshot(loginItems, &seedValue);
		for(int i = 0 ; i< [loginItemsArray count]; i++){
			LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)[loginItemsArray objectAtIndex:i];
			//Resolve the item with URL
			if (LSSharedFileListItemResolve(itemRef, 0, (CFURLRef*) &url, NULL) == noErr) {
				NSURL *uu = (__bridge NSURL*)url;
				if ([[uu path] compare:appPath] == NSOrderedSame){
					LSSharedFileListItemRemove(loginItems,itemRef);
				}
			}
		}
	}
}

@end

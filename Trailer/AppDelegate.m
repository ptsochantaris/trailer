//
//  AppDelegate.m
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

#import "AppDelegate.h"

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

	_static_shared_ref = self;

	self.api = [[API alloc] init];

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
}

- (IBAction)launchAtStartSelected:(NSButton *)sender {
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

-(void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
	switch (notification.activationType)
	{
		case NSUserNotificationActivationTypeContentsClicked:
		{
			[[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:notification];

			NSString *urlToOpen = nil;
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

			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlToOpen]];
			[pullRequest catchUpWithComments];

			[self updateStatusItem];

			break;
		}
		default: break;
	}
}

-(void)postNotificationOfType:(PRNotificationType)type forItem:(id)item
{
	NSUserNotification *notification = [[NSUserNotification alloc] init];

	switch (type)
	{
		case kNewComment:
		{
			notification.title = @"New PR Comment";
			notification.informativeText = [item body];
			PullRequest *associatedRequest = [PullRequest pullRequestWithUrl:[item pullRequestUrl]
																		 moc:self.managedObjectContext];
			notification.subtitle = associatedRequest.title;
			notification.userInfo = @{COMMENT_ID_KEY:[item serverId]};
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
			notification.userInfo = @{PULL_REQUEST_ID_KEY:[item serverId]};
			notification.subtitle = [item title];
			break;
		}
	}

    notification.soundName = @"bell.caf";
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}

- (IBAction)myPrTitleSelected:(NSMenuItem *)sender {}

- (NSInteger)buildPrMenuItems
{
	NSInteger newCount = 0;
	if(!self.prMenuItems)
	{
		self.prMenuItems = [NSMutableArray array];
	}
	else
	{
		for(NSMenuItem *i in self.prMenuItems)
		{
			[self.statusBarMenu removeItem:i];
		}
		[self.prMenuItems removeAllObjects];
	}

	NSArray *pullRequests = [PullRequest sortedPullRequestsInMoc:self.managedObjectContext];
	NSInteger myIndex=6, commentedIndex = 8, allIndex=10;
	for(PullRequest *r in pullRequests)
	{
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:r.title action:@selector(prSelected:) keyEquivalent:@""];
		PRItemView *itemView = [[PRItemView alloc] initWithFrame:CGRectZero];
		[itemView setPullRequest:r];
		item.view = itemView;
		if(r.isMine)
		{
			[self.statusBarMenu insertItem:item atIndex:myIndex++];
			newCount += [r unreadCommentCount];
			commentedIndex++;
		}
		else if(r.commentedByMe)
		{
			[self.statusBarMenu insertItem:item atIndex:commentedIndex++];
			newCount += [r unreadCommentCount];
		}
		else
		{
			[self.statusBarMenu insertItem:item atIndex:allIndex];
		}
		allIndex++;
		[self.prMenuItems addObject:item];
	}
	return newCount;
}

- (void)prSelected:(NSMenuItem *)item
{
	NSArray *pullRequests = [PullRequest sortedPullRequestsInMoc:self.managedObjectContext];
	NSInteger index = [self.prMenuItems indexOfObject:item];
	PullRequest *r = [pullRequests objectAtIndex:index];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:r.webUrl]];
	[r catchUpWithComments];
	[self updateStatusItem];
}

- (void)defaultsUpdated
{
	if(self.api.localUser)
		self.userNameLabel.stringValue = self.api.localUser;
	else
		self.userNameLabel.stringValue = @"...";
}

- (void)startRateLimitHandling
{
	[self.apiLoad setIndeterminate:YES];
	[self.apiLoad stopAnimation:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(apiUsageUpdate:) name:RATE_UPDATE_NOTIFICATION object:nil];
	if(self.api.authToken.length)
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

	[DataItem assumeWilldeleteItemsOfType:@"Repo" inMoc:self.managedObjectContext];
	[DataItem assumeWilldeleteItemsOfType:@"Org" inMoc:self.managedObjectContext];

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

- (void)reset
{
	self.lastSuccessfulRefresh = nil;
	[DataItem deleteAllObjectsInContext:self.managedObjectContext
							 usingModel:self.managedObjectModel];
	[self.projectsTable reloadData];
	[self updateStatusItem];
}

- (IBAction)preferencesSelected:(NSMenuItem *)sender
{
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;

	if([self isAppLoginItem])
		[self.launchAtStartup setIntegerValue:1];
	else
		[self.launchAtStartup setIntegerValue:0];

	[self.preferencesWindow setLevel:NSFloatingWindowLevel];
	NSWindowController *c = [[NSWindowController alloc] initWithWindow:self.preferencesWindow];
	[c showWindow:self];
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

-(id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSArray *allRepos = [Repo allReposSortedByField:@"fullName" inMoc:self.managedObjectContext];
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

-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [DataItem countItemsOfType:@"Repo" inMoc:self.managedObjectContext];
}

-(void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSArray *allRepos = [Repo allReposSortedByField:@"fullName" inMoc:self.managedObjectContext];
	Repo *r = allRepos[row];
	r.active = @([object boolValue]);
	NSLog(@"Repo %@ is %@",r.fullName,r.active);
	[self.managedObjectContext save:nil];
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

// Returns the NSUndoManager for the application. In this case, the manager returned is that of the managed object context for the application.
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window
{
    return [[self managedObjectContext] undoManager];
}

// Performs the save action for the application, which is to send the save: message to the application's managed object context. Any encountered errors are presented to the user.
- (IBAction)saveAction:(id)sender
{
    NSError *error = nil;
    
    if (![[self managedObjectContext] commitEditing]) {
        NSLog(@"%@:%@ unable to commit editing before saving", [self class], NSStringFromSelector(_cmd));
    }
    
    if (![[self managedObjectContext] save:&error]) {
        [[NSApplication sharedApplication] presentError:error];
    }
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
    
    NSError *error = nil;
    if (![[self managedObjectContext] save:&error]) {

        // Customize this code block to include application-specific recovery steps.              
        BOOL result = [sender presentError:error];
        if (result) {
            return NSTerminateCancel;
        }

        NSString *question = NSLocalizedString(@"Could not save changes while quitting. Quit anyway?", @"Quit without saves error question message");
        NSString *info = NSLocalizedString(@"Quitting now will lose any changes you have made since the last successful save", @"Quit without saves error question info");
        NSString *quitButton = NSLocalizedString(@"Quit anyway", @"Quit anyway button title");
        NSString *cancelButton = NSLocalizedString(@"Cancel", @"Cancel button title");
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:question];
        [alert setInformativeText:info];
        [alert addButtonWithTitle:quitButton];
        [alert addButtonWithTitle:cancelButton];

        NSInteger answer = [alert runModal];
        
        if (answer == NSAlertAlternateReturn) {
            return NSTerminateCancel;
        }
    }
    return NSTerminateNow;
}

-(void)windowWillClose:(NSNotification *)notification
{
	[self controlTextDidChange:nil];
	if(self.api.authToken.length) [self startRefresh];
}

- (IBAction)refreshNowSelected:(NSMenuItem *)sender
{
	[self checkApiUsage];
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
        [alert setInformativeText:[NSString stringWithFormat:@"Your request cannot be completed until GitHub resets your hourly API allowance at %@.  If you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.  You can check your API usage at any time from the bottom of the preferences pane.",self.api.resetDate]];
        [alert addButtonWithTitle:@"OK"];
		return;
	}
	if((self.apiLoad.maxValue-self.apiLoad.doubleValue)<LOW_API_WARNING)
	{
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Your API request usage is getting very high"];
        [alert setInformativeText:[NSString stringWithFormat:@"Try to make fewer manual refreshes or reducing the number of repos you are monitoring.  Your allowance will be reset at %@, and you can check your API usage from the bottom of the preferences pane.",self.api.resetDate]];
        [alert addButtonWithTitle:@"OK"];
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
	[self.managedObjectContext save:nil];
	[self.projectsTable reloadData];
	[self updateStatusItem];
}

-(void)startRefresh
{
	[self prepareForRefresh];
	id oldTarget = self.refreshNow.target;
	SEL oldAction = self.refreshNow.action;

	if(self.api.localUser)
		self.refreshNow.title = [NSString stringWithFormat:@"Refreshing %@...",self.api.localUser];
	else
		self.refreshNow.title = @"Refreshing...";

	[self.refreshNow setAction:nil];
	[self.refreshNow setTarget:nil];
	[self.api fetchPullRequestsForActiveReposAndCallback:^(BOOL success) {
		self.refreshNow.target = oldTarget;
		self.refreshNow.action = oldAction;
		self.lastUpdateFailed = !success;
		if(success) self.lastSuccessfulRefresh = [NSDate date];
		[self completeRefresh];
		self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:REFRESH_PERIOD target:self selector:@selector(refreshIfApplicable) userInfo:nil repeats:NO];
		[self sendNotifications];
		NSLog(@"Refresh done: %d",success);
	}];
}



-(void)refreshIfApplicable
{
	if(self.api.localUserId && self.api.authToken.length)
	{
		NSLog(@"Starting refresh");
		[self startRefresh];
	}
}

-(void)sendNotifications
{
	NSArray *latestPrs = [PullRequest newItemsOfType:@"PullRequest" inMoc:self.managedObjectContext];
	for(PullRequest *r in latestPrs)
	{
		[self postNotificationOfType:kNewPr forItem:r];
		r.postSyncAction = @(kTouchedNone);
	}

	NSArray *latestComments = [PRComment newItemsOfType:@"PRComment" inMoc:self.managedObjectContext];
	for(PRComment *c in latestComments)
	{
		PullRequest *r = [PullRequest pullRequestWithUrl:c.pullRequestUrl moc:self.managedObjectContext];
		if(r.isMine || r.commentedByMe)
		{
			if(![c.userId.stringValue isEqualToString:self.api.localUserId])
			{
				[self postNotificationOfType:kNewComment forItem:c];
			}
		}
		c.postSyncAction = @(kTouchedNone);
	}
	[self.managedObjectContext save:nil];
}

-(void)updateStatusItem
{
	NSArray *pullRequests = [PullRequest sortedPullRequestsInMoc:self.managedObjectContext];
	NSString *countString = [NSString stringWithFormat:@"%ld",pullRequests.count];
	NSLog(@"Updating status item with %@ total PRs",countString);

	NSInteger newCommentCount = [self buildPrMenuItems];

	NSDictionary *attributes;
	if(newCommentCount)
	{
		attributes = @{
					   NSFontAttributeName: [NSFont systemFontOfSize:11.0],
					   NSForegroundColorAttributeName: [NSColor blackColor],
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

	CGFloat padding = 3.0;
	NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
	CGFloat H = statusBar.thickness;
	CGFloat length = H+width+padding*3;
	if(self.statusItem)
	{
		self.statusItem.length = length;
	}
	else
	{
		self.statusItem = [statusBar statusItemWithLength:length];
	}

	NSImage *newImage = [[NSImage alloc] initWithSize:CGSizeMake(self.statusItem.length, H)];
    [newImage lockFocus];
	NSImage *oldImage = [NSImage imageNamed:NSImageNameApplicationIcon];
	[oldImage drawInRect:CGRectMake(padding, 0, H, H)
				fromRect:NSZeroRect
			   operation:NSCompositeSourceOver
				fraction:1.0];
	[countString drawInRect:CGRectMake(H+padding, -5, width, H) withAttributes:attributes];
    [newImage unlockFocus];
	[newImage setTemplate:YES];

	self.statusItem.image = newImage;
	self.statusItem.highlightMode = YES;
	self.statusItem.menu = self.statusBarMenu;
	self.statusItem.menu.delegate = self;
}

-(void)menuWillOpen:(NSMenu *)menu
{
	if(self.refreshNow.target)
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
}

- (IBAction)selectAllSelected:(NSButton *)sender
{
	NSArray *allRepos = [Repo allReposSortedByField:@"fullName" inMoc:self.managedObjectContext];
	for(Repo *r in allRepos)
	{
		r.active = @YES;
	}
	[self.managedObjectContext save:nil];
	[self.projectsTable reloadData];
}

- (IBAction)clearallSelected:(NSButton *)sender
{
	NSArray *allRepos = [Repo allReposSortedByField:@"fullName" inMoc:self.managedObjectContext];
	for(Repo *r in allRepos)
	{
		r.active = @NO;
	}
	[self.managedObjectContext save:nil];
	[self.projectsTable reloadData];
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
				NSLog(@"comparing: %@ %@",uu,appPath);
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

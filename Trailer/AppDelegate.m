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
	_static_shared_ref = self;

	[self updateStatusItem];

	self.api = [[API alloc] init];
	[self.githubToken setStringValue:self.api.authToken];
	[self controlTextDidChange:nil];

	self.api = [[API alloc] init];

	[self startRateLimitHandling];

	if(!self.githubToken)
	{
		[self preferencesSelected:nil];
	}

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(defaultsUpdated)
												 name:NSUserDefaultsDidChangeNotification
											   object:nil];
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
	NSInteger index=6;
	for(PullRequest *r in pullRequests)
	{
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:r.title action:@selector(prSelected:) keyEquivalent:@""];
		PRItemView *itemView = [[PRItemView alloc] initWithFrame:CGRectZero];
		[itemView setPullRequest:r];
		newCount += [r unreadCommentCount];
		item.view = itemView;
		[self.statusBarMenu insertItem:item atIndex:index++];
		[self.prMenuItems addObject:item];
	}
	return newCount;
}

- (void)prSelected:(NSMenuItem *)item
{
	NSArray *pullRequests = [PullRequest sortedPullRequestsInMoc:self.managedObjectContext];
	NSInteger index = [self.prMenuItems indexOfObject:item];
	PullRequest *r = [pullRequests objectAtIndex:index];
	NSWorkspace *ws = [NSWorkspace sharedWorkspace];
	[ws openURL:[NSURL URLWithString:r.webUrl]];
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

- (IBAction)refreshReposSelected:(NSButton *)sender {

	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	[d setObject:[self.githubToken stringValue] forKey:GITHUB_TOKEN_KEY];

	[self.activityDisplay startAnimation:self];
	self.refreshButton.enabled = NO;

	[DataItem unTouchItemsOfType:@"Repo" inMoc:self.managedObjectContext];
	[DataItem unTouchItemsOfType:@"Org" inMoc:self.managedObjectContext];

	[self.api fetchRepositoriesAndCallback:^(BOOL success) {

		NSAssert([NSThread isMainThread], @"Should be main thread!");

		[self.activityDisplay stopAnimation:self];
		self.refreshButton.enabled = YES;

		NSArray *allRepos = [Repo allItemsOfType:@"Repo" inMoc:self.managedObjectContext];
		NSLog(@"now monitoring %lu repos",allRepos.count);

		if(!success)
		{
            NSError *error = [NSError errorWithDomain:@"YOUR_ERROR_DOMAIN"
												 code:101
											 userInfo:@{NSLocalizedDescriptionKey:@"Error while fetching data from GitHub, please check that the token you have provided is correct and that you have a working network connection"}];
            [[NSApplication sharedApplication] presentError:error];
		}
		else
		{
			[DataItem nukeUntouchedItemsOfType:@"Repo" inMoc:self.managedObjectContext];
			[DataItem nukeUntouchedItemsOfType:@"Org" inMoc:self.managedObjectContext];
			[self.managedObjectContext save:nil];
			[self.projectsTable reloadData];
		}
	}];
}

-(void)controlTextDidChange:(NSNotification *)obj
{
	self.refreshButton.enabled = ([self.githubToken stringValue].length!=0);
}

- (IBAction)preferencesSelected:(NSMenuItem *)sender {
	[self.preferencesWindow setLevel:NSFloatingWindowLevel];
	NSWindowController *c = [[NSWindowController alloc] initWithWindow:self.preferencesWindow];
	[c showWindow:self];
}

- (IBAction)createTokenSelected:(NSButton *)sender {
	NSWorkspace * ws = [NSWorkspace sharedWorkspace];
	[ws openURL:[NSURL URLWithString:@"https://github.com/settings/tokens/new"]];
}

- (IBAction)viewExistingTokensSelected:(NSButton *)sender {
	NSWorkspace * ws = [NSWorkspace sharedWorkspace];
	[ws openURL:[NSURL URLWithString:@"https://github.com/settings/applications"]];
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
    _managedObjectContext = [[NSManagedObjectContext alloc] init];
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
	[self startRefresh];
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

-(void)startRefresh
{
	NSArray *activeRepos = [Repo activeReposInMoc:self.managedObjectContext];
	if(activeRepos.count==0) return;

	id oldTarget = self.refreshNow.target;
	SEL oldAction = self.refreshNow.action;
	[self.refreshButton setEnabled:NO];
	[self.projectsTable setEnabled:NO];
	[self.selectAll setEnabled:NO];
	[self.clearAll setEnabled:NO];
	[self.activityDisplay startAnimation:nil];
	[self.refreshNow setAction:nil];
	[self.refreshNow setTarget:nil];
	[self updateStatusItem];
	[self.api fetchPullRequestsForActiveReposAndCallback:^(BOOL success) {
		NSArray *pullRequests = [PullRequest allItemsOfType:@"PullRequest" inMoc:self.managedObjectContext];
		for(PullRequest *r in pullRequests)
		{
			NSLog(@"PR '%@' has %ld comments",r.title,[PRComment countCommentsForPullRequestUrl:r.url inMoc:self.managedObjectContext]);
		}
		NSLog(@"Done with %ld PRs: %d",pullRequests.count,success);
		[self.managedObjectContext save:nil];
		[self.projectsTable reloadData];
		[self.refreshNow setTarget:oldTarget];
		[self.refreshNow setAction:oldAction];
		[self.refreshButton setEnabled:YES];
		[self.projectsTable setEnabled:YES];
		[self.selectAll setEnabled:YES];
		[self.clearAll setEnabled:YES];
		[self.activityDisplay stopAnimation:nil];
		[self updateStatusItem];
	}];
}

-(void)updateStatusItem
{
	NSArray *pullRequests = [PullRequest sortedPullRequestsInMoc:self.managedObjectContext];
	NSString *countString;
	if(self.refreshNow.target)
	{
		countString = [NSString stringWithFormat:@"%ld",pullRequests.count];
	}
	else
	{
		countString = @"...";
	}
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
	if(!self.statusItem)
	{
		self.statusItem = [statusBar statusItemWithLength:length];
	}
	else
	{
		self.statusItem.length = length;
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

@end

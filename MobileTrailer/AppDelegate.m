//
//  AppDelegate.m
//  MobileTrailer
//
//  Created by Paul Tsochantaris on 4/1/14.
//  Copyright (c) 2014 HouseTrip. All rights reserved.
//

@implementation AppDelegate

static AppDelegate *_static_shared_ref;
+(AppDelegate *)shared { return _static_shared_ref; }

CGFloat GLOBAL_SCREEN_SCALE;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	_static_shared_ref = self;

	// Useful snippet for resetting prefs when testing
	//NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
	//[[NSUserDefaults standardUserDefaults] removePersistentDomainForName:appDomain];

	GLOBAL_SCREEN_SCALE = [UIScreen mainScreen].scale;

	self.filterTimer = [[HTPopTimer alloc] initWithTimeInterval:0.2 target:self selector:@selector(filterTimerPopped)];

	self.dataManager = [[DataManager alloc] init];
	self.api = [[API alloc] init];

	if(self.api.authToken.length) [self.api updateLimitFromServer];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(defaultsUpdated)
												 name:NSUserDefaultsDidChangeNotification
											   object:nil];

	[self setupUI];

	if(self.api.authToken.length)
	{
		//[self.githubTokenHolder setStringValue:self.api.authToken];
		[self startRefresh];
	}
	else
	{
		[self forcePreferences];
	}

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(networkStateChanged)
												 name:kReachabilityChangedNotification
											   object:nil];

    return YES;
}

- (void)setupUI
{
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
	    UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
	    UINavigationController *navigationController = [splitViewController.viewControllers lastObject];
	    splitViewController.delegate = (id)navigationController.topViewController;

	    UINavigationController *masterNavigationController = splitViewController.viewControllers[0];
	    MasterViewController *controller = (MasterViewController *)masterNavigationController.topViewController;
	    controller.managedObjectContext = self.dataManager.managedObjectContext;
	} else {
	    UINavigationController *navigationController = (UINavigationController *)self.window.rootViewController;
	    MasterViewController *controller = (MasterViewController *)navigationController.topViewController;
	    controller.managedObjectContext = self.dataManager.managedObjectContext;
	}
}

- (void)filterTimerPopped
{
	// TODO
}

- (void)defaultsUpdated
{
	// TODO
}

- (void)forcePreferences
{
	// TODO
}

- (void)sendNotifications
{
	// TODO
}

- (void)networkStateChanged
{
	if([self.api.reachability currentReachabilityStatus]!=NotReachable)
	{
		DLog(@"Network is back");
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
			DLog(@"No need to refresh yet, will refresh in %f",howLongUntilNextSync);
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










- (IBAction)refreshNowSelected
{
	NSArray *activeRepos = [Repo activeReposInMoc:self.dataManager.managedObjectContext];
	if(activeRepos.count==0)
	{
		[self forcePreferences];
		return;
	}
	[self startRefresh];
}

- (void)checkApiUsage
{
	if(self.api.requestsRemaining==0)
	{
		[[[UIAlertView alloc] initWithTitle:@"Your API request usage is over the limit!"
									message:[NSString stringWithFormat:@"Your request cannot be completed until GitHub resets your hourly API allowance at %@.\n\nIf you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.\n\nYou can check your API usage at any time from the bottom of the preferences pane at any time.",self.api.resetDate]
								   delegate:nil
						  cancelButtonTitle:@"OK"
						  otherButtonTitles:nil] show];
		return;
	}
	else if((self.api.requestsRemaining/self.api.requestsLimit)<LOW_API_WARNING)
	{
		[[[UIAlertView alloc] initWithTitle:@"Your API request usage is close to full"
									message:[NSString stringWithFormat:@"Try to make fewer manual refreshes, increasing the automatic refresh time, or reducing the number of repos you are monitoring.\n\nYour allowance will be reset by Github on %@.\n\nYou can check your API usage from the bottom of the preferences pane.",self.api.resetDate]
								   delegate:nil
						  cancelButtonTitle:@"OK"
						  otherButtonTitles:nil] show];
	}
}

-(void)prepareForRefresh
{
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;

	if(self.dataManager.justMigrated)
	{
		DLog(@"FORCING ALL PRS TO BE REFETCHED");
		NSArray *prs = [PullRequest allItemsOfType:@"PullRequest" inMoc:self.dataManager.managedObjectContext];
		for(PullRequest *r in prs) r.updatedAt = [NSDate distantPast];
		self.dataManager.justMigrated = NO;
	}
}

-(void)completeRefresh
{
	[self.dataManager saveDB];
	[self checkApiUsage];
	[self sendNotifications];
	self.isRefreshing = NO;
}

-(void)startRefresh
{
	if(self.isRefreshing) return;
	self.isRefreshing = YES;
	DLog(@"Starting refresh");
	[self prepareForRefresh];

	[self.api fetchPullRequestsForActiveReposAndCallback:^(BOOL success) {
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
		DLog(@"Refresh done");
	}];
}

-(void)refreshTimerDone
{
	if(self.api.localUserId && self.api.authToken.length)
	{
		[self startRefresh];
	}
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
	[self startRefreshIfItIsDue];
}

-(void)postNotificationOfType:(PRNotificationType)type forItem:(id)item
{
	if(self.preferencesDirty) return;

	UILocalNotification *notification = [[UILocalNotification alloc] init];

	switch (type)
	{
		case kNewComment:
		{
			PullRequest *associatedRequest = [PullRequest pullRequestWithUrl:[item pullRequestUrl] moc:self.dataManager.managedObjectContext];
			notification.alertBody = [NSString stringWithFormat:@"Comment for '%@': %@",associatedRequest.title,[item body]];
			notification.userInfo = @{COMMENT_ID_KEY:[item serverId]};
			break;
		}
		case kNewPr:
		{
			notification.alertBody = [NSString stringWithFormat:@"New PR: %@",[item title]];
			notification.userInfo = @{PULL_REQUEST_ID_KEY:[item serverId]};
			break;
		}
		case kPrMerged:
		{
			notification.alertBody = [NSString stringWithFormat:@"PR Merged: %@",[item title]];
			notification.userInfo = @{NOTIFICATION_URL_KEY:[item webUrl]};
			break;
		}
	}

    [[UIApplication sharedApplication] presentLocalNotificationNow:notification];
}

@end

#import "MasterViewController.h"

iOS_AppDelegate *app;
NSString *currentAppVersion;

@implementation iOS_AppDelegate
{
	UIPopoverController *sharePopover;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	app = self;

	self.lastRepoCheck = [NSDate distantPast];
	self.enteringForeground = YES;

	[DataManager postProcessAllPrs];

	if([ApiServer someServersHaveAuthTokensInMoc:DataManager.managedObjectContext])
		[api updateLimitsFromServer];

	UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
	splitViewController.minimumPrimaryColumnWidth = 320;
	splitViewController.maximumPrimaryColumnWidth = 320;
	splitViewController.delegate = self;

	MasterViewController *m = (MasterViewController *)[(UINavigationController *)splitViewController.viewControllers[0] topViewController];
	m.clearsSelectionOnViewWillAppear = NO; // for iPad

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(networkStateChanged)
												 name:kReachabilityChangedNotification
											   object:nil];

	[[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:Settings.backgroundRefreshPeriod];

	UILocalNotification *localNotification = [launchOptions objectForKey:UIApplicationLaunchOptionsLocalNotificationKey];

	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		NSManagedObjectContext *moc = DataManager.managedObjectContext;
		if([Repo visibleReposInMoc:moc]>0 && [ApiServer someServersHaveAuthTokensInMoc:moc])
		{
			if(localNotification) [self handleLocalNotification:localNotification];
		}
		else
		{
			[self forcePreferences];
		}
	});

	UIUserNotificationSettings *notificationSettings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound
																						 categories:nil];
	[[UIApplication sharedApplication] registerUserNotificationSettings:notificationSettings];

	return YES;
}

- (BOOL)splitViewController:(UISplitViewController *)splitViewController
collapseSecondaryViewController:(UIViewController *)secondaryViewController
  ontoPrimaryViewController:(UIViewController *)primaryViewController
{
	MasterViewController *m = (MasterViewController *)[(UINavigationController *)primaryViewController viewControllers][0];
	m.clearsSelectionOnViewWillAppear = YES;
	DetailViewController *d = (DetailViewController *)[(UINavigationController *)secondaryViewController viewControllers][0];
	return (d.detailItem==nil);
}

- (UIViewController *)splitViewController:(UISplitViewController *)splitViewController separateSecondaryViewControllerFromPrimaryViewController:(UIViewController *)primaryViewController
{
	MasterViewController *m = (MasterViewController *)[(UINavigationController *)primaryViewController viewControllers][0];
	m.clearsSelectionOnViewWillAppear = NO;
	return nil;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
	self.enteringForeground = YES;
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
	if(notification && self.enteringForeground)
	{
		[self handleLocalNotification:notification];
	}
}

- (void)handleLocalNotification:(UILocalNotification *)notification
{
	DLog(@"Received local notification: %@",notification.userInfo);
	[[NSNotificationCenter defaultCenter] postNotificationName:RECEIVED_NOTIFICATION_KEY object:nil userInfo:notification.userInfo];
	[[UIApplication sharedApplication] cancelLocalNotification:notification];
}

- (void)forcePreferences
{
	UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
	UINavigationController *masterNavigationController = splitViewController.viewControllers[0];
	MasterViewController *controller = (MasterViewController *)masterNavigationController.viewControllers[0];

	[controller performSegueWithIdentifier:@"showPreferences" sender:self];
}

- (void)networkStateChanged
{
	if([api.reachability currentReachabilityStatus]!=NotReachable)
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
		if(howLongAgo>Settings.refreshPeriod)
		{
			[self startRefresh];
		}
		else
		{
			NSTimeInterval howLongUntilNextSync = Settings.refreshPeriod-howLongAgo;
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

- (void)refreshMainList
{
	[DataManager postProcessAllPrs];

	UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
	UINavigationController *masterNavigationController = splitViewController.viewControllers[0];
	MasterViewController *controller = (MasterViewController *)masterNavigationController.viewControllers[0];
	[controller reloadData];
}

- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(backgroundFetchCompletionCallback)completionHandler
{
	self.backgroundCallback = completionHandler;
	[self startRefresh];
}

- (void)checkApiUsage
{
	for(ApiServer *apiServer in [ApiServer allApiServersInMoc:DataManager.managedObjectContext])
	{
		if(apiServer.goodToGo && apiServer.requestsLimit.doubleValue>0)
		{
			if(apiServer.requestsRemaining.doubleValue==0)
			{
				[[[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"%@ API request usage is over the limit!",apiServer.label]
											message:[NSString stringWithFormat:@"Your request cannot be completed until GitHub resets your hourly API allowance at %@.\n\nIf you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.\n\nYou can check your API usage at any time from the bottom of the preferences pane at any time.",apiServer.resetDate]
										   delegate:nil
								  cancelButtonTitle:@"OK"
								  otherButtonTitles:nil] show];
				return;
			}
			else if((apiServer.requestsRemaining.doubleValue/apiServer.requestsLimit.doubleValue)<LOW_API_WARNING)
			{
				[[[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"%@ API request usage is close to full",apiServer.label]
											message:[NSString stringWithFormat:@"Try to make fewer manual refreshes, increasing the automatic refresh time, or reducing the number of repos you are monitoring.\n\nYour allowance will be reset by Github on %@.\n\nYou can check your API usage from the bottom of the preferences pane.",apiServer.resetDate]
										   delegate:nil
								  cancelButtonTitle:@"OK"
								  otherButtonTitles:nil] show];
			}
		}
	}
}

- (void)prepareForRefresh
{
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;

	self.isRefreshing = YES;
	[[NSNotificationCenter defaultCenter] postNotificationName:REFRESH_STARTED_NOTIFICATION object:nil];
	DLog(@"Starting refresh");

	[api expireOldImageCacheEntries];
	[DataManager postMigrationTasks];
}

- (void)completeRefresh
{
	[self checkApiUsage];
	self.isRefreshing = NO;
	[[NSNotificationCenter defaultCenter] postNotificationName:REFRESH_ENDED_NOTIFICATION object:nil];
	[DataManager saveDB];
	[DataManager sendNotifications];
}

- (BOOL)startRefresh
{
	if(self.isRefreshing) return NO;

	if([api.reachability currentReachabilityStatus]==NotReachable) return NO;

	if(![ApiServer someServersHaveAuthTokensInMoc:DataManager.managedObjectContext]) return NO;

	[self prepareForRefresh];

	[api fetchPullRequestsForActiveReposAndCallback:^{
		BOOL success = ![ApiServer shouldReportRefreshFailureInMoc:DataManager.managedObjectContext];
		self.lastUpdateFailed = !success;
		BOOL hasNewData = (success && DataManager.managedObjectContext.hasChanges);
		if(success)
		{
			self.lastSuccessfulRefresh = [NSDate date];
			self.preferencesDirty = NO;
		}
		[self completeRefresh];
		if(self.backgroundCallback)
		{
			if(hasNewData)
			{
				DLog(@">> got new data!");
				self.backgroundCallback(UIBackgroundFetchResultNewData);
			}
			else if(success)
			{
				DLog(@"no new data");
				self.backgroundCallback(UIBackgroundFetchResultNoData);
			}
			else
			{
				DLog(@"background refresh failed");
				self.backgroundCallback(UIBackgroundFetchResultFailed);
			}
			self.backgroundCallback = nil;
		}

		if(!success && [UIApplication sharedApplication].applicationState==UIApplicationStateActive)
		{
			[[[UIAlertView alloc] initWithTitle:@"Refresh failed"
										message:@"Loading the latest data from Github failed"
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
		}

		self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:Settings.refreshPeriod
															 target:self
														   selector:@selector(refreshTimerDone)
														   userInfo:nil
															repeats:NO];
		DLog(@"Refresh done");
	}];

	return YES;
}

- (void)refreshTimerDone
{
	NSManagedObjectContext *moc = DataManager.managedObjectContext;
	if([ApiServer someServersHaveAuthTokensInMoc:moc] && ([Repo countVisibleReposInMoc:moc]>0))
	{
		[self startRefresh];
	}
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
	self.enteringForeground = NO;
	[self startRefreshIfItIsDue];
}

- (void)postNotificationOfType:(PRNotificationType)type forItem:(id)item
{
	if(self.preferencesDirty) return;

	UILocalNotification *notification = [[UILocalNotification alloc] init];
	notification.userInfo = [DataManager infoForType:type item:item];

	switch (type)
	{
		case kNewMention:
		{
			PRComment *c = item;
			notification.alertBody = [NSString stringWithFormat:@"@%@ mentioned you in '%@': %@", c.userName, c.pullRequest.title, c.body];
			break;
		}
		case kNewComment:
		{
			PRComment *c = item;
			notification.alertBody = [NSString stringWithFormat:@"@%@ commented on '%@': %@", c.userName, c.pullRequest.title, c.body];
			break;
		}
		case kNewPr:
		{
			notification.alertBody = [NSString stringWithFormat:@"New PR: %@",[item title]];
			break;
		}
		case kPrReopened:
		{
			notification.alertBody = [NSString stringWithFormat:@"Re-Opened PR: %@",[item title]];
			break;
		}
		case kPrMerged:
		{
			notification.alertBody = [NSString stringWithFormat:@"PR Merged! %@",[item title]];
			break;
		}
		case kPrClosed:
		{
			notification.alertBody = [NSString stringWithFormat:@"PR Closed: %@",[item title]];
			break;
		}
		case kNewRepoSubscribed:
		{
			notification.alertBody = [NSString stringWithFormat:@"New Repository Subscribed: %@",[item fullName]];
			break;
		}
		case kNewRepoAnnouncement:
		{
			notification.alertBody = [NSString stringWithFormat:@"New Repository: %@",[item fullName]];
			break;
		}
		case kNewPrAssigned:
		{
			notification.alertBody = [NSString stringWithFormat:@"PR Assigned: %@",[item title]];
			break;
		}
	}

	// Present notifications only if the user isn't currenty reading notifications in the notification center, over the open app, a corner case
	// Otherwise the app will end up consuming them
	if(self.enteringForeground)
	{
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{

			while([UIApplication sharedApplication].applicationState==UIApplicationStateInactive)
				[NSThread sleepForTimeInterval:1.0];

			dispatch_sync(dispatch_get_main_queue(), ^{
				[[UIApplication sharedApplication] presentLocalNotificationNow:notification];
			});
		});
	}
	else
	{
		[[UIApplication sharedApplication] presentLocalNotificationNow:notification];
	}
}

/////////////// sharing

- (void)shareFromView:(UIViewController *)view buttonItem:(UIBarButtonItem *)button url:(NSURL *)url
{
	OpenInSafariActivity *a = [[OpenInSafariActivity alloc] init];
	UIActivityViewController * v = [[UIActivityViewController alloc] initWithActivityItems:@[url]
																	 applicationActivities:@[a]];
	if(UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad)
	{
		sharePopover = [[UIPopoverController alloc] initWithContentViewController:v];
		sharePopover.delegate = self;
		[sharePopover presentPopoverFromBarButtonItem:button permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
	}
	else
	{
		[view presentViewController:v animated:YES completion:nil];
	}
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController
{
	sharePopover = nil;
}

@end

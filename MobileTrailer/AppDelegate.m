
AppDelegate *app;

@implementation AppDelegate
{
	UIPopoverController *sharePopover;
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
	DLog(@"Memory warning");
	[[NSURLCache sharedURLCache] removeAllCachedResponses];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	app = self;

	self.currentAppVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];

	self.enteringForeground = YES;

	// Useful snippet for resetting prefs when testing
	//NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
	//[[NSUserDefaults standardUserDefaults] removePersistentDomainForName:appDomain];

	settings = [[Settings alloc] init];
	self.dataManager = [[DataManager alloc] init];
	self.api = [[API alloc] init];

	// ONLY FOR DEBUG!
	/*
	 #warning COMMENT THIS
	 NSArray *allPRs = [PullRequest allItemsOfType:@"PullRequest" inMoc:self.dataManager.managedObjectContext];
	 PullRequest *firstPr = allPRs[2];
	 firstPr.updatedAt = [NSDate distantPast];

	 Repo *r = [Repo itemOfType:@"Repo" serverId:firstPr.repoId moc:self.dataManager.managedObjectContext];
	 r.updatedAt = [NSDate distantPast];

	 NSString *prUrl = firstPr.url;
	 NSArray *allCommentsForFirstPr = [PRComment commentsForPullRequestUrl:prUrl inMoc:self.dataManager.managedObjectContext];
	 [self.dataManager.managedObjectContext deleteObject:[allCommentsForFirstPr objectAtIndex:0]];
	 */
	// ONLY FOR DEBUG!

	[self.dataManager postProcessAllPrs];

	if(settings.authToken.length) [self.api updateLimitFromServer];

	UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
	splitViewController.minimumPrimaryColumnWidth = 240;
	splitViewController.preferredPrimaryColumnWidthFraction = 0.3;
	splitViewController.delegate = self;

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(networkStateChanged)
												 name:kReachabilityChangedNotification
											   object:nil];

	[[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:settings.backgroundRefreshPeriod];

	UILocalNotification *localNotification = [launchOptions objectForKey:UIApplicationLaunchOptionsLocalNotificationKey];

	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		if([Repo visibleReposInMoc:self.dataManager.managedObjectContext]==0 || settings.authToken.length==0)
		{
			[self forcePreferences];
		}
		else
		{
			if(localNotification) [self handleLocalNotification:localNotification];
		}
	});

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
		if(howLongAgo>settings.refreshPeriod)
		{
			[self startRefresh];
		}
		else
		{
			NSTimeInterval howLongUntilNextSync = settings.refreshPeriod-howLongAgo;
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

- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(backgroundFetchCompletionCallback)completionHandler
{
	self.backgroundCallback = completionHandler;
	[self startRefresh];
}

- (void)checkApiUsage
{
	if(settings.authToken.length==0) return;
	if(self.api.requestsLimit>0)
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
}

- (void)prepareForRefresh
{
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;

    self.isRefreshing = YES;
	[[NSNotificationCenter defaultCenter] postNotificationName:REFRESH_STARTED_NOTIFICATION object:nil];
	DLog(@"Starting refresh");

    [self.api expireOldImageCacheEntries];
	[self.dataManager postMigrationTasks];
}

- (void)completeRefresh
{
	[self checkApiUsage];
	self.isRefreshing = NO;
	[[NSNotificationCenter defaultCenter] postNotificationName:REFRESH_ENDED_NOTIFICATION object:nil];
	[self.dataManager sendNotifications];
	[self.dataManager saveDB];
}

- (void)startRefresh
{
	if(self.isRefreshing) return;

	if([app.api.reachability currentReachabilityStatus]==NotReachable) return;

	if(settings.authToken.length==0) return;

	[self prepareForRefresh];

	[self.api fetchPullRequestsForActiveReposAndCallback:^(BOOL success) {
		self.lastUpdateFailed = !success;
		BOOL hasNewData = (success && self.dataManager.managedObjectContext.hasChanges);
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
			if(!settings.dontReportRefreshFailures)
			{
				[[[UIAlertView alloc] initWithTitle:@"Refresh failed"
											message:@"Loading the latest data from Github failed"
										   delegate:nil
								  cancelButtonTitle:@"OK"
								  otherButtonTitles:nil] show];
			}
		}

		self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:settings.refreshPeriod
															 target:self
														   selector:@selector(refreshTimerDone)
														   userInfo:nil
															repeats:NO];
		DLog(@"Refresh done");
	}];
}

- (void)refreshTimerDone
{
	if(settings.localUserId && settings.authToken.length)
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
	notification.userInfo = [self.dataManager infoForType:type item:item];

	switch (type)
	{
		case kNewMention:
		{
			PRComment *c = item;
			PullRequest *associatedRequest = [PullRequest pullRequestWithUrl:c.pullRequestUrl moc:c.managedObjectContext];
			notification.alertBody = [NSString stringWithFormat:@"@%@ mentioned you in '%@': %@", c.userName, associatedRequest.title, c.body];
			break;
		}
		case kNewComment:
		{
			PRComment *c = item;
			PullRequest *associatedRequest = [PullRequest pullRequestWithUrl:c.pullRequestUrl moc:c.managedObjectContext];
			notification.alertBody = [NSString stringWithFormat:@"@%@ commented on '%@': %@", c.userName, associatedRequest.title, c.body];
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


@implementation AppDelegate

static AppDelegate *_static_shared_ref;
+ (AppDelegate *)shared { return _static_shared_ref; }

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
	DLog(@"Memory warning");
	[[NSURLCache sharedURLCache] removeAllCachedResponses];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	_static_shared_ref = self;

	self.currentAppVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];

	self.enteringForeground = YES;

	// Useful snippet for resetting prefs when testing
	//NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
	//[[NSUserDefaults standardUserDefaults] removePersistentDomainForName:appDomain];

	self.dataManager = [[DataManager alloc] init];
	self.api = [[API alloc] init];

	// ONLY FOR DEBUG!
	//NSArray *allPRs = [PullRequest allItemsOfType:@"PullRequest" inMoc:self.dataManager.managedObjectContext];
	//[self.dataManager.managedObjectContext deleteObject:[allPRs firstObject]];
    //[allPRs.firstObject setCondition:@kPullRequestConditionMerged];

	[self.dataManager postProcessAllPrs];

	if([Settings shared].authToken.length) [self.api updateLimitFromServer];

	[self setupUI];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(networkStateChanged)
												 name:kReachabilityChangedNotification
											   object:nil];

	[[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:[Settings shared].backgroundRefreshPeriod];

	UILocalNotification *localNotification = [launchOptions objectForKey:UIApplicationLaunchOptionsLocalNotificationKey];

	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		if([Repo visibleReposInMoc:self.dataManager.managedObjectContext]==0 || [Settings shared].authToken.length==0)
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

- (void)setupUI
{
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
	{
	    UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
	    UINavigationController *navigationController = [splitViewController.viewControllers lastObject];
	    splitViewController.delegate = (id)navigationController.topViewController;

	    UINavigationController *masterNavigationController = splitViewController.viewControllers[0];
	    MasterViewController *controller = (MasterViewController *)masterNavigationController.topViewController;
	    controller.managedObjectContext = self.dataManager.managedObjectContext;
	}
	else
	{
	    UINavigationController *navigationController = (UINavigationController *)self.window.rootViewController;
	    MasterViewController *controller = (MasterViewController *)navigationController.topViewController;
	    controller.managedObjectContext = self.dataManager.managedObjectContext;
	}
}

- (void)forcePreferences
{
	MasterViewController *controller = nil;

	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
	{
		UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
		UINavigationController *masterNavigationController = splitViewController.viewControllers[0];
		controller = (MasterViewController *)masterNavigationController.topViewController;
	}
	else
	{
		UINavigationController *navigationController = (UINavigationController *)self.window.rootViewController;
		controller = (MasterViewController *)navigationController.topViewController;
	}
	
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
		if(howLongAgo>[Settings shared].refreshPeriod)
		{
			[self startRefresh];
		}
		else
		{
			NSTimeInterval howLongUntilNextSync = [Settings shared].refreshPeriod-howLongAgo;
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
	if([Settings shared].authToken.length==0) return;
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

	if([[AppDelegate shared].api.reachability currentReachabilityStatus]==NotReachable) return;

	if([Settings shared].authToken.length==0) return;

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
			if(![Settings shared].dontReportRefreshFailures)
			{
				[[[UIAlertView alloc] initWithTitle:@"Refresh failed"
											message:@"Loading the latest data from Github failed"
										   delegate:nil
								  cancelButtonTitle:@"OK"
								  otherButtonTitles:nil] show];
			}
		}

		self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:[Settings shared].refreshPeriod
															 target:self
														   selector:@selector(refreshTimerDone)
														   userInfo:nil
															repeats:NO];
		DLog(@"Refresh done");
	}];
}

- (void)refreshTimerDone
{
	if([Settings shared].localUserId && [Settings shared].authToken.length)
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
			PullRequest *associatedRequest = [PullRequest pullRequestWithUrl:[item pullRequestUrl] moc:self.dataManager.managedObjectContext];
			notification.alertBody = [NSString stringWithFormat:@"Mentioned in Comment for '%@': %@",associatedRequest.title,[item body]];
			break;
		}
		case kNewComment:
		{
			PullRequest *associatedRequest = [PullRequest pullRequestWithUrl:[item pullRequestUrl] moc:self.dataManager.managedObjectContext];
			notification.alertBody = [NSString stringWithFormat:@"Comment for '%@': %@",associatedRequest.title,[item body]];
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

@end

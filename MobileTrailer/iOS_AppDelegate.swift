
var app: iOS_AppDelegate!

let REFRESH_STARTED_NOTIFICATION = "RefreshStartedNotification"
let REFRESH_ENDED_NOTIFICATION = "RefreshEndedNotification"
let RECEIVED_NOTIFICATION_KEY = "ReceivedNotificationKey"

class iOS_AppDelegate: UIResponder, UIApplicationDelegate, UIPopoverControllerDelegate, UISplitViewControllerDelegate {

	var preferencesDirty: Bool = false
	var isRefreshing: Bool = false
	var lastUpdateFailed: Bool = false
	var enteringForeground: Bool = true
	var lastSuccessfulRefresh: NSDate?
	var lastRepoCheck = NSDate.distantPast() as NSDate
	var window: UIWindow!
	var backgroundTask = UIBackgroundTaskInvalid

	var refreshTimer: NSTimer?
	var backgroundCallback: ((UIBackgroundFetchResult) -> Void)?

	private var sharePopover: UIPopoverController?

	func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject : AnyObject]?) -> Bool {
		app = self

		DataManager.postProcessAllPrs()

		if ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
			api.updateLimitsFromServer()
		}

		let splitViewController = window.rootViewController as UISplitViewController
		splitViewController.minimumPrimaryColumnWidth = 320
		splitViewController.maximumPrimaryColumnWidth = 320
		splitViewController.delegate = self

		let m = (splitViewController.viewControllers[0] as UINavigationController).topViewController as MasterViewController
		m.clearsSelectionOnViewWillAppear = false // for iPad

		UIApplication.sharedApplication().setMinimumBackgroundFetchInterval(NSTimeInterval(Settings.backgroundRefreshPeriod))

		let localNotification = launchOptions?[UIApplicationLaunchOptionsLocalNotificationKey] as? UILocalNotification

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (Int64)(0.1 * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
			if Repo.visibleReposInMoc(mainObjectContext).count > 0 && ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
				if localNotification != nil {
					self.handleLocalNotification(localNotification!)
				}
			} else {
				self.forcePreferences()
			}
		}

		let notificationSettings = UIUserNotificationSettings(forTypes: UIUserNotificationType.Alert | UIUserNotificationType.Badge | UIUserNotificationType.Sound, categories: nil)
		UIApplication.sharedApplication().registerUserNotificationSettings(notificationSettings)
		return true
	}

	func splitViewController(splitViewController: UISplitViewController, collapseSecondaryViewController secondaryViewController: UIViewController!, ontoPrimaryViewController primaryViewController: UIViewController!) -> Bool {
		let m = (primaryViewController as UINavigationController).viewControllers.first as MasterViewController
		m.clearsSelectionOnViewWillAppear = true
		let d = (secondaryViewController as UINavigationController).viewControllers.first as DetailViewController
		return d.detailItem==nil
	}

	func splitViewController(splitViewController: UISplitViewController, separateSecondaryViewControllerFromPrimaryViewController primaryViewController: UIViewController!) -> UIViewController? {
		let m = (primaryViewController as UINavigationController).viewControllers.first as MasterViewController
		m.clearsSelectionOnViewWillAppear = false
		return nil
	}

	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}

	func applicationWillResignActive(application: UIApplication) {
		enteringForeground = true
	}

	func application(application: UIApplication, didReceiveLocalNotification notification: UILocalNotification) {
		if enteringForeground {
			handleLocalNotification(notification)
		}
	}

	private func handleLocalNotification(notification: UILocalNotification) {
		DLog("Received local notification: %@", notification.userInfo)
		NSNotificationCenter.defaultCenter().postNotificationName(RECEIVED_NOTIFICATION_KEY, object: nil, userInfo: notification.userInfo)
		UIApplication.sharedApplication().cancelLocalNotification(notification)
	}

	private func forcePreferences() {
		let m = ((window.rootViewController as UISplitViewController).viewControllers.first as UINavigationController).viewControllers.first as MasterViewController
		m.performSegueWithIdentifier("showPreferences", sender: self)
	}

	func startRefreshIfItIsDue() {

		refreshTimer?.invalidate()
		refreshTimer = nil

		if let l = lastSuccessfulRefresh {
			let howLongAgo = NSDate().timeIntervalSinceDate(l)
			if howLongAgo > NSTimeInterval(Settings.refreshPeriod) {
				startRefresh()
			} else {
				let howLongUntilNextSync = NSTimeInterval(Settings.refreshPeriod) - howLongAgo
				DLog("No need to refresh yet, will refresh in %f", howLongUntilNextSync)
				refreshTimer = NSTimer.scheduledTimerWithTimeInterval(howLongUntilNextSync, target: self, selector: Selector("refreshTimerDone"), userInfo: nil, repeats: false)
			}
		} else {
			startRefresh()
		}
	}

	func refreshMainList() {
		DataManager.postProcessAllPrs()
		let m = ((window.rootViewController as UISplitViewController).viewControllers.first as UINavigationController).viewControllers.first as MasterViewController
		m.reloadDataWithAnimation(true)
	}

	func application(application: UIApplication, performFetchWithCompletionHandler completionHandler: (UIBackgroundFetchResult) -> Void) {
		backgroundCallback = completionHandler
		startRefresh()
	}

	private func checkApiUsage() {
		for apiServer in ApiServer.allApiServersInMoc(mainObjectContext) {
			if apiServer.goodToGo() && (apiServer.requestsLimit?.doubleValue ?? 0) > 0 {
				if (apiServer.requestsRemaining?.doubleValue ?? 0) == 0 {
					UIAlertView(title: (apiServer.label ?? "Untitled Server's") + " API request usage is over the limit!",
						message: "Your request cannot be completed until GitHub resets your hourly API allowance at \(apiServer.resetDate).\n\nIf you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.\n\nYou can check your API usage at any time from the bottom of the preferences pane at any time.",
						delegate: nil,
						cancelButtonTitle: "OK").show()
					return
				} else if ((apiServer.requestsRemaining?.doubleValue ?? 0.0) / (apiServer.requestsLimit?.doubleValue ?? 1.0)) < LOW_API_WARNING {
					UIAlertView(title: (apiServer.label ?? "Untitled Server's") + " API request usage is close to full",
						message: "Try to make fewer manual refreshes, increasing the automatic refresh time, or reducing the number of repos you are monitoring.\n\nYour allowance will be reset by Github on \(apiServer.resetDate).\n\nYou can check your API usage from the bottom of the preferences pane.",
						delegate: nil,
						cancelButtonTitle: "OK").show()
				}
			}
		}
	}

	private func prepareForRefresh() {
		refreshTimer?.invalidate()
		refreshTimer = nil;

		isRefreshing = true

		backgroundTask = UIApplication.sharedApplication().beginBackgroundTaskWithName("com.housetrip.Trailer.refresh", expirationHandler: {
			self.endBGTask()
		})

		NSNotificationCenter.defaultCenter().postNotificationName(REFRESH_STARTED_NOTIFICATION, object: nil)
		DLog("Starting refresh")

		api.expireOldImageCacheEntries()
		DataManager.postMigrationTasks()
	}

	func startRefresh() -> Bool {
		if isRefreshing || api.reachability.currentReachabilityStatus()==NetworkStatus.NotReachable || !ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
			return false
		}

		prepareForRefresh()

		api.fetchPullRequestsForActiveReposAndCallback {

			let success = !ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext)

			self.lastUpdateFailed = !success

			if success {
				self.lastSuccessfulRefresh = NSDate()
				self.preferencesDirty = false
			}

			self.checkApiUsage()
			self.isRefreshing = false
			NSNotificationCenter.defaultCenter().postNotificationName(REFRESH_ENDED_NOTIFICATION, object: nil)
			DataManager.saveDB()
			DataManager.sendNotifications()

			if let bc = self.backgroundCallback {
				if success && mainObjectContext.hasChanges {
					DLog("Background fetch: Got new data")
					bc(UIBackgroundFetchResult.NewData)
				} else if success {
					DLog("Background fetch: No new data")
					bc(UIBackgroundFetchResult.NoData);
				} else {
					DLog("Background fetch: FAILED")
					bc(UIBackgroundFetchResult.Failed);
				}
				self.backgroundCallback = nil
			}

			if !success && UIApplication.sharedApplication().applicationState==UIApplicationState.Active {
				UIAlertView(title: "Refresh failed", message: "Loading the latest data from Github failed", delegate: nil, cancelButtonTitle: "OK").show()
			}

			self.refreshTimer = NSTimer.scheduledTimerWithTimeInterval(NSTimeInterval(Settings.refreshPeriod), target: self, selector: Selector("refreshTimerDone"), userInfo: nil, repeats:false)
			DLog("Refresh done")

			self.endBGTask()
		}

		return true
	}

	private func endBGTask() {
		if self.backgroundTask != UIBackgroundTaskInvalid {
			UIApplication.sharedApplication().endBackgroundTask(self.backgroundTask)
			self.backgroundTask = UIBackgroundTaskInvalid
		}
	}

	func refreshTimerDone() {
		if ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) && Repo.countVisibleReposInMoc(mainObjectContext) > 0 {
			startRefresh()
		}
	}

	func applicationDidBecomeActive(application: UIApplication) {
		enteringForeground = false
		startRefreshIfItIsDue()
	}


	func postNotificationOfType(type: PRNotificationType, forItem: DataItem) {
		if preferencesDirty {
			return
		}

		let notification = UILocalNotification()
		notification.userInfo = DataManager.infoForType(type, item: forItem)

		switch (type)
		{
		case .NewMention:
			if let c = forItem as? PRComment {
				let name = c.userName ?? "(unnamed)"
				let title = c.pullRequest.title ?? "(untitled)"
				let body = c.body ?? "(no description)"
				notification.alertBody = "@\(name) mentioned you in '\(title)': \(body)"
			}
		case .NewComment:
			if let c = forItem as? PRComment {
				let name = c.userName ?? "(unnamed)"
				let title = c.pullRequest.title ?? "(untitled)"
				let body = c.body ?? "(no description)"
				notification.alertBody = "@\(name) commented on '\(title)': \(body)"
			}
		case .NewPr:
			if let p = forItem as? PullRequest {
				notification.alertBody = "New PR: " + (p.title ?? "(untitled)")
			}
		case .PrReopened:
			if let p = forItem as? PullRequest {
				notification.alertBody = "Re-Opened PR: " + (p.title ?? "(untitled)")
			}
		case .PrMerged:
			if let p = forItem as? PullRequest {
				notification.alertBody = "PR Merged! " + (p.title ?? "(untitled)")
			}
		case .PrClosed:
			if let p = forItem as? PullRequest {
				notification.alertBody = "PR Closed: " + (p.title ?? "(untitled)")
			}
		case .NewRepoSubscribed:
			if let r = forItem as? Repo {
				notification.alertBody = "New Repository Subscribed: " + (r.fullName ?? "(untitled)")
			}
		case .NewRepoAnnouncement:
			if let r = forItem as? Repo {
				notification.alertBody = "New Repository: " + (r.fullName ?? "(untitled)")
			}
		case .NewPrAssigned:
			if let p = forItem as? PullRequest {
				notification.alertBody = "PR Assigned: " + (p.title ?? "(untitled)")
			}
		}

		// Present notifications only if the user isn't currenty reading notifications in the notification center, over the open app, a corner case
		// Otherwise the app will end up consuming them
		if enteringForeground {
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), {

				while UIApplication.sharedApplication().applicationState==UIApplicationState.Inactive {
					NSThread.sleepForTimeInterval(1.0)
				}
				dispatch_sync(dispatch_get_main_queue(), {
					UIApplication.sharedApplication().presentLocalNotificationNow(notification)
				})
			})
		} else {
			UIApplication.sharedApplication().presentLocalNotificationNow(notification)
		}
	}

	/////////////// sharing

	func shareFromView(view: UIViewController, buttonItem: UIBarButtonItem, url: NSURL) {
		let a = OpenInSafariActivity()
		let v = UIActivityViewController(activityItems: [url], applicationActivities:[a])

		if UIDevice.currentDevice().userInterfaceIdiom == UIUserInterfaceIdiom.Pad {
			sharePopover = UIPopoverController(contentViewController: v)
			sharePopover!.delegate = self
			sharePopover!.presentPopoverFromBarButtonItem(buttonItem, permittedArrowDirections: UIPopoverArrowDirection.Any, animated: true)
		} else {
			view.presentViewController(v, animated: true, completion: nil)
		}
	}

	func popoverControllerDidDismissPopover(popoverController: UIPopoverController) {
		sharePopover = nil
	}

}

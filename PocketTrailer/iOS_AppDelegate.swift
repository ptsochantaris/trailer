
import UIKit

var app: iOS_AppDelegate!

final class iOS_AppDelegate: UIResponder, UIApplicationDelegate {

	var preferencesDirty: Bool = false
	var isRefreshing: Bool = false
	var lastUpdateFailed: Bool = false
	var enteringForeground: Bool = true
	var lastRepoCheck = never()
	var window: UIWindow?
	var backgroundTask = UIBackgroundTaskInvalid
	var watchManager: WatchManager?

	var refreshTimer: NSTimer?
	var backgroundCallback: ((UIBackgroundFetchResult) -> Void)?

	func updateBadge() {
		UIApplication.sharedApplication().applicationIconBadgeNumber = PullRequest.badgeCountInMoc(mainObjectContext) + Issue.badgeCountInMoc(mainObjectContext)
		watchManager?.updateContext()
	}

	func application(application: UIApplication, willFinishLaunchingWithOptions launchOptions: [NSObject : AnyObject]?) -> Bool {
		app = self
		return true
	}

	func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject : AnyObject]?) -> Bool {

		DataManager.postProcessAllItems()

		if ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
			api.updateLimitsFromServer()
		}

		UITabBar.appearance().tintColor = GLOBAL_TINT
		UIBarButtonItem.appearance().tintColor = GLOBAL_TINT

		let splitViewController = window!.rootViewController as! UISplitViewController
		splitViewController.minimumPrimaryColumnWidth = 320
		splitViewController.maximumPrimaryColumnWidth = 320
		splitViewController.delegate = popupManager

		let m = popupManager.getMasterController()
		m.clearsSelectionOnViewWillAppear = false // for iPad

		UIApplication.sharedApplication().setMinimumBackgroundFetchInterval(NSTimeInterval(Settings.backgroundRefreshPeriod))

		atNextEvent { [weak self] in
			if Repo.visibleReposInMoc(mainObjectContext).count > 0 && ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
				if let localNotification = launchOptions?[UIApplicationLaunchOptionsLocalNotificationKey] as? UILocalNotification {
					NotificationManager.handleLocalNotification(localNotification, action: nil)
				}
			} else {

				if !ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
					if ApiServer.countApiServersInMoc(mainObjectContext) == 1, let a = ApiServer.allApiServersInMoc(mainObjectContext).first where a.authToken == nil || a.authToken!.isEmpty {
						m.performSegueWithIdentifier("showQuickstart", sender: self)
					} else {
						m.performSegueWithIdentifier("showPreferences", sender: self)
					}
				}
			}

			self?.watchManager = WatchManager()
		}

		let readAction = UIMutableUserNotificationAction()
		readAction.identifier = "read"
		readAction.title = "Mark as read"
		readAction.destructive = false
		readAction.authenticationRequired = false
		readAction.activationMode = .Background

		let readShort = UIMutableUserNotificationAction()
		readShort.identifier = "read"
		readShort.title = "Read"
		readShort.destructive = false
		readShort.authenticationRequired = false
		readShort.activationMode = .Background

		let muteAction = UIMutableUserNotificationAction()
		muteAction.identifier = "mute"
		muteAction.title = "Mute this item"
		muteAction.destructive = true
		muteAction.authenticationRequired = false
		muteAction.activationMode = .Background

		let muteShort = UIMutableUserNotificationAction()
		muteShort.identifier = "mute"
		muteShort.title = "Mute"
		muteShort.destructive = true
		muteShort.authenticationRequired = false
		muteShort.activationMode = .Background

		let itemCategory = UIMutableUserNotificationCategory()
		itemCategory.identifier = "mutable"
		itemCategory.setActions([readAction, muteAction], forContext: .Default)
		itemCategory.setActions([readShort, muteShort], forContext: .Minimal)

		let notificationSettings = UIUserNotificationSettings(forTypes: UIUserNotificationType.Alert.union(UIUserNotificationType.Badge).union(UIUserNotificationType.Sound), categories: [itemCategory])
		UIApplication.sharedApplication().registerUserNotificationSettings(notificationSettings)
		return true
	}

	func application(application: UIApplication, performActionForShortcutItem shortcutItem: UIApplicationShortcutItem, completionHandler: (Bool) -> Void) {

		switch shortcutItem.type {

		case "view-prs":
			let m = popupManager.getMasterController()
			m.showPullRequestsSelected(self)
			m.focusFilter()
			completionHandler(true)

		case "view-issues":
			let m = popupManager.getMasterController()
			m.showIssuesSelected(self)
			m.focusFilter()
			completionHandler(true)

		case "mark-all-read":
			markEverythingRead()
			completionHandler(true)

		default:
			completionHandler(false)
		}
	}

	func application(application: UIApplication, openURL url: NSURL, sourceApplication: String?, annotation: AnyObject) -> Bool {
		if let c = NSURLComponents(URL: url, resolvingAgainstBaseURL: false) {
			if let scheme = c.scheme {
				if scheme == "pockettrailer", let host = c.host {
					if host == "pullRequests" {
						NSOperationQueue.mainQueue().addOperationWithBlock {
							let m = popupManager.getMasterController()
							m.showPullRequestsSelected(self)
						}
						return true
					} else if host == "issues" {
						NSOperationQueue.mainQueue().addOperationWithBlock {
							let m = popupManager.getMasterController()
							m.showIssuesSelected(self)
						}
						return true
					}
				} else {
					settingsManager.loadSettingsFrom(url, confirmFromView: nil, withCompletion: nil)
				}
			}
		}
		return false
	}

	func application(application: UIApplication, continueUserActivity userActivity: NSUserActivity, restorationHandler: ([AnyObject]?) -> Void) -> Bool {
		return NotificationManager.handleUserActivity(userActivity)
	}

	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}

	func applicationWillResignActive(application: UIApplication) {
		enteringForeground = true
	}

	func application(application: UIApplication, didReceiveLocalNotification notification: UILocalNotification) {
		if enteringForeground {
			NotificationManager.handleLocalNotification(notification, action: nil)
		}
	}

	func application(application: UIApplication, handleActionWithIdentifier identifier: String?, forLocalNotification notification: UILocalNotification, completionHandler: () -> Void) {
		dispatch_async(dispatch_get_main_queue()) {
			NotificationManager.handleLocalNotification(notification, action: identifier)
			completionHandler()
		}
	}

	func startRefreshIfItIsDue() {

		refreshTimer?.invalidate()
		refreshTimer = nil

		if let l = Settings.lastSuccessfulRefresh {
			let howLongAgo = NSDate().timeIntervalSinceDate(l)
			if fabs(howLongAgo) > NSTimeInterval(Settings.refreshPeriod) {
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

	func application(application: UIApplication, performFetchWithCompletionHandler completionHandler: (UIBackgroundFetchResult) -> Void) {
		backgroundCallback = completionHandler
		startRefresh()
	}

	private func checkApiUsage() {
		for apiServer in ApiServer.allApiServersInMoc(mainObjectContext) {
			if apiServer.goodToGo && (apiServer.requestsLimit?.doubleValue ?? 0) > 0 {
				if (apiServer.requestsRemaining?.doubleValue ?? 0) == 0 {
					showMessage((apiServer.label ?? "Untitled Server's") + " API request usage is over the limit!",
						"Your request cannot be completed until GitHub resets your hourly API allowance at \(apiServer.resetDate).\n\nIf you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.\n\nYou can check your API usage at any time from the bottom of the preferences pane at any time.")
					return
				} else if ((apiServer.requestsRemaining?.doubleValue ?? 0.0) / (apiServer.requestsLimit?.doubleValue ?? 1.0)) < LOW_API_WARNING {
					showMessage((apiServer.label ?? "Untitled Server's") + " API request usage is close to full",
						"Try to make fewer manual refreshes, increasing the automatic refresh time, or reducing the number of repos you are monitoring.\n\nYour allowance will be reset by Github on \(apiServer.resetDate).\n\nYou can check your API usage from the bottom of the preferences pane.")
				}
			}
		}
	}

	private func prepareForRefresh() {
		refreshTimer?.invalidate()
		refreshTimer = nil

		isRefreshing = true

		backgroundTask = UIApplication.sharedApplication().beginBackgroundTaskWithName("com.housetrip.Trailer.refresh") { [weak self] in
			self?.endBGTask()
		}

		NSNotificationCenter.defaultCenter().postNotificationName(REFRESH_STARTED_NOTIFICATION, object: nil)
		DLog("Starting refresh")

		api.expireOldImageCacheEntries()
		DataManager.postMigrationTasks()
	}

	func startRefresh() -> Bool {

		if isRefreshing || api.noNetworkConnection() || !ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
			return false
		}

		prepareForRefresh()

		api.syncItemsForActiveReposAndCallback { [weak self] in

			if let s = self {
				let success = !ApiServer.shouldReportRefreshFailureInMoc(mainObjectContext)

				s.lastUpdateFailed = !success

				if success {
					Settings.lastSuccessfulRefresh = NSDate()
					s.preferencesDirty = false
				}

				s.checkApiUsage()
				s.isRefreshing = false
				NSNotificationCenter.defaultCenter().postNotificationName(REFRESH_ENDED_NOTIFICATION, object: nil)
				DataManager.saveDB() // Ensure object IDs are permanent before sending notifications
				DataManager.sendNotificationsIndexAndSave()

				if let bc = s.backgroundCallback {
					if success && mainObjectContext.hasChanges {
						DLog("Background fetch: Got new data")
						bc(UIBackgroundFetchResult.NewData)
					} else if success {
						DLog("Background fetch: No new data")
						bc(UIBackgroundFetchResult.NoData)
					} else {
						DLog("Background fetch: FAILED")
						bc(UIBackgroundFetchResult.Failed)
					}
					s.backgroundCallback = nil
				}

				if !success && UIApplication.sharedApplication().applicationState==UIApplicationState.Active {
					showMessage("Refresh failed", "Loading the latest data from Github failed")
				}

				s.refreshTimer = NSTimer.scheduledTimerWithTimeInterval(NSTimeInterval(Settings.refreshPeriod), target: s, selector: Selector("refreshTimerDone"), userInfo: nil, repeats:false)
				DLog("Refresh done")

				s.updateBadge()
				s.endBGTask()
			}
		}

		return true
	}

	private func endBGTask() {
		if backgroundTask != UIBackgroundTaskInvalid {
			UIApplication.sharedApplication().endBackgroundTask(backgroundTask)
			backgroundTask = UIBackgroundTaskInvalid
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

	func setMinimumBackgroundFetchInterval(interval: NSTimeInterval) -> Void {
		UIApplication.sharedApplication().setMinimumBackgroundFetchInterval(NSTimeInterval(interval))
	}

	func postNotificationOfType(type: PRNotificationType, forItem: DataItem) {
		NotificationManager.postNotificationOfType(type, forItem: forItem)
	}

	func markEverythingRead() {
		PullRequest.markEverythingRead(PullRequestSection.None, moc: mainObjectContext)
		Issue.markEverythingRead(PullRequestSection.None, moc: mainObjectContext)
		popupManager.getMasterController().reloadDataWithAnimation(false)
		DataManager.saveDB()
		app.updateBadge()
	}

	func clearAllClosed() {
		for p in PullRequest.allClosedRequestsInMoc(mainObjectContext) {
			mainObjectContext.deleteObject(p)
		}
		for i in Issue.allClosedIssuesInMoc(mainObjectContext) {
			mainObjectContext.deleteObject(i)
		}
		DataManager.saveDB()
		let m = popupManager.getMasterController()
		m.reloadDataWithAnimation(false)
		m.updateStatus()
	}

	func clearAllMerged() {
		for p in PullRequest.allMergedRequestsInMoc(mainObjectContext) {
			mainObjectContext.deleteObject(p)
		}
		DataManager.saveDB()
		let m = popupManager.getMasterController()
		m.reloadDataWithAnimation(false)
		m.updateStatus()
	}

	func markItemAsRead(itemUri: String?, reloadView: Bool) {
		if let
			i = itemUri,
			oid = DataManager.idForUriPath(i),
			o = existingObjectWithID(oid) as? ListableItem {
				o.catchUpWithComments()
				if reloadView {
					popupManager.getMasterController().reloadDataWithAnimation(false)
				}
				DataManager.saveDB()
				app.updateBadge()
		}
	}

	func markItemAsUnRead(itemUri: String?, reloadView: Bool) {
		if let
			i = itemUri,
			oid = DataManager.idForUriPath(i),
			o = existingObjectWithID(oid) as? ListableItem {
				o.latestReadCommentDate = never()
				o.postProcess()
				if reloadView {
					popupManager.getMasterController().reloadDataWithAnimation(false)
				}
				DataManager.saveDB()
				app.updateBadge()
		}
	}
}


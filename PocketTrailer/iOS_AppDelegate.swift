
import UIKit
import UserNotifications

var app: iOS_AppDelegate!

final class iOS_AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

	var window: UIWindow?

	private var lastUpdateFailed = false
	private var backgroundTask = UIBackgroundTaskInvalid
	private var watchManager: WatchManager?
	private var refreshTimer: Timer?
	private var backgroundCallback: ((UIBackgroundFetchResult) -> Void)?
	private var actOnLocalNotification = true

	func updateBadge() {
		UIApplication.shared.applicationIconBadgeNumber = PullRequest.badgeCount(in: mainObjectContext) + Issue.badgeCount(in: mainObjectContext)
		watchManager?.updateContext()
	}

	func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [NSObject : AnyObject]?) -> Bool {

		if mainObjectContext.persistentStoreCoordinator == nil {
			DLog("Database was corrupted on startup, removing DB files and resetting")
			DataManager.removeDatabaseFiles()
			abort()
		}

		app = self
		return true
	}

	func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: (UNNotificationPresentationOptions) -> Void) {
		completionHandler([.alert, .badge, .sound])
	}

	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: () -> Void) {
		NotificationManager.handleLocalNotification(notification: response.notification.request.content, action: response.actionIdentifier)
		completionHandler()
	}

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject : AnyObject]?) -> Bool {

		DataManager.postProcessAllItems()

		if ApiServer.someServersHaveAuthTokens(in: mainObjectContext) {
			api.updateLimitsFromServer()
		}

		UITabBar.appearance().tintColor = GLOBAL_TINT
		UIBarButtonItem.appearance().tintColor = GLOBAL_TINT

		let splitViewController = window!.rootViewController as! UISplitViewController
		splitViewController.minimumPrimaryColumnWidth = 320
		splitViewController.maximumPrimaryColumnWidth = 320
		splitViewController.delegate = popupManager

		application.setMinimumBackgroundFetchInterval(TimeInterval(Settings.backgroundRefreshPeriod))

		NotificationManager.setup(delegate: self)

		atNextEvent(self) { S in
			if !ApiServer.someServersHaveAuthTokens(in: mainObjectContext) {
				let m = popupManager.masterController
				if ApiServer.countApiServers(in: mainObjectContext) == 1, let a = ApiServer.allApiServers(in: mainObjectContext).first, a.authToken == nil || a.authToken!.isEmpty {
					m.performSegue(withIdentifier: "showQuickstart", sender: self)
				} else {
					m.performSegue(withIdentifier: "showPreferences", sender: self)
				}
			}

			S.watchManager = WatchManager()
		}

		return true
	}

	func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: (Bool) -> Void) {

		switch shortcutItem.type {

		case "search-items":
			let m = popupManager.masterController
			m.focusFilter()
			completionHandler(true)

		case "mark-all-read":
			markEverythingRead()
			completionHandler(true)

		default:
			completionHandler(false)
		}
	}

	func application(_ application: UIApplication, open url: URL, sourceApplication: String?, annotation: AnyObject) -> Bool {
		if let c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
			if let scheme = c.scheme {
				if scheme == "pockettrailer" {
					return true
				} else {
					settingsManager.loadSettingsFrom(url: url, confirmFromView: nil, withCompletion: nil)
				}
			}
		}
		return false
	}

	func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: ([AnyObject]?) -> Void) -> Bool {
		return NotificationManager.handleUserActivity(activity: userActivity)
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	func startRefreshIfItIsDue() {

		refreshTimer?.invalidate()
		refreshTimer = nil

		if let l = Settings.lastSuccessfulRefresh {
			let howLongAgo = Date().timeIntervalSince(l)
			if fabs(howLongAgo) > TimeInterval(Settings.refreshPeriod) {
				_ = startRefresh()
			} else {
				let howLongUntilNextSync = TimeInterval(Settings.refreshPeriod) - howLongAgo
				DLog("No need to refresh yet, will refresh in %f", howLongUntilNextSync)
				refreshTimer = Timer.scheduledTimer(timeInterval: howLongUntilNextSync, target: self, selector: #selector(refreshTimerDone), userInfo: nil, repeats: false)
			}
		} else {
			_ = startRefresh()
		}
	}

	func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: (UIBackgroundFetchResult) -> Void) {
		backgroundCallback = completionHandler
		_ = startRefresh()
	}

	private func checkApiUsage() {
		for apiServer in ApiServer.allApiServers(in: mainObjectContext) {
			if apiServer.goodToGo && apiServer.hasApiLimit, let resetDate = apiServer.resetDate {
				if apiServer.shouldReportOverTheApiLimit {
					let apiLabel = S(apiServer.label)
					let resetDateString = itemDateFormatter.string(from: resetDate)

					showMessage("\(apiLabel) API request usage is over the limit!",
						"Your request cannot be completed until GitHub resets your hourly API allowance at \(resetDateString).\n\nIf you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.\n\nYou can check your API usage at any time from the bottom of the preferences pane at any time.")
				} else if apiServer.shouldReportCloseToApiLimit {
					let apiLabel = S(apiServer.label)
					let resetDateString = itemDateFormatter.string(from: resetDate)

					showMessage("\(apiLabel) API request usage is close to full",
						"Try to make fewer manual refreshes, increasing the automatic refresh time, or reducing the number of repos you are monitoring.\n\nYour allowance will be reset by GitHub on \(resetDateString).\n\nYou can check your API usage from the bottom of the preferences pane.")
				}
			}
		}
	}

	private func prepareForRefresh() {
		refreshTimer?.invalidate()
		refreshTimer = nil

		appIsRefreshing = true

		backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "com.housetrip.Trailer.refresh") { [weak self] in
			self?.endBGTask()
		}

		NotificationCenter.default.post(name: RefreshStartedNotification, object: nil)
		DLog("Starting refresh")

		DataManager.postMigrationTasks()
	}

	func startRefresh() -> Bool {

		if appIsRefreshing || !api.hasNetworkConnection || !ApiServer.someServersHaveAuthTokens(in: mainObjectContext) {
			return false
		}

		prepareForRefresh()

		api.syncItemsForActiveReposAndCallback({

			popupManager.masterController.title = "Processing..."

		}) { [weak self] in

			guard let s = self else { return }

			let success = !ApiServer.shouldReportRefreshFailure(in: mainObjectContext)

			s.lastUpdateFailed = !success

			if success {
				Settings.lastSuccessfulRefresh = Date()
				preferencesDirty = false
			}

			s.checkApiUsage()
			appIsRefreshing = false
			NotificationCenter.default.post(name: RefreshEndedNotification, object: nil)
			DataManager.saveDB() // Ensure object IDs are permanent before sending notifications
			DataManager.sendNotificationsIndexAndSave()

			if !success && UIApplication.shared.applicationState == .active {
				showMessage("Refresh failed", "Loading the latest data from GitHub failed")
			}

			s.refreshTimer = Timer.scheduledTimer(timeInterval: TimeInterval(Settings.refreshPeriod), target: s, selector: #selector(s.refreshTimerDone), userInfo: nil, repeats: false)
			DLog("Refresh done")

			s.updateBadge()
			s.endBGTask()

			if let bc = s.backgroundCallback {
				if success && mainObjectContext.hasChanges {
					DLog("Background fetch: Got new data")
					bc(.newData)
				} else if success {
					DLog("Background fetch: No new data")
					bc(.noData)
				} else {
					DLog("Background fetch: FAILED")
					bc(.failed)
				}
				s.backgroundCallback = nil
			}
		}

		return true
	}

	private func endBGTask() {
		if backgroundTask != UIBackgroundTaskInvalid {
			UIApplication.shared.endBackgroundTask(backgroundTask)
			backgroundTask = UIBackgroundTaskInvalid
		}
	}

	func refreshTimerDone() {
		if DataManager.appIsConfigured {
			_ =
				startRefresh()
		}
	}

	func applicationDidBecomeActive(_ application: UIApplication) {
		startRefreshIfItIsDue()
		actOnLocalNotification = false
	}

	func applicationWillEnterForeground(_ application: UIApplication) {
		actOnLocalNotification = true
	}

	func applicationDidEnterBackground(_ application: UIApplication) {
		actOnLocalNotification = false
	}

	func applicationWillResignActive(_ application: UIApplication) {
		actOnLocalNotification = true
	}

	func postNotification(type: NotificationType, for item: DataItem) {
		NotificationManager.postNotification(type: type, for: item)
	}

	func markEverythingRead() {
		PullRequest.markEverythingRead(in: .none, in: mainObjectContext)
		Issue.markEverythingRead(in: .none, in: mainObjectContext)
		DataManager.saveDB()
		app.updateBadge()
	}

	func clearAllClosed() {
		for p in PullRequest.allClosed(in: mainObjectContext, includeAllGroups: true) {
			mainObjectContext.delete(p)
		}
		for i in Issue.allClosed(in: mainObjectContext, includeAllGroups: true) {
			mainObjectContext.delete(i)
		}
		DataManager.saveDB()
		popupManager.masterController.updateStatus()
	}

	func clearAllMerged() {
		for p in PullRequest.allMerged(in: mainObjectContext, includeAllGroups: true) {
			mainObjectContext.delete(p)
		}
		DataManager.saveDB()
		popupManager.masterController.updateStatus()
	}
}

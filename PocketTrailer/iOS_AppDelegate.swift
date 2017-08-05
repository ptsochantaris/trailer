
import UIKit
import UserNotifications

@UIApplicationMain
final class iOS_AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

	var window: UIWindow?

	private var lastUpdateFailed = false
	private var backgroundTask = UIBackgroundTaskInvalid
	private var watchManager: WatchManager?
	private var refreshTimer: Timer?
	private var backgroundCallback: ((UIBackgroundFetchResult) -> Void)?
	private var actOnLocalNotification = true

	func updateBadgeAndSaveDB() {
		watchManager?.updateContext()
	}

	func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]? = nil) -> Bool {

		app = self
		bootUp()

		if DataManager.main.persistentStoreCoordinator == nil {
			DLog("Database was corrupted on startup, removing DB files and resetting")
			DataManager.removeDatabaseFiles()
			abort()
		}

		return true
	}

	func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		completionHandler([.alert, .badge, .sound])
	}

	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		NotificationManager.handleLocalNotification(notification: response.notification.request.content, action: response.actionIdentifier)
		completionHandler()
	}

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]? = nil) -> Bool {

		DataManager.postProcessAllItems()

		if ApiServer.someServersHaveAuthTokens(in: DataManager.main) {
			API.updateLimitsFromServer()
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
			if !ApiServer.someServersHaveAuthTokens(in: DataManager.main) {
				let m = popupManager.masterController
				if ApiServer.countApiServers(in: DataManager.main) == 1, let a = ApiServer.allApiServers(in: DataManager.main).first, a.authToken == nil || a.authToken!.isEmpty {
					m.performSegue(withIdentifier: "showQuickstart", sender: self)
				} else {
					m.performSegue(withIdentifier: "showPreferences", sender: self)
				}
			}

			S.watchManager = WatchManager()
		}

		return true
	}

	func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {

		switch shortcutItem.type {

		case "search-items":
			let m = popupManager.masterController
			m.focusFilter(terms: nil)
			completionHandler(true)

		case "mark-all-read":
			markEverythingRead()
			completionHandler(true)

		default:
			completionHandler(false)
		}
	}

	func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
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

	func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]?) -> Void) -> Bool {
		return NotificationManager.handleUserActivity(activity: userActivity)
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	func startRefreshIfItIsDue() {

		refreshTimer = nil

		if let l = Settings.lastSuccessfulRefresh {
			let howLongAgo = Date().timeIntervalSince(l)
			if fabs(howLongAgo) > TimeInterval(Settings.refreshPeriod) {
				startRefresh()
			} else {
				let howLongUntilNextSync = TimeInterval(Settings.refreshPeriod) - howLongAgo
				DLog("No need to refresh yet, will refresh in %@", howLongUntilNextSync)
				refreshTimer = Timer(repeats: false, interval: howLongUntilNextSync) { [weak self] in
					self?.refreshTimerDone()
				}
			}
		} else {
			startRefresh()
		}
	}

	func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
		backgroundCallback = completionHandler
		startRefresh()
	}

	private func checkApiUsage() {
		for apiServer in ApiServer.allApiServers(in: DataManager.main) {
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
						"Try to make fewer manual refreshes, increasing the automatic refresh time, or reducing the number of repos you are monitoring.\n\nYour allowance will be reset by GitHub \(resetDateString).\n\nYou can check your API usage from the bottom of the preferences pane.")
				}
			}
		}
	}

	private func prepareForRefresh() {
		refreshTimer = nil

		DataManager.postMigrationTasks()

		appIsRefreshing = true

		backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "com.housetrip.Trailer.refresh") { [weak self] in
			self?.endBGTask()
		}

		NotificationCenter.default.post(name: RefreshStartedNotification, object: nil)

		NotificationQueue.clear()

		DLog("Starting refresh")
	}

	enum RefreshStartResult {
		case started, noNetwork, noConfiguredServers, alreadyRefreshing
	}

	@discardableResult
	func startRefresh() -> RefreshStartResult {

		if appIsRefreshing {
			return .alreadyRefreshing
		}

		if !API.hasNetworkConnection {
			return .noNetwork
		}

		if !ApiServer.someServersHaveAuthTokens(in: DataManager.main) {
			return .noConfiguredServers
		}

		prepareForRefresh()

		API.syncItemsForActiveReposAndCallback { [weak self] in
			self?.processRefresh()
		}

		return .started
	}

	private func processRefresh() {
		let success = !ApiServer.shouldReportRefreshFailure(in: DataManager.main)

		lastUpdateFailed = !success

		if success {
			Settings.lastSuccessfulRefresh = Date()
			preferencesDirty = false
		}

		checkApiUsage()
		appIsRefreshing = false
		DataManager.saveDB() // Ensure object IDs are permanent before sending notifications
		DataManager.sendNotificationsIndexAndSave()
		NotificationCenter.default.post(name: RefreshEndedNotification, object: nil)

		if !success && UIApplication.shared.applicationState == .active {
			showMessage("Refresh failed", "Loading the latest data from GitHub failed")
		}

		refreshTimer = Timer(repeats: false, interval: TimeInterval(Settings.refreshPeriod)) {
			self.refreshTimerDone()
		}
		DLog("Refresh done")

		endBGTask()

		if let bc = backgroundCallback {
			if success && DataManager.main.hasChanges {
				DLog("Background fetch: Got new data")
				bc(.newData)
			} else if success {
				DLog("Background fetch: No new data")
				bc(.noData)
			} else {
				DLog("Background fetch: FAILED")
				bc(.failed)
			}
			backgroundCallback = nil
		}
	}

	private func endBGTask() {
		if backgroundTask != UIBackgroundTaskInvalid {
			UIApplication.shared.endBackgroundTask(backgroundTask)
			backgroundTask = UIBackgroundTaskInvalid
		}
	}

	private func refreshTimerDone() {
		refreshTimer = nil
		if DataManager.appIsConfigured {
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

	func markEverythingRead() {
		PullRequest.markEverythingRead(in: .none, in: DataManager.main)
		Issue.markEverythingRead(in: .none, in: DataManager.main)
	}

	func clearAllClosed() {
		for p in PullRequest.allClosed(in: DataManager.main, includeAllGroups: true) {
			DataManager.main.delete(p)
		}
		for i in Issue.allClosed(in: DataManager.main, includeAllGroups: true) {
			DataManager.main.delete(i)
		}
	}

	func clearAllMerged() {
		for p in PullRequest.allMerged(in: DataManager.main, includeAllGroups: true) {
			DataManager.main.delete(p)
		}
	}
}

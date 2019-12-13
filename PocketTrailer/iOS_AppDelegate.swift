
import UIKit
import UserNotifications
import BackgroundTasks

@UIApplicationMain
final class iOS_AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

	var window: UIWindow?

	private var lastUpdateFailed = false
	private var watchManager: WatchManager?
    private var backgroundProcessing: BGProcessingTask?

	func updateBadgeAndSaveDB() {
		watchManager?.updateContext()
	}

	func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

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

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

		DataManager.postProcessAllItems()

		if ApiServer.someServersHaveAuthTokens(in: DataManager.main) {
			API.updateLimitsFromServer()
		}

        UIToolbar.appearance().tintColor = UIColor(named: "apptint")

        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.housetrip.mobile.trailer.ios.PocketTrailer.refresh", using: DispatchQueue.main) { task in
            guard let task = task as? BGProcessingTask, DataManager.appIsConfigured else {
                return
            }
            self.backgroundProcessing = task
            self.startRefresh()
        }

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
			popupManager.masterController.focusFilter(terms: nil)
			completionHandler(true)

		case "mark-all-read":
			markEverythingRead()
			completionHandler(true)

		default:
			completionHandler(false)
		}
	}

	func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
		guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), let scheme = c.scheme else {
			return false
		}

		if scheme == "pockettrailer" {
			var terms: String?
			if let items = c.queryItems, let index = items.firstIndex(where: { $0.name == "search" }) {
				terms = items[index].value
			}
			popupManager.masterController.focusFilter(terms: terms)
		} else {
			settingsManager.loadSettingsFrom(url: url, confirmFromView: nil, withCompletion: nil)
		}

		return true
	}

	func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
		return NotificationManager.handleUserActivity(activity: userActivity)
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	func startRefreshIfItIsDue() {

		if let l = Settings.lastSuccessfulRefresh {
			let howLongAgo = Date().timeIntervalSince(l)
            let period = TimeInterval(Settings.backgroundRefreshPeriod)
			if fabs(howLongAgo) > period {
				startRefresh()
			} else {
				let howLongUntilNextSync = period - howLongAgo
				DLog("No need to refresh yet, will refresh in %@", howLongUntilNextSync)
			}
		} else {
			startRefresh()
		}
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

	enum RefreshStartResult {
		case started, noNetwork, noConfiguredServers, alreadyRefreshing
	}
    
    private func wrapBackgroundProcessing(success: Bool) {
        scheduleRefreshTask()
        
        guard let bc = backgroundProcessing else {
            return
        }
        
        if success && DataManager.main.hasChanges {
            DLog("Background fetch: Got new data")
        } else if success {
            DLog("Background fetch: No new data")
        } else {
            DLog("Background fetch: FAILED")
        }
        bc.setTaskCompleted(success: success)
        
        backgroundProcessing = nil
    }
    
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    
    private func startBGTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "com.housetrip.Trailer.refresh") { [weak self] in
            self?.endBGTask()
        }
        DLog("BG task started")
    }
    
    private func endBGTask() {
        if backgroundTask == .invalid {
            return
        }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
        DLog("BG task ended")
    }

	@discardableResult
	func startRefresh() -> RefreshStartResult {

		if appIsRefreshing {
            wrapBackgroundProcessing(success: false)
			return .alreadyRefreshing
		}

		if !API.hasNetworkConnection {
            wrapBackgroundProcessing(success: false)
			return .noNetwork
		}

		if !ApiServer.someServersHaveAuthTokens(in: DataManager.main) {
            wrapBackgroundProcessing(success: false)
			return .noConfiguredServers
		}

        DataManager.postMigrationTasks()
        appIsRefreshing = true
        NotificationCenter.default.post(name: .RefreshStarted, object: nil)
        NotificationQueue.clear()
        DLog("Starting refresh")

        startBGTask()

		API.syncItemsForActiveReposAndCallback { [weak self] in
            guard let s = self else { return }
			s.processRefresh()
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
        NotificationCenter.default.post(name: .RefreshEnded, object: nil)

		if !success && UIApplication.shared.applicationState == .active {
			showMessage("Refresh failed", "Loading the latest data from GitHub failed")
		}

        wrapBackgroundProcessing(success: success)
		endBGTask()
        
        DLog("Refresh done")
	}

	func applicationDidBecomeActive(_ application: UIApplication) {
        BGTaskScheduler.shared.cancelAllTaskRequests()
		startRefreshIfItIsDue()
	}
    
    func applicationWillResignActive(_ application: UIApplication) {
        scheduleRefreshTask()
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
    
    // e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.housetrip.mobile.trailer.ios.PocketTrailer.refresh"]
    
    private func scheduleRefreshTask() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
        
        let request = BGProcessingTaskRequest(identifier: "com.housetrip.mobile.trailer.ios.PocketTrailer.refresh")
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        
        let period = Settings.backgroundRefreshPeriod
        if let lastRefresh = Settings.lastSuccessfulRefresh {
            request.earliestBeginDate = max(Date(timeIntervalSinceNow: 10), lastRefresh.addingTimeInterval(period))
        } else {
            request.earliestBeginDate = Date(timeIntervalSinceNow: period)
        }

        do {
            try BGTaskScheduler.shared.submit(request)
            DLog("Scheduled next refresh after \(request.earliestBeginDate!)")
        } catch {
            DLog("Could not schedule app refresh: \(error)")
        }
    }
}

import BackgroundTasks
import UIKit
import UserNotifications

@main
final class iOSAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    private var backgroundProcessing: BGProcessingTask?

    func application(_: UIApplication, willFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        app = self
        bootUp()

        if DataManager.main.persistentStoreCoordinator == nil {
            Logging.log("Database was corrupted on startup, removing DB files and resetting")
            DataManager.removeDatabaseFiles()
            abort()
        }

        return true
    }

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task {
            await DataManager.postProcessAllItems(in: DataManager.main)
        }

        if ApiServer.someServersHaveAuthTokens(in: DataManager.main) {
            Task {
                await API.updateLimitsFromServer()
            }
        }

        UIToolbar.appearance().tintColor = UIColor(named: "apptint")

        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.housetrip.mobile.trailer.ios.PocketTrailer.refresh", using: .main) { [weak self] task in
            guard let self, let task = task as? BGProcessingTask, DataManager.appIsConfigured else {
                return
            }
            backgroundProcessing = task
            Task {
                await self.startRefresh()
            }
        }

        NotificationManager.shared.setup()

        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(refreshStarting), name: .RefreshStarting, object: nil)
        n.addObserver(self, selector: #selector(refreshDone(_:)), name: .RefreshEnded, object: nil)

        return true
    }

    func application(_: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
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

    func application(_: UIApplication, open url: URL, options _: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
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
            Task {
                await settingsManager.loadSettingsFrom(url: url, confirmFromView: nil)
            }
        }

        return true
    }

    func application(_: UIApplication, continue userActivity: NSUserActivity, restorationHandler _: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        NotificationManager.shared.handleUserActivity(activity: userActivity)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func startRefreshIfItIsDue() async {
        if let l = Settings.lastSuccessfulRefresh {
            let howLongAgo = Date().timeIntervalSince(l).rounded()
            let howLongUntilNextSync = Settings.backgroundRefreshPeriod - howLongAgo
            if howLongUntilNextSync > 0 {
                Logging.log("No need to refresh yet, will refresh in \(howLongUntilNextSync) sec")
                return
            }
        }
        _ = await startRefresh()
    }

    private func checkApiUsage() {
        for apiServer in ApiServer.allApiServers(in: DataManager.main) {
            if apiServer.goodToGo, apiServer.hasApiLimit, let resetDate = apiServer.resetDate {
                if apiServer.shouldReportOverTheApiLimit {
                    let apiLabel = apiServer.label.orEmpty
                    let resetDateString = itemDateFormatter.string(from: resetDate)

                    showMessage("\(apiLabel) API request usage is over the limit!",
                                "Your request cannot be completed until GitHub resets your hourly API allowance at \(resetDateString).\n\nIf you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.\n\nYou can check your API usage at any time from the bottom of the preferences pane at any time.")
                } else if apiServer.shouldReportCloseToApiLimit {
                    let apiLabel = apiServer.label.orEmpty
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
        if success {
            Logging.log("Background fetch completed")
        } else {
            Logging.log("Background fetch FAILED")
        }
        scheduleRefreshTask()
        backgroundProcessing?.setTaskCompleted(success: success)
        backgroundProcessing = nil
    }

    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    @discardableResult
    @MainActor
    func startRefresh() async -> RefreshStartResult {
        let refreshing = API.isRefreshing
        if refreshing {
            wrapBackgroundProcessing(success: false)
            return .alreadyRefreshing
        }

        let hasConnection = API.hasNetworkConnection
        if !hasConnection {
            wrapBackgroundProcessing(success: false)
            return .noNetwork
        }

        let someHaveTokens = ApiServer.someServersHaveAuthTokens(in: DataManager.main)
        if !someHaveTokens {
            wrapBackgroundProcessing(success: false)
            return .noConfiguredServers
        }

        Task {
            await API.performSync()

            if Settings.V4IdMigrationPhase == .failedPending {
                showMessage("ID migration failed", "Trailer tried to automatically migrate your IDs during the most recent sync but it failed for some reason. Since GitHub servers require using a new set of IDs soon please visit Trailer Preferences -> Servers -> V4 API Settings and select the option to try migrating IDs again soon.")
                Settings.V4IdMigrationPhase = .failedAnnounced
            }
        }

        return .started
    }

    @objc private func refreshStarting() {
        popupManager.masterController.updateStatus(becauseOfChanges: false)
    }

    @objc private func refreshDone(_ notification: Notification) {
        checkApiUsage()

        let success = notification.object as? Bool ?? false
        if !success, UIApplication.shared.applicationState == .active {
            showMessage("Refresh failed", "Loading the latest data from GitHub failed")
        }

        wrapBackgroundProcessing(success: success)
    }

    func applicationDidBecomeActive(_: UIApplication) {
        BGTaskScheduler.shared.cancelAllTaskRequests()
        Task {
            await startRefreshIfItIsDue()
        }
    }

    func applicationWillResignActive(_: UIApplication) {
        scheduleRefreshTask()
    }

    func markEverythingRead() {
        PullRequest.markEverythingRead(in: .hidden, in: DataManager.main)
        Issue.markEverythingRead(in: .hidden, in: DataManager.main)
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
            Logging.log("Scheduled next refresh after \(request.earliestBeginDate!)")
        } catch {
            Logging.log("Could not schedule app refresh: \(error)")
        }
    }
}

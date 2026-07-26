import BackgroundTasks
import UIKit
import UserNotifications

@main
final class iOSAppDelegate: UIResponder, UIApplicationDelegate {
    private var backgroundProcessing: BGProcessingTask?

    // Scene configuration is provided here rather than through a `UIApplicationSceneManifest` in
    // Info.plist. Both routes are supported; doing it in code keeps the storyboard name and the
    // delegate class next to the delegate itself. UIKit builds the window and installs the
    // storyboard's initial view controller automatically, so `SceneDelegate` creates no UI.
    func application(_: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options _: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        configuration.storyboard = UIStoryboard(name: "Main", bundle: nil)
        return configuration
    }

    func application(_: UIApplication, willFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        app = self
        bootUp()

        if DataManager.main.persistentStoreCoordinator == nil {
            Task {
                await Logging.shared.log("Database was corrupted on startup, removing DB files and resetting")
            }
            DataManager.removeDatabaseFiles()
            abort()
        }

        return true
    }

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task {
            await DataManager.postProcessAllItems(in: DataManager.main, settings: Settings.cache)
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
        n.addObserver(self, selector: #selector(refreshDone(_:)), name: .RefreshEnded, object: nil)

        return true
    }

    // The three `handle` methods below used to be `UIApplicationDelegate` callbacks. Under the scene
    // life cycle UIKit delivers these to the scene delegate instead, so they are plain helpers now
    // and `SceneDelegate` forwards to them.
    @discardableResult
    func handle(shortcutItem: UIApplicationShortcutItem) -> Bool {
        switch shortcutItem.type {
        case "search-items":
            NotificationCenter.default.post(name: .focusFilter, object: nil)
            return true

        case "mark-all-read":
            markEverythingRead(settings: Settings.cache)
            return true

        default:
            return false
        }
    }

    @discardableResult
    func handle(url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), let scheme = c.scheme else {
            return false
        }

        if scheme == "pockettrailer" {
            var terms: String?
            if let items = c.queryItems, let index = items.firstIndex(where: { $0.name == "search" }) {
                terms = items[index].value
            }
            NotificationCenter.default.post(name: .focusFilter, object: terms)
        } else {
            Task {
                await settingsManager.loadSettingsFrom(url: url, confirmFromView: nil)
            }
        }

        return true
    }

    @discardableResult
    func handle(userActivity: NSUserActivity) -> Bool {
        NotificationManager.shared.handleUserActivity(activity: userActivity)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @MainActor
    func startRefreshIfItIsDue() async {
        if let l = Settings.lastSuccessfulRefresh {
            let howLongAgo = Date().timeIntervalSince(l).rounded()
            let howLongUntilNextSync = Settings.backgroundRefreshPeriod - howLongAgo
            if howLongUntilNextSync > 0 {
                await Logging.shared.log("No need to refresh yet, will refresh in \(howLongUntilNextSync) sec")
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
                    let resetDateString = Date.Formatters.itemDateFormat.format(resetDate)

                    showMessage("\(apiLabel) API request usage is over the limit!",
                                "Your request cannot be completed until GitHub resets your hourly API allowance at \(resetDateString).\n\nIf you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.\n\nYou can check your API usage at any time from the bottom of the preferences pane at any time.")
                } else if apiServer.shouldReportCloseToApiLimit {
                    let apiLabel = apiServer.label.orEmpty
                    let resetDateString = Date.Formatters.itemDateFormat.format(resetDate)

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
        Task {
            if success {
                await Logging.shared.log("Background fetch completed")
            } else {
                await Logging.shared.log("Background fetch FAILED")
            }
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
            await API.performSync(settings: Settings.cache)

            if Settings.V4IdMigrationPhase == .failedPending {
                showMessage("ID migration failed", "Trailer tried to automatically migrate your IDs during the most recent sync but it failed for some reason. Since GitHub servers require using a new set of IDs soon please visit Trailer Preferences -> Servers -> V4 API Settings and select the option to try migrating IDs again soon.")
                Settings.V4IdMigrationPhase = .failedAnnounced
            }
        }

        return .started
    }

    @objc private func refreshDone(_ notification: Notification) {
        checkApiUsage()

        let success = notification.object as? Bool ?? false
        if !success, UIApplication.shared.applicationState == .active {
            showMessage("Refresh failed", "Loading the latest data from GitHub failed")
        }

        wrapBackgroundProcessing(success: success)
    }

    // `applicationDidBecomeActive` and `applicationWillResignActive` used to live here. UIKit does
    // not call them once the scene life cycle is adopted, so they moved to `SceneDelegate` as
    // `sceneDidBecomeActive` / `sceneWillResignActive`. Leaving them here would look correct and
    // silently never run, taking foreground refresh and background scheduling with them.

    func markEverythingRead(settings: Settings.Cache) {
        PullRequest.markEverythingRead(in: .hidden(cause: .unknown), in: DataManager.main, settings: settings)
        Issue.markEverythingRead(in: .hidden(cause: .unknown), in: DataManager.main, settings: settings)
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

    func scheduleRefreshTask() {
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
            if let startDate = request.earliestBeginDate {
                Task {
                    await Logging.shared.log("Scheduled next refresh after \(startDate)")
                }
            }
        } catch {
            Task {
                await Logging.shared.log("Could not schedule app refresh: \(error)")
            }
        }
    }
}

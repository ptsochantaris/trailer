import BackgroundTasks
import UIKit

/// Receives the UI life-cycle events that `iOSAppDelegate` used to handle. UIKit stopped delivering
/// those to the app delegate when this app adopted the scene life cycle, which iOS 27 requires.
///
/// No UI is built here: `iOSAppDelegate.application(_:configurationForConnecting:options:)` hands
/// UIKit the `Main` storyboard, so the window and root view controller already exist by the time
/// this delegate is called.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    // A cold launch delivers its URL, shortcut or Handoff activity while the scene is connecting,
    // which is before the storyboard's view controllers are listening for the notifications these
    // handlers post. They are stashed here and replayed once the scene is active.
    private var pendingShortcutItem: UIApplicationShortcutItem?
    private var pendingURLs = [URL]()
    private var pendingUserActivities = [NSUserActivity]()

    func scene(_: UIScene, willConnectTo _: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        pendingShortcutItem = connectionOptions.shortcutItem
        pendingURLs = connectionOptions.urlContexts.map(\.url)
        pendingUserActivities = Array(connectionOptions.userActivities)
    }

    func sceneDidBecomeActive(_: UIScene) {
        replayPendingLaunchEvents()

        BGTaskScheduler.shared.cancelAllTaskRequests()
        Task {
            await app.startRefreshIfItIsDue()
        }
    }

    func sceneWillResignActive(_: UIScene) {
        app.scheduleRefreshTask()
    }

    func scene(_: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            app.handle(url: context.url)
        }
    }

    func scene(_: UIScene, continue userActivity: NSUserActivity) {
        app.handle(userActivity: userActivity)
    }

    func windowScene(_: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(app.handle(shortcutItem: shortcutItem))
    }

    private func replayPendingLaunchEvents() {
        if let pendingShortcutItem {
            self.pendingShortcutItem = nil
            app.handle(shortcutItem: pendingShortcutItem)
        }

        if !pendingURLs.isEmpty {
            let urls = pendingURLs
            pendingURLs.removeAll()
            for url in urls {
                app.handle(url: url)
            }
        }

        if !pendingUserActivities.isEmpty {
            let activities = pendingUserActivities
            pendingUserActivities.removeAll()
            for activity in activities {
                app.handle(userActivity: activity)
            }
        }
    }
}

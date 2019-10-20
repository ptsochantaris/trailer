import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    @objc private func terminate() {
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if LauncherCommon.isMainAppRunning {
            terminate()
        } else {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(terminate), name: .KillHelper, object: LauncherCommon.mainAppId)
            LauncherCommon.launchMainApp()
        }
    }
}

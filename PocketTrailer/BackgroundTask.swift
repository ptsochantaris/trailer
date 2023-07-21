import UIKit

@MainActor
enum BackgroundTask {
    private static var bgTask = UIBackgroundTaskIdentifier.invalid

    private static func endTask() {
        if bgTask == .invalid { return }
        Logging.log("BG Task done")
        endTimer.abort()
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }

    private static var globalBackgroundCount = 0
    private static var appInBackground = false

    private static let endTimer = PopTimer(timeInterval: 3) {
        endTask()
    }

    static func appBackgrounded() {
        appInBackground = true
        if globalBackgroundCount != 0, bgTask == .invalid {
            Logging.log("BG Task starting")
            bgTask = UIApplication.shared.beginBackgroundTask {
                endTask()
            }
        }
    }

    static func appForegrounded() {
        endTimer.abort()
        appInBackground = false
        endTask()
    }

    static func registerForBackground() {
        endTimer.abort()
        let count = globalBackgroundCount
        globalBackgroundCount = count + 1
        if appInBackground, bgTask == .invalid, count == 0 {
            appBackgrounded()
        }
    }

    static func unregisterForBackground() {
        globalBackgroundCount -= 1
        if globalBackgroundCount == 0, bgTask != .invalid {
            endTimer.push()
        }
    }
}

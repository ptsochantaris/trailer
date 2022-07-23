import UIKit

final class BackgroundTask {
    private static var bgTask = UIBackgroundTaskIdentifier.invalid

    private static func endTask() {
        if bgTask == .invalid { return }
        DLog("BG Task done")
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }

    private static var globalBackgroundCount = 0
    private static var appInBackground = false

    private static let endTimer = PopTimer(timeInterval: 3) {
        endTask()
    }

    @MainActor
    static func appBackgrounded() {
        appInBackground = true
        if globalBackgroundCount != 0, bgTask == .invalid {
            DLog("BG Task starting")
            bgTask = UIApplication.shared.beginBackgroundTask {
                endTask()
            }
        }
    }

    @MainActor
    static func appForegrounded() {
        endTimer.abort()
        appInBackground = false
        endTask()
    }

    @MainActor
    static func registerForBackground() {
        endTimer.abort()
        let count = globalBackgroundCount
        globalBackgroundCount = count + 1
        if appInBackground, bgTask == .invalid, count == 0 {
            appBackgrounded()
        }
    }

    @MainActor
    static func unregisterForBackground() {
        globalBackgroundCount -= 1
        if globalBackgroundCount == 0, bgTask != .invalid {
            endTimer.push()
        }
    }
}

import UIKit

final class BackgroundTask {

    private static var bgTask = UIBackgroundTaskIdentifier.invalid

    private static func end() {
        if bgTask == .invalid { return }
        DLog("BG Task done")
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }

    private static var globalBackgroundCount = 0

    private static let endTimer = PopTimer(timeInterval: 3) {
        end()
    }

    static func registerForBackground() {
        assert(Thread.isMainThread)
        if endTimer.isRunning {
            endTimer.abort()
        }
        if globalBackgroundCount == 0 && bgTask == .invalid {
            DLog("BG Task starting")
            bgTask = UIApplication.shared.beginBackgroundTask {
                end()
            }
        }
        globalBackgroundCount += 1
    }

    static func unregisterForBackground() {
        assert(Thread.isMainThread)
        globalBackgroundCount -= 1
        if globalBackgroundCount == 0 && bgTask != .invalid {
            endTimer.push()
        }
    }
}

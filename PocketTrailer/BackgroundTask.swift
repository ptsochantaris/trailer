import UIKit

final class BackgroundTask {

    private static var bgTask = UIBackgroundTaskIdentifier.invalid

    private static func endTask() {
        if bgTask == .invalid { return }
        log("BG Task done")
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }

    private static var globalBackgroundCount = 0
    private static var appInBackground = false

    private static let endTimer = PopTimer(timeInterval: 3) {
        endTask()
    }
    
    static func appBackgrounded() {
        assert(Thread.isMainThread)
        appInBackground = true
        if globalBackgroundCount != 0 && bgTask == .invalid {
            log("BG Task starting")
            bgTask = UIApplication.shared.beginBackgroundTask {
                endTask()
            }
        }
    }
    
    static func appForegrounded() {
        assert(Thread.isMainThread)
        endTimer.abort()
        appInBackground = false
        endTask()
    }
    
    private static func onMainThread(completion: () -> Void) {
        if Thread.isMainThread {
            completion()
        } else {
            DispatchQueue.main.sync {
                completion()
            }
        }
    }
    
    static func registerForBackground() {
        onMainThread {
            endTimer.abort()
            let count = globalBackgroundCount
            globalBackgroundCount = count + 1
            if appInBackground, bgTask == .invalid, count == 0 {
                appBackgrounded()
            }
        }
    }

    static func unregisterForBackground() {
        onMainThread {
            globalBackgroundCount -= 1
            if globalBackgroundCount == 0 && bgTask != .invalid {
                endTimer.push()
            }
        }
    }
}

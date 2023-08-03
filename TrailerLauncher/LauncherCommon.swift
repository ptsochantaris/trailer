import Cocoa

extension Notification.Name {
    static let KillHelper = Notification.Name("KillTrailerLauncher")
}

@MainActor
enum LauncherCommon {
    static let helperAppId = "com.housetrip.Trailer.Launcher"
    static var isHelperRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == helperAppId }
    }

    static let mainAppId = "com.housetrip.Trailer"
    static var isMainAppRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == mainAppId }
    }

    static func killHelper() {
        if isHelperRunning {
            DistributedNotificationCenter.default().post(name: .KillHelper, object: mainAppId)
        }
    }

    static func launchMainApp() {
        if isMainAppRunning { return }
        let path = "/" + Bundle.main.bundlePath.split(separator: "/").dropLast(3).joined(separator: "/") + "/MacOS/Trailer"
        NSWorkspace.shared.open(URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
    }
}

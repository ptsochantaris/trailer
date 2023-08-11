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
        var finalPathComponents = [String.SubSequence]()
        for component in Bundle.main.bundlePath.split(separator: "/") {
            finalPathComponents.append(component)
            if component.hasSuffix(".app") {
                break
            }
        }
        let path = "/" + finalPathComponents.joined(separator: "/")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config) { _, _ in }
    }
}

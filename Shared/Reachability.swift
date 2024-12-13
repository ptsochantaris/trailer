import Foundation
import SystemConfiguration

enum NetworkStatus {
    case notReachable, reachableViaWiFi, reachableViaWWAN
    var name: String {
        switch self {
        case .notReachable:
            "Down"
        case .reachableViaWiFi:
            "Local"
        case .reachableViaWWAN:
            "Cellular"
        }
    }
}

let ReachabilityChangedNotification = Notification.Name("ReachabilityChangedNotification")

func ReachabilityCallback(target _: SCNetworkReachability, flags _: SCNetworkReachabilityFlags, info _: UnsafeMutableRawPointer?) {
    Task { @MainActor in
        NotificationCenter.default.post(name: ReachabilityChangedNotification, object: nil)
    }
}

final class Reachability {
    private let reachability: SCNetworkReachability

    init() {
        var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)

        reachability = withUnsafePointer(to: &zeroAddress) { pointer in
            let p = UnsafePointer<sockaddr>(OpaquePointer(pointer))
            return SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, p)!
        }
    }

    func startNotifier() {
        var context = SCNetworkReachabilityContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)

        if SCNetworkReachabilitySetCallback(reachability, ReachabilityCallback, &context) {
            if SCNetworkReachabilityScheduleWithRunLoop(reachability, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue) {
                Task {
                    await Logging.shared.log("Reachability monitoring active")
                }
                return
            }
        }
        Task {
            await Logging.shared.log("Reachability monitoring start failed")
        }
    }

    deinit {
        SCNetworkReachabilityUnscheduleFromRunLoop(reachability, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
    }

    var status: NetworkStatus {
        var flags = SCNetworkReachabilityFlags()
        var returnValue: NetworkStatus = .notReachable

        if SCNetworkReachabilityGetFlags(reachability, &flags) {
            if flags.contains(.reachable) {
                if !flags.contains(.connectionRequired) { returnValue = .reachableViaWiFi }

                if flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic) {
                    if !flags.contains(.interventionRequired) { returnValue = .reachableViaWiFi }
                }

                #if os(iOS)
                    if flags.contains(.isWWAN) { returnValue = .reachableViaWWAN }
                #endif
            }
        }

        return returnValue
    }
}


import Foundation
import SystemConfiguration

enum NetworkStatus: Int {
	case NotReachable, ReachableViaWiFi, ReachableViaWWAN
	static let descriptions = ["Down", "Local", "Cellular"]
	var name: String { return NetworkStatus.descriptions[rawValue] }
}

let ReachabilityChangedNotification = Notification.Name("ReachabilityChangedNotification")

func ReachabilityCallback(target: SCNetworkReachability, flags: SCNetworkReachabilityFlags, info: UnsafeMutableRawPointer?) {
	NotificationCenter.default.post(name: ReachabilityChangedNotification, object: nil)
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

		if (SCNetworkReachabilitySetCallback(reachability, ReachabilityCallback, &context)) {
			if (SCNetworkReachabilityScheduleWithRunLoop(reachability, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)) {
				DLog("Reachability monitoring active")
				return
			}
		}
		DLog("Reachability monitoring start failed")
	}

	deinit {
		SCNetworkReachabilityUnscheduleFromRunLoop(reachability, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
	}

	var status: NetworkStatus {

		var flags = SCNetworkReachabilityFlags()
		var returnValue: NetworkStatus = .NotReachable

		if SCNetworkReachabilityGetFlags(reachability, &flags) {
			if flags.contains(.reachable) {

				if !flags.contains(.connectionRequired) { returnValue = .ReachableViaWiFi }

				if flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic) {
					if !flags.contains(.interventionRequired) { returnValue = .ReachableViaWiFi }
				}

				#if os(iOS)
					if flags.contains(.isWWAN) { returnValue = .ReachableViaWWAN }
				#endif
			}
		}

		return returnValue
	}
}

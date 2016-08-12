
import Foundation
import SystemConfiguration

enum NetworkStatus: Int {
	case NotReachable, ReachableViaWiFi, ReachableViaWWAN
}

let ReachabilityChangedNotification = Notification.Name("ReachabilityChangedNotification")

func ReachabilityCallback(target: SCNetworkReachability, flags: SCNetworkReachabilityFlags, info: UnsafeMutablePointer<Void>?) {
	NotificationCenter.default.post(name: ReachabilityChangedNotification, object: nil, userInfo: nil)
}

class Reachability {

	let reachability: SCNetworkReachability

	init() {
		var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
		zeroAddress.sin_len = UInt8(sizeofValue(zeroAddress))
		zeroAddress.sin_family = sa_family_t(AF_INET)

		reachability = withUnsafePointer(&zeroAddress) {
			SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, UnsafePointer($0))!
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

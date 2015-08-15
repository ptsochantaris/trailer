
let SECTION_KEY = "INDEX_KEY"
let PULL_REQUEST_KEY = "PULL_REQUEST_KEY"
let ISSUE_KEY = "ISSUE_KEY"
let TYPE_KEY = "TYPE_KEY"
let SESSION_REACHABILITY_CHANGE_KEY = "SESSION_REACHABILITY_CHANGE_KEY"

import WatchKit
import WatchConnectivity

class ExtensionDelegate: NSObject, WKExtensionDelegate, WCSessionDelegate {

	let session = WCSession.defaultSession()
	var appLaunched = false
	var lastView = ""

	func startWatchConnectSessionIfNeeded() {
		if session.delegate == nil {
			session.delegate = self
			session.activateSession()
		}
	}

	func sessionReachabilityDidChange(session: WCSession) {
		NSNotificationCenter.defaultCenter().postNotificationName(SESSION_REACHABILITY_CHANGE_KEY, object: nil)
	}

	func applicationDidFinishLaunching() {
		appLaunched = true
		startWatchConnectSessionIfNeeded()
	}
	
	func applicationDidBecomeActive() {
	}

	func applicationWillResignActive() {
		lastView = ""
	}

}

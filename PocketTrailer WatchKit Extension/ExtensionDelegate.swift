
let SECTION_KEY = "INDEX_KEY"
let PULL_REQUEST_KEY = "PULL_REQUEST_KEY"
let ISSUE_KEY = "ISSUE_KEY"
let TYPE_KEY = "TYPE_KEY"

import WatchKit
import WatchConnectivity

class ExtensionDelegate: NSObject, WKExtensionDelegate, WCSessionDelegate {

	var lastView = ""

	func applicationDidFinishLaunching() {
	}
	
	func applicationDidBecomeActive() {
	}

	func applicationWillResignActive() {
		lastView = ""
	}

}

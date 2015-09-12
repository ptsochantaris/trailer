
let SECTION_KEY = "INDEX_KEY"
let PULL_REQUEST_KEY = "PULL_REQUEST_KEY"
let ISSUE_KEY = "ISSUE_KEY"
let TYPE_KEY = "TYPE_KEY"

import WatchKit
import WatchConnectivity
import ClockKit

class ExtensionDelegate: NSObject, WKExtensionDelegate, WCSessionDelegate {

	var lastView = ""

	func applicationDidFinishLaunching() {
	}
	
	func applicationDidBecomeActive() {
		updateComplications()
	}

	func applicationWillResignActive() {
		lastView = ""
	}

	func updateComplications() {
		let complicationServer = CLKComplicationServer.sharedInstance()
		if let activeComplications = complicationServer.activeComplications {
			for complication in activeComplications {
				complicationServer.reloadTimelineForComplication(complication)
			}
		}
	}
}

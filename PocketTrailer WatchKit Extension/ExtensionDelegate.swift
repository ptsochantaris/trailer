
let SECTION_KEY = "INDEX_KEY"
let PULL_REQUEST_KEY = "PULL_REQUEST_KEY"
let ISSUE_KEY = "ISSUE_KEY"
let TYPE_KEY = "TYPE_KEY"

import WatchKit
import WatchConnectivity
import ClockKit

class ExtensionDelegate: NSObject, WKExtensionDelegate, WCSessionDelegate {

	private let session = WCSession.defaultSession()

	weak var lastView: CommonController? {
		didSet {
			potentialUpdate()
		}
	}

	func applicationDidFinishLaunching() {
		session.delegate = self
	}

	func sessionReachabilityDidChange(session: WCSession) {
		dispatch_async(dispatch_get_main_queue()) {
			self.potentialUpdate()
		}
	}

	func session(session: WCSession, didReceiveApplicationContext applicationContext: [String : AnyObject]) {
		dispatch_async(dispatch_get_main_queue()) {
			self.potentialUpdate()
		}
	}

	func applicationDidBecomeActive() {
		session.activateSession()
		self.potentialUpdate()
	}

	private func potentialUpdate() {
		if session.reachable, let l = lastView {
			l.requestData(nil)
		}
	}

	func applicationWillResignActive() {
		lastView = nil
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

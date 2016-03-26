
let SECTION_KEY = "INDEX_KEY"
let PULL_REQUEST_KEY = "PULL_REQUEST_KEY"
let ISSUE_KEY = "ISSUE_KEY"
let TYPE_KEY = "TYPE_KEY"

import WatchKit
import WatchConnectivity
import ClockKit

class ExtensionDelegate: NSObject, WKExtensionDelegate, WCSessionDelegate {

	private let session = WCSession.defaultSession()
	private var requestedUpdate = false

	weak var lastView: CommonController? {
		didSet {
			potentialUpdate()
		}
	}

	func applicationDidFinishLaunching() {
		session.delegate = self
	}

	func sessionReachabilityDidChange(session: WCSession) {
		potentialUpdate()
	}

	func session(session: WCSession, didReceiveApplicationContext applicationContext: [String : AnyObject]) {
		potentialUpdate()
	}

	func applicationDidBecomeActive() {
		session.activateSession()
		updateComplications()
	}

	private func potentialUpdate() {
		// Possibly in thread!
		atNextEvent {
			if let l = self.lastView where self.session.reachable && !self.requestedUpdate {
				self.requestedUpdate = true
				l.requestData(nil)
				delay(0.5) {
					self.requestedUpdate = false
				}
			}
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

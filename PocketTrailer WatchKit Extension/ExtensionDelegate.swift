
let SECTION_KEY = "INDEX_KEY"
let ITEM_KEY = "ITEM_KEY"
let TYPE_KEY = "TYPE_KEY"
let UNREAD_KEY = "UNREAD_KEY"
let GROUP_KEY = "GROUP_KEY"
let API_URI_KEY = "API_URI_KEY"

import WatchKit
import WatchConnectivity
import ClockKit

class ExtensionDelegate: NSObject, WKExtensionDelegate, WCSessionDelegate {

	private let session = WCSession.default()
	private var requestedUpdate = false

	weak var lastView: CommonController? {
		didSet {
			potentialUpdate()
		}
	}

	func applicationDidFinishLaunching() {
		session.delegate = self
	}

	func sessionReachabilityDidChange(_ session: WCSession) {
		potentialUpdate()
	}

	func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : AnyObject]) {
		potentialUpdate()
	}

	func applicationDidBecomeActive() {
		session.activate()
	}

	func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
		if activationState == .activated {
			potentialUpdate()
		}
	}

	private func potentialUpdate() {
		// Possibly in thread!
		atNextEvent(self) { S in
			if let l = S.lastView, S.session.isReachable && !S.requestedUpdate {
				S.requestedUpdate = true
				l.requestData(command: nil)
				delay(0.5, S) { S in
					S.requestedUpdate = false
				}
			}
		}
	}

	func applicationWillResignActive() {
		lastView = nil
		updateComplications()
	}

	func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
		for task in backgroundTasks {
			if let t = task as? WKSnapshotRefreshBackgroundTask {
				if t.returnToDefaultState {
					lastView?.popToRootController()
					(lastView as? SectionController)?.resetUI()
				}
				updateComplications()
				t.setTaskCompleted(restoredDefaultState: t.returnToDefaultState, estimatedSnapshotExpiration: Date.distantFuture, userInfo: nil)
			} else {
				task.setTaskCompleted()
			}
		}
	}

	private func updateComplications() {
		let complicationServer = CLKComplicationServer.sharedInstance()
		if let activeComplications = complicationServer.activeComplications {
			for complication in activeComplications {
				complicationServer.reloadTimeline(for: complication)
			}
		}
	}
}

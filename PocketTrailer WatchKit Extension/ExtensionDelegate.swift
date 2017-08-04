
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
	
	private let session = WCSession.default
	private var requestedUpdate = false
	private var appIsLaunched = false
	
	override init() {
		super.init()
		session.delegate = self
		session.activate()
	}
	
	weak var lastView: CommonController? {
		didSet {
			potentialUpdate()
		}
	}
	
	func applicationDidFinishLaunching() {
		appIsLaunched = true
	}
	
	func sessionReachabilityDidChange(_ session: WCSession) {
		if session.isReachable {
			potentialUpdate()
		}
	}
	
	func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
		potentialUpdate()
		if applicationContext.keys.contains("overview") {
			atNextEvent(self) { S in
				S.updateComplications()
				if S.appIsLaunched {
					WKExtension.shared().scheduleSnapshotRefresh(withPreferredDate: Date(), userInfo: nil) { error in
					}
				}
			}
		}
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
			} else if !S.appIsLaunched, S.session.isReachable, !S.session.receivedApplicationContext.keys.contains("overview") {
				S.session.sendMessage(["command": "needsOverview"], replyHandler: nil, errorHandler: nil)
			}
		}
	}
	
	func applicationWillResignActive() {
		lastView = nil
	}
	
	func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
		for task in backgroundTasks {
			if let t = task as? WKSnapshotRefreshBackgroundTask {
				let wantDefault = t.reasonForSnapshot == .returnToDefaultState
				if wantDefault {
					lastView?.popToRootController()
					(lastView as? SectionController)?.resetUI()
				}
				t.setTaskCompleted(restoredDefaultState: wantDefault, estimatedSnapshotExpiration: .distantFuture, userInfo: nil)
			} else {
				task.setTaskCompletedWithSnapshot(false)
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

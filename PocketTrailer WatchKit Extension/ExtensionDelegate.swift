let SECTION_KEY = "INDEX_KEY"
let ITEM_KEY = "ITEM_KEY"
let TYPE_KEY = "TYPE_KEY"
let UNREAD_KEY = "UNREAD_KEY"
let GROUP_KEY = "GROUP_KEY"
let API_URI_KEY = "API_URI_KEY"

import WatchKit
import WatchConnectivity
import ClockKit

final class ExtensionDelegate: NSObject, WKExtensionDelegate, WCSessionDelegate {
	
	private let session = WCSession.default
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
	
	func sessionReachabilityDidChange(_ session: WCSession) {}
    		
	func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["newInfoAvailable"] as? Bool == true {
            potentialUpdate()
        }
    }

    func applicationWillEnterForeground() {
        potentialUpdate()
    }
    
    static var storedOverview: [AnyHashable: Any]? {
        didSet {
            let complicationServer = CLKComplicationServer.sharedInstance()
            if let activeComplications = complicationServer.activeComplications {
                for complication in activeComplications {
                    complicationServer.reloadTimeline(for: complication)
                }
            }
        }
    }
	
	private func potentialUpdate() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
			if let l = self.lastView, self.session.isReachable {
				l.requestData(command: nil)
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
}

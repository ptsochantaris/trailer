
import WatchKit
import ClockKit
import WatchConnectivity

final class GlanceController: WKInterfaceController, WCSessionDelegate {

    @IBOutlet weak var totalCount: WKInterfaceLabel!
	@IBOutlet var totalGroup: WKInterfaceGroup!
	@IBOutlet var errorText: WKInterfaceLabel!

	@IBOutlet weak var myCount: WKInterfaceLabel!
	@IBOutlet weak var myGroup: WKInterfaceGroup!

	@IBOutlet weak var mentionedCount: WKInterfaceLabel!
	@IBOutlet weak var mentionedGroup: WKInterfaceGroup!

	@IBOutlet weak var participatedCount: WKInterfaceLabel!
	@IBOutlet weak var participatedGroup: WKInterfaceGroup!

	@IBOutlet weak var otherCount: WKInterfaceLabel!
	@IBOutlet weak var otherGroup: WKInterfaceGroup!

	@IBOutlet weak var snoozingCount: WKInterfaceLabel!
	@IBOutlet weak var snoozingGroup: WKInterfaceGroup!

	@IBOutlet weak var unreadCount: WKInterfaceLabel!
	@IBOutlet weak var unreadGroup: WKInterfaceGroup!

	@IBOutlet weak var lastUpdate: WKInterfaceLabel!

	@IBOutlet weak var prIcon: WKInterfaceImage!
	@IBOutlet weak var issueIcon: WKInterfaceImage!

	private var showIssues = false

	override func awakeWithContext(context: AnyObject?) {
		super.awakeWithContext(context)
		errorText.setText("Loading...")
		setErrorMode(true)
	}

	override func willActivate() {
		super.willActivate()

		let session = WCSession.defaultSession()
		session.delegate = self
		session.activateSession()

		if session.iOSDeviceNeedsUnlockAfterRebootForReachability {
			errorText.setText("Please unlock your iPhone first")
			setErrorMode(true)
		} else if session.receivedApplicationContext.count > 0 {
			self.updateFromContext(session.receivedApplicationContext)
		}
	}

	func session(session: WCSession, didReceiveApplicationContext applicationContext: [String : AnyObject]) {
		dispatch_async(dispatch_get_main_queue()) {
			self.updateFromContext(applicationContext)
		}
	}

	func sessionReachabilityDidChange(session: WCSession) {
		dispatch_async(dispatch_get_main_queue()) {
			self.updateFromContext(session.receivedApplicationContext)
		}
	}

	private func updateFromContext(applicationContext: [String : AnyObject]) {
		if let result = applicationContext["overview"] as? [String : AnyObject] {

			showIssues = result["preferIssues"] as! Bool
			prIcon.setHidden(showIssues)
			issueIcon.setHidden(!showIssues)

			let r = result[showIssues ? "issues" : "prs"] as! [String : AnyObject]

			let tc = r["total_open"] as? Int ?? 0
			totalCount.setText("\(tc)")

			func setCount(s: Section, _ count: WKInterfaceLabel, _ group: WKInterfaceGroup) {
				let c = r[s.apiName()]?["total"] as? Int ?? 0
				count.setText("\(c) \(s.watchMenuName().uppercaseString)")
				group.setAlpha(c==0 ? 0.4 : 1.0)
			}
			setCount(.Mine, myCount, myGroup)
			setCount(.Participated, participatedCount, participatedGroup)
			setCount(.Mentioned, mentionedCount, mentionedGroup)
			setCount(.All, otherCount, otherGroup)
			setCount(.Snoozed, snoozingCount, snoozingGroup)

			let uc = r["unread"] as! Int
			if uc==0 {
				unreadCount.setText("NONE UNREAD")
				unreadGroup.setAlpha(0.3)
			} else if uc==1 {
				unreadCount.setText("1 COMMENT")
				unreadGroup.setAlpha(1.0)
			} else {
				unreadCount.setText("\(uc) COMMENTS")
				unreadGroup.setAlpha(1.0)
			}

			if let lastRefresh = result["lastUpdated"] as? NSDate where !lastRefresh.isEqualToDate(never()) {
				lastUpdate.setText(shortDateFormatter.stringFromDate(lastRefresh))
			} else {
				lastUpdate.setText("Not refreshed yet")
			}

			errorText.setText(nil)
			setErrorMode(false)

			updateComplications()
		}
	}

	private func setErrorMode(mode: Bool) {
		for g in [myGroup, participatedGroup, mentionedGroup, otherGroup, unreadGroup, totalGroup, lastUpdate, errorText] {
			g.setHidden(mode)
		}
	}

	private func updateComplications() {
		let complicationServer = CLKComplicationServer.sharedInstance()
		if let activeComplications = complicationServer.activeComplications {
			for complication in activeComplications {
				complicationServer.reloadTimelineForComplication(complication)
			}
		}
	}
}


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

			var totalOpen = 0
			var totalUnread = 0
			var totalMine = 0
			var totalParticipated = 0
			var totalMentioned = 0
			var totalSnoozed = 0
			var totalOther = 0
			for r in result["views"] as! [[String : AnyObject]] {
				if let v = r[showIssues ? "issues" : "prs"] as? [String : AnyObject] {
					totalMine += v[Section.Mine.apiName()]?["total"] as? Int ?? 0
					totalParticipated += v[Section.Participated.apiName()]?["total"] as? Int ?? 0
					totalMentioned += v[Section.Mentioned.apiName()]?["total"] as? Int ?? 0
					totalSnoozed += v[Section.Snoozed.apiName()]?["total"] as? Int ?? 0
					totalOther += v[Section.All.apiName()]?["total"] as? Int ?? 0
					totalUnread += v["unread"] as? Int ?? 0
					totalOpen += v["total_open"] as? Int ?? 0
				}
			}

			totalCount.setText("\(totalOpen)")

			func setCount(c: Int, section: Section, _ count: WKInterfaceLabel, _ group: WKInterfaceGroup) {
				count.setText("\(c) \(section.watchMenuName().uppercaseString)")
				group.setAlpha(c==0 ? 0.4 : 1.0)
			}
			setCount(totalMine, section: .Mine, myCount, myGroup)
			setCount(totalParticipated, section: .Participated, participatedCount, participatedGroup)
			setCount(totalMentioned, section: .Mentioned, mentionedCount, mentionedGroup)
			setCount(totalOther, section: .All, otherCount, otherGroup)
			setCount(totalSnoozed, section: .Snoozed, snoozingCount, snoozingGroup)

			if totalUnread==0 {
				unreadCount.setText("NONE UNREAD")
				unreadGroup.setAlpha(0.3)
			} else if totalUnread==1 {
				unreadCount.setText("1 COMMENT")
				unreadGroup.setAlpha(1.0)
			} else {
				unreadCount.setText("\(totalUnread) COMMENTS")
				unreadGroup.setAlpha(1.0)
			}

			if let lastRefresh = result["lastUpdated"] as? NSDate where lastRefresh != never() {
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

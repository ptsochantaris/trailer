
import WatchKit
import WatchConnectivity

let shortDateFormatter = { () -> NSDateFormatter in
	let d = NSDateFormatter()
	d.dateStyle = NSDateFormatterStyle.ShortStyle
	d.timeStyle = NSDateFormatterStyle.ShortStyle
	d.doesRelativeDateFormatting = true
	return d
	}()

final class GlanceController: WKInterfaceController {

    @IBOutlet weak var totalCount: WKInterfaceLabel!
	@IBOutlet var totalGroup: WKInterfaceGroup!
	@IBOutlet var errorText: WKInterfaceLabel!

	@IBOutlet weak var myCount: WKInterfaceLabel!
	@IBOutlet weak var myGroup: WKInterfaceGroup!

	@IBOutlet weak var mergedCount: WKInterfaceLabel!
	@IBOutlet weak var mergedGroup: WKInterfaceGroup!

	@IBOutlet weak var closedCount: WKInterfaceLabel!
	@IBOutlet weak var closedGroup: WKInterfaceGroup!

	@IBOutlet weak var participatedCount: WKInterfaceLabel!
	@IBOutlet weak var participatedGroup: WKInterfaceGroup!

	@IBOutlet weak var otherCount: WKInterfaceLabel!
	@IBOutlet weak var otherGroup: WKInterfaceGroup!

	@IBOutlet weak var unreadCount: WKInterfaceLabel!
	@IBOutlet weak var unreadGroup: WKInterfaceGroup!

	@IBOutlet weak var lastUpdate: WKInterfaceLabel!

	@IBOutlet weak var prIcon: WKInterfaceImage!
	@IBOutlet weak var issueIcon: WKInterfaceImage!

	override func awakeWithContext(context: AnyObject?) {
		let d = WKExtension.sharedExtension().delegate as! ExtensionDelegate
		d.startWatchConnectSessionIfNeeded()
		NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("reachabilityChanged"), name: SESSION_REACHABILITY_CHANGE_KEY, object: nil)
		errorText.setText("Loading...")
		setErrorMode(true)
	}

	override func willActivate() {
		super.willActivate()
		requestUpdate()
	}

	func reachabilityChanged() {
		requestUpdate()
	}

	private func requestUpdate() {
		WCSession.defaultSession().sendMessage(["list": "overview"], replyHandler: { data in
			dispatch_async(dispatch_get_main_queue()) {
				self.updateFromData(data)
			}
			}) { error  in
				dispatch_async(dispatch_get_main_queue()) {
					self.showError(error)
				}
		}
	}

	private func updateFromData(data: [String : AnyObject]) {

		let result = data["result"] as! [String : AnyObject]

		let showIssues = result["glanceWantsIssues"] as! Bool
		prIcon.setHidden(showIssues)
		issueIcon.setHidden(!showIssues)
		mergedGroup.setHidden(showIssues)

		let r = result[showIssues ? "issues" : "prs"] as! [String : AnyObject]

		let tc = r["total"] as! Int
		totalCount.setText("\(tc)")

		let mc = r["mine"]?["total"] as! Int
		myCount.setText("\(mc) \(PullRequestSection.Mine.watchMenuName().uppercaseString)")
		myGroup.setAlpha(mc==0 ? 0.4 : 1.0)

		let pc = r["participated"]?["total"] as! Int
		participatedCount.setText("\(pc) \(PullRequestSection.Participated.watchMenuName().uppercaseString)")
		participatedGroup.setAlpha(pc==0 ? 0.4 : 1.0)

		if !showIssues {
			let rc = r["merged"]?["total"] as! Int
			mergedCount.setText("\(rc) \(PullRequestSection.Merged.watchMenuName().uppercaseString)")
			mergedGroup.setAlpha(rc==0 ? 0.4 : 1.0)
		}

		let cc = r["closed"]?["total"] as! Int
		closedCount.setText("\(cc) \(PullRequestSection.Closed.watchMenuName().uppercaseString)")
		closedGroup.setAlpha(cc==0 ? 0.4 : 1.0)

		let oc = r["other"]?["total"] as! Int
		otherCount.setText("\(oc) \(PullRequestSection.All.watchMenuName().uppercaseString)")
		otherGroup.setAlpha(oc==0 ? 0.4 : 1.0)

		let uc = r["participated"]?["unread"] as! Int
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

		let lastRefresh = result["lastUpdated"] as! NSDate
		if lastRefresh.isEqualToDate(NSDate.distantPast()) {
			lastUpdate.setText("Not refreshed yet")
		} else {
			lastUpdate.setText(shortDateFormatter.stringFromDate(lastRefresh))
		}

		setErrorMode(false)
	}

	private func showError(error: NSError) {
		setErrorMode(true)
		let d = WKExtension.sharedExtension().delegate as! ExtensionDelegate
		if !WCSession.defaultSession().reachable && d.appLaunched == false {
			errorText.setText("Please tap to open PocketTrailer for the first time to make glance work");
		} else if !WCSession.defaultSession().reachable {
			errorText.setText("PocketTrailer cannot connect to your iPhone");
		} else if WCSession.defaultSession().iOSDeviceNeedsUnlockAfterRebootForReachability {
			errorText.setText("Please unlock your iPhone first");
		} else {
			errorText.setText(error.localizedDescription)
		}
	}

	private func setErrorMode(mode: Bool) {
		myGroup.setHidden(mode)
		participatedGroup.setHidden(mode)
		mergedGroup.setHidden(mode)
		closedGroup.setHidden(mode)
		otherGroup.setHidden(mode)
		unreadGroup.setHidden(mode)
		totalGroup.setHidden(mode)
		lastUpdate.setHidden(mode)
		errorText.setHidden(!mode)
	}
}

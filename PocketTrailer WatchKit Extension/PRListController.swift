
import WatchKit
import WatchConnectivity

final class PRListController: WKInterfaceController {

	@IBOutlet weak var table: WKInterfaceTable!
	@IBOutlet var statusLabel: WKInterfaceLabel!

	private var firstLoad: Bool = true
	private var section: PullRequestSection!
	private var type: String!
	private var selectedIndex: Int?

	override func awakeWithContext(context: AnyObject?) {

		let c = context as! [NSObject : AnyObject]
		section = PullRequestSection(rawValue: c[SECTION_KEY] as! Int)
		type = c[TYPE_KEY] as! String

		setTitle(section.watchMenuName())

		sendCommand(nil)
	}

	private var app: ExtensionDelegate {
		return WKExtension.sharedExtension().delegate as! ExtensionDelegate
	}

	override func willActivate() {
		super.willActivate()
		if !firstLoad && app.session.reachable && app.lastView != "LIST" {
			sendCommand(nil)
		}
	}

	override func didAppear() {
		app.lastView = "LIST"
		firstLoad = false
		super.didAppear()
	}

	private func showStatus(status: String) {
		table.setHidden(!status.isEmpty)
		statusLabel.setText(status)
		statusLabel.setHidden(status.isEmpty)
	}

	private func sendCommand(command: String?) {

		showStatus("Loading")

		var params = ["list": "item_list", "type": type, "section": section.apiName()]
		if let command = command {
			params["command"] = command
		}
		WCSession.defaultSession().sendMessage(params, replyHandler: { response in
			if let errorIndicator = response["error"] as? Bool where errorIndicator == true {
				self.showTemporaryError(response["status"] as! String)
			} else {
				self.updateFromData(response)
			}
			}) { error in
				self.showTemporaryError("Error: "+error.localizedDescription)
		}
	}

	private func showTemporaryError(error: String) {
		self.statusLabel.setTextColor(UIColor.redColor())
		self.showStatus(error)
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (Int64)(3.0 * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
			self.statusLabel.setTextColor(UIColor.whiteColor())
			self.showStatus("")
		}
	}

	private func updateFromData(data: [String : AnyObject]) {

		let result = data["result"] as! [[String : AnyObject]]

		table.setNumberOfRows(result.count, withRowType: "PRRow")

		showStatus(result.count==0 ? "There are no items in this section" : "")

		var index = 0
		for itemData in result {
			if let c = table.rowControllerAtIndex(index++) as? PRRow {
				c.populateFrom(itemData)
			}
		}

		self.showStatus("")
		if let s = self.selectedIndex {
			self.table.scrollToRowAtIndex(s)
			self.selectedIndex = nil
		}
	}

	@IBAction func markAllReadSelected() {
		showStatus("Marking items as read")
		if type=="prs" {
			sendCommand("markAllPrsRead")
		} else {
			sendCommand("markAllIssuesRead")
		}
	}

	@IBAction func refreshSelected() {
		showStatus("Refreshing")
		sendCommand("refresh")
	}

	override func table(table: WKInterfaceTable, didSelectRowAtIndex rowIndex: Int) {
		selectedIndex = rowIndex
		let row = table.rowControllerAtIndex(rowIndex) as! PRRow
		let key = (type=="prs" ? PULL_REQUEST_KEY : ISSUE_KEY)
		pushControllerWithName("DetailController", context: [ key: row.itemId! ])
	}
}

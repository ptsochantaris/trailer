
import WatchKit
import WatchConnectivity

final class SectionController: WKInterfaceController {

	@IBOutlet weak var table: WKInterfaceTable!
	@IBOutlet weak var statusLabel: WKInterfaceLabel!

	private var rowControllers = [PopulatableRow]()

	private var app: ExtensionDelegate {
		return WKExtension.sharedExtension().delegate as! ExtensionDelegate
	}

	override func awakeWithContext(context: AnyObject?) {
		super.awakeWithContext(context)
		showStatus("Loading")
	}

	override func willActivate() {
		super.willActivate()
		if app.lastView != "SECTIONS" {
			app.lastView = "SECTIONS"
			sendCommand(nil)
		}
	}

	private func showStatus(status: String) {
		table.setAlpha(status.isEmpty ? 1.0 : 0.5)
		statusLabel.setText(status)
		statusLabel.setHidden(status.isEmpty)
	}

	private func sendCommand(command: String?) {

		var params = ["list": "overview"]
		if let command = command {
			params["command"] = command
		}
		WCSession.defaultSession().sendMessage(params, replyHandler: { response in
			dispatch_async(dispatch_get_main_queue(), { () -> Void in
				if let errorIndicator = response["error"] as? Bool where errorIndicator == true {
					self.showTemporaryError(response["status"] as! String)
				} else {
					self.updateFromData(response)
				}
			})
			}) { error in
				dispatch_async(dispatch_get_main_queue(), { 
					self.showTemporaryError("Error: "+error.localizedDescription)
				})
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

	@IBAction func clearMergedSelected() {
		showStatus("Clearing merged")
		sendCommand("clearAllMerged")
	}

	@IBAction func clearClosedSelected() {
		showStatus("Clearing closed")
		sendCommand("clearAllClosed")
	}

	@IBAction func markAllReadSelected() {
		showStatus("Marking all as read")
		sendCommand("markEverythingRead")
	}

	@IBAction func refreshSelected() {
		showStatus("Refreshing")
		sendCommand("refresh")
	}

	override func table(table: WKInterfaceTable, didSelectRowAtIndex rowIndex: Int) {
		let r = rowControllers[rowIndex] as! SectionRow
		let section = r.section?.rawValue
		pushControllerWithName("ListController", context: [ SECTION_KEY: section!, TYPE_KEY: r.type! ] )
	}

	private func updateFromData(data: [String : AnyObject]) {

		rowControllers.removeAll(keepCapacity: false)
		let result = data["result"] as! [String : AnyObject]

		let prType = "prs"
		let prs = result[prType] as! [String : AnyObject]
		let totalPrs = prs["total"] as! Int
		let pt = TitleRow()
		rowControllers.append(pt)
		if totalPrs > 0 {
			pt.title = "\(totalPrs) PULL REQUESTS"
			for prSection in PullRequestSection.apiTitles {
				if prSection == PullRequestSection.None.apiName() { continue }

				if let section = prs[prSection], count = section["total"] as? Int, unread = section["unread"] as? Int where count > 0 {
					let s = SectionRow()
					s.section = sectionFromApi(prSection)
					s.totalCount = count
					s.unreadCount = unread
					s.type = prType
					rowControllers.append(s)
				}
			}
		} else {
			pt.title = prs["error"] as? String
		}


		let issueType = "issues"
		let issues = result[issueType] as! [String : AnyObject]
		let totalIssues = issues["total"] as! Int
		let it = TitleRow()
		rowControllers.append(it)
		if totalIssues > 0 {
			it.title = "\(totalIssues) ISSUES"
			for issueSection in PullRequestSection.apiTitles {
				if issueSection == PullRequestSection.None.apiName() { continue }
				if issueSection == PullRequestSection.Merged.apiName() { continue }

				if let section = issues[issueSection], count = section["total"] as? Int, unread = section["unread"] as? Int where count > 0 {
					let s = SectionRow()
					s.section = sectionFromApi(issueSection)
					s.totalCount = count
					s.unreadCount = unread
					s.type = issueType
					rowControllers.append(s)
				}
			}
		} else {
			it.title = issues["error"] as? String
		}

		table.setRowTypes(rowControllers.map({ $0.rowType() }))

		var index = 0
		for rc in rowControllers {
			if let c = table.rowControllerAtIndex(index++) as? PopulatableRow {
				c.populateFrom(rc)
			}
		}

		self.showStatus("")
	}
}

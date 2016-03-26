
import WatchKit
import WatchConnectivity

final class SectionController: CommonController {

	@IBOutlet weak var table: WKInterfaceTable!
	@IBOutlet weak var statusLabel: WKInterfaceLabel!

	private var rowControllers = [PopulatableRow]()

	override func awakeWithContext(context: AnyObject?) {
		_statusLabel = statusLabel
		_table = table
		super.awakeWithContext(context)
	}

	override func showLoadingFeedback() -> Bool {
		return false
	}

	@IBAction func clearMergedSelected() {
		showStatus("Clearing merged", hideTable: true)
		requestData("clearAllMerged")
	}

	@IBAction func clearClosedSelected() {
		showStatus("Clearing closed", hideTable: true)
		requestData("clearAllClosed")
	}

	@IBAction func markAllReadSelected() {
		showStatus("Marking all as read", hideTable: true)
		requestData("markEverythingRead")
	}

	@IBAction func refreshSelected() {
		showStatus("Refreshing", hideTable: true)
		requestData("refresh")
	}

	override func requestData(command: String?) {
		if let c = command {
			sendRequest(["command": c])
		} else {
			updateUI()
		}
	}

	override func table(table: WKInterfaceTable, didSelectRowAtIndex rowIndex: Int) {
		let r = rowControllers[rowIndex] as! SectionRow
		let section = r.section?.rawValue
		pushControllerWithName("ListController", context: [ SECTION_KEY: section!, TYPE_KEY: r.type! ] )
	}

	override func updateFromData(response: [NSString : AnyObject]) {
		super.updateFromData(response)
		updateUI()
	}

	private func updateUI() {

		rowControllers.removeAll(keepCapacity: false)
		let session = WCSession.defaultSession()
		if let result = session.receivedApplicationContext["overview"] as? [String : AnyObject] {

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
				if let c = table.rowControllerAtIndex(index) as? PopulatableRow {
					c.populateFrom(rc)
				}
				index += 1
			}

			showStatus("", hideTable: false)
			(WKExtension.sharedExtension().delegate as! ExtensionDelegate).updateComplications()
		} else {
			showStatus("There is no data from Trailer yet, please run it once on your iOS device", hideTable: true)
		}
	}
}

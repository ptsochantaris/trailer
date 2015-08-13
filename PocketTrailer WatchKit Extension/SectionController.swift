
import WatchKit
import WatchConnectivity

final class SectionController: WKInterfaceController {

	@IBOutlet weak var table: WKInterfaceTable!

	private var selectedIndex: Int?

	override func willActivate() {
		super.willActivate()
		//reloadData()
	}

	/*
	private func sendCommand(command: String) {
		showBusy()
		WCSession.defaultSession().sendMessage(["command" : command, "list": "overview"], replyHandler: { response in

			}) { error in
				errorMode(error)
		}
	}
*/

	@IBAction func clearMergedSelected() {
		presentControllerWithName("Command Controller", context: ["command": "clearAllMerged"])
	}

	@IBAction func clearClosedSelected() {
		presentControllerWithName("Command Controller", context: ["command": "clearAllClosed"])
	}

	@IBAction func markAllReadSelected() {
		presentControllerWithName("Command Controller", context: ["command": "markEverythingRead"])
	}

	@IBAction func refreshSelected() {
		presentControllerWithName("Command Controller", context: ["command": "refresh"])
	}

	/*
	class titleEntry {
		var title: String
		init(_ t: String) { title = t }
	}

	class attributedTitleEntry {
		var title: NSAttributedString
		init(_ t: NSAttributedString) { title = t }
	}

	class prEntry {
		var section: PullRequestSection
		init(_ s: PullRequestSection) { section = s }
	}

	class issueEntry {
		var section: PullRequestSection
		init(_ s: PullRequestSection) { section = s }
	}

	override func table(table: WKInterfaceTable, didSelectRowAtIndex rowIndex: Int) {
		selectedIndex = rowIndex
		if let t = rowTypes[rowIndex] as? prEntry {
			pushControllerWithName("ListController", context: [ SECTION_KEY: t.section.rawValue, TYPE_KEY: "PRS" ] )
		} else if let t = rowTypes[rowIndex] as? issueEntry {
			pushControllerWithName("ListController", context: [ SECTION_KEY: t.section.rawValue, TYPE_KEY: "ISSUES" ] )
		}
	}

	private var boundaryIndex:Int = 0
    private var rowTypes = [AnyObject]()

	private func reloadData() {

		rowTypes.removeAll(keepCapacity: false)

		func appendNonZeroPrs(s: PullRequestSection) {
			if PullRequest.countRequestsInSection(s, moc: mainObjectContext) > 0 {
				rowTypes.append(prEntry(s))
			}
		}

		func appendNonZeroIssues(s: PullRequestSection) {
			if Issue.countIssuesInSection(s, moc: mainObjectContext) > 0 {
				rowTypes.append(issueEntry(s))
			}
		}

		let totalPrs = PullRequest.countAllRequestsInMoc(mainObjectContext)
		if totalPrs==0 {
			rowTypes.append(attributedTitleEntry(DataManager.reasonForEmptyWithFilter(nil)))
		} else {
			rowTypes.append(titleEntry(totalPrs==1 ? "1 PULL REQUEST" : "\(totalPrs) PULL REQUESTS"))
			appendNonZeroPrs(PullRequestSection.Mine)
			appendNonZeroPrs(PullRequestSection.Participated)
			appendNonZeroPrs(PullRequestSection.Merged)
			appendNonZeroPrs(PullRequestSection.Closed)
			appendNonZeroPrs(PullRequestSection.All)
		}

		boundaryIndex = rowTypes.count

		if Repo.interestedInIssues() {
			let totalIssues = Issue.countAllIssuesInMoc(mainObjectContext)
			if totalIssues==0 {
				rowTypes.append(attributedTitleEntry(DataManager.reasonForEmptyIssuesWithFilter(nil)))
			} else {
				rowTypes.append(titleEntry(totalIssues==1 ? "1 ISSUE" : "\(totalIssues) ISSUES"))
				appendNonZeroIssues(PullRequestSection.Mine)
				appendNonZeroIssues(PullRequestSection.Participated)
				appendNonZeroIssues(PullRequestSection.Merged)
				appendNonZeroIssues(PullRequestSection.Closed)
				appendNonZeroIssues(PullRequestSection.All)
			}
		}

		setTitle("Sections")

		var rowControllerTypes = [String]()
		for type in rowTypes {
			if type is titleEntry || type is attributedTitleEntry{
				rowControllerTypes.append("TitleRow")
			} else if type is prEntry || type is issueEntry {
				rowControllerTypes.append("SectionRow")
			}
		}
		table.setRowTypes(rowControllerTypes)

		var index = 0
		for type in rowTypes {
			if let t = type as? titleEntry {
				let r = table.rowControllerAtIndex(index) as! TitleRow
				r.titleL.setText(t.title)
			} else if let t = type as? attributedTitleEntry {
				let r = table.rowControllerAtIndex(index) as! TitleRow
				r.group.setBackgroundColor(UIColor.whiteColor())
				r.group.setAlpha(1.0)
				r.titleL.setAttributedText(t.title)
			} else if let t = type as? prEntry {
				(table.rowControllerAtIndex(index) as! SectionRow).setPr(t.section)
			} else if let t = type as? issueEntry {
				(table.rowControllerAtIndex(index) as! SectionRow).setIssue(t.section)
			}
			index++
		}
	
		if let i = self!.selectedIndex {
			self!.table.scrollToRowAtIndex(i)
			self!.selectedIndex = nil
		}
	}
*/
}

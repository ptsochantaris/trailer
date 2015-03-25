
import WatchKit

class SectionController: WKInterfaceController {

    @IBOutlet weak var table: WKInterfaceTable!

    var refreshWhenBack = false

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

        dataReadonly = true
		Settings.clearCache()

        buildUI()
    }

    override func willActivate() {
        if refreshWhenBack {
            buildUI()
        }
        super.willActivate()
    }

    override func didDeactivate() {
        super.didDeactivate()
    }

    @IBAction func clearMergedSelected() {
        refreshWhenBack = true
        presentControllerWithName("Command Controller", context: "clearAllMerged")
    }

    @IBAction func clearClosedSelected() {
        refreshWhenBack = true
        presentControllerWithName("Command Controller", context: "clearAllClosed")
    }

    @IBAction func markAllReadSelected() {
        refreshWhenBack = true
        presentControllerWithName("Command Controller", context: "markAllRead")
    }

    @IBAction func refreshSelected() {
        refreshWhenBack = true
        presentControllerWithName("Command Controller", context: "refresh")
    }

	class titleEntry {
		var title: String
		init(_ title: String) { self.title = title }
	}

	class attributedTitleEntry {
		var title: NSAttributedString
		init(_ title: NSAttributedString) { self.title = title }
	}

	class prEntry {
		var section: PullRequestSection
		init(_ section: PullRequestSection) { self.section = section }
	}

	class issueEntry {
		var section: PullRequestSection
		init(_ section: PullRequestSection) { self.section = section }
	}

	override func table(table: WKInterfaceTable, didSelectRowAtIndex rowIndex: Int) {
		if Settings.showIssuesMenu {
			var ri = rowIndex
			var type = "PRS"
			if ri > PullRequestSection.All.rawValue {
				ri -= PullRequestSection.All.rawValue
				ri--
				type = "ISSUES"
			}
			pushControllerWithName("ListController", context: [ SECTION_KEY: ri, TYPE_KEY: type ] )
		} else {
			pushControllerWithName("ListController", context: [ SECTION_KEY: rowIndex+1 ] )
		}
	}

    private func buildUI() {

		var rowTypes = [AnyObject]()

		let totalPrs = PullRequest.countAllRequestsInMoc(mainObjectContext)
        if totalPrs==0 {
            rowTypes.append(attributedTitleEntry(DataManager.reasonForEmptyWithFilter(nil)))
        } else {
			if Settings.showIssuesMenu { rowTypes.append(titleEntry("\(totalPrs) Pull Requests")) }
			rowTypes.append(prEntry(PullRequestSection.Mine))
			rowTypes.append(prEntry(PullRequestSection.Participated))
			rowTypes.append(prEntry(PullRequestSection.Merged))
			rowTypes.append(prEntry(PullRequestSection.Closed))
			rowTypes.append(prEntry(PullRequestSection.All))
        }

		if Settings.showIssuesMenu {
			let totalIssues = Issue.countAllIssuesInMoc(mainObjectContext)
			if totalIssues==0 {
				rowTypes.append(attributedTitleEntry(DataManager.reasonForEmptyIssuesWithFilter(nil)))
			} else {
				rowTypes.append(titleEntry("\(totalIssues) Issues"))
				rowTypes.append(issueEntry(PullRequestSection.Mine))
				rowTypes.append(issueEntry(PullRequestSection.Participated))
				rowTypes.append(issueEntry(PullRequestSection.Merged))
				rowTypes.append(issueEntry(PullRequestSection.Closed))
				rowTypes.append(issueEntry(PullRequestSection.All))
			}
			setTitle("Sections")
		} else {
			setTitle("\(totalPrs) PRs")
		}

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
				(table.rowControllerAtIndex(index) as! TitleRow).titleL.setText(t.title)
			} else if let t = type as? attributedTitleEntry {
				(table.rowControllerAtIndex(index) as! TitleRow).titleL.setAttributedText(t.title)
			} else if let t = type as? prEntry {
				(table.rowControllerAtIndex(index) as! SectionRow).setPr(t.section)
			} else if let t = type as? issueEntry {
				(table.rowControllerAtIndex(index) as! SectionRow).setIssue(t.section)
			}
			index++
		}
    }
}

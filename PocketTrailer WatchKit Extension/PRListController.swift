
import WatchKit
import Foundation

class PRListController: WKInterfaceController {

    @IBOutlet weak var emptyLabel: WKInterfaceLabel!
    @IBOutlet weak var table: WKInterfaceTable!

    var itemsInSection: [AnyObject]!

    var refreshWhenBack = false

    var sectionIndex: Int!

	var prs: Bool!

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

		let c = context as! NSDictionary
        sectionIndex = c[SECTION_KEY] as! Int

		prs = ((c[TYPE_KEY] as! String)=="PRS")

        setTitle(PullRequestSection.watchMenuTitles[sectionIndex])

        buildUI()
    }

    override func willActivate() {
        if refreshWhenBack {
            buildUI()
            refreshWhenBack = false
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

	override func table(table: WKInterfaceTable, didSelectRowAtIndex rowIndex: Int) {
		if prs==true {
			pushControllerWithName("DetailController", context: [ PULL_REQUEST_KEY: itemsInSection[rowIndex] ])
		} else {
			pushControllerWithName("DetailController", context: [ ISSUE_KEY: itemsInSection[rowIndex] ])
		}
	}

    private func buildUI() {

		if prs==true {
			let f = PullRequest.requestForPullRequestsWithFilter(nil, sectionIndex: sectionIndex)
			itemsInSection = mainObjectContext.executeFetchRequest(f, error: nil) as! [PullRequest]
		} else {
			let f = Issue.requestForIssuesWithFilter(nil, sectionIndex: sectionIndex)
			itemsInSection = mainObjectContext.executeFetchRequest(f, error: nil) as! [Issue]
		}

        table.setNumberOfRows(itemsInSection.count, withRowType: "PRRow")

        if itemsInSection.count==0 {
            table.setHidden(true)
            emptyLabel.setHidden(false)
        } else {
            table.setHidden(false)
            emptyLabel.setHidden(true)

            var index = 0
            for item in itemsInSection {
                let controller = table.rowControllerAtIndex(index++) as! PRRow
				if prs==true {
					controller.setPullRequest(item as! PullRequest)
				} else {
					controller.setIssue(item as! Issue)
				}
            }
        }
    }
}

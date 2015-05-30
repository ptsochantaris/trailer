
import WatchKit
import Foundation

final class PRListController: WKInterfaceController {

	@IBOutlet weak var emptyLabel: WKInterfaceLabel!
	@IBOutlet weak var table: WKInterfaceTable!

	private var itemsInSection: [AnyObject]!
	private var sectionIndex: Int!
	private var prs: Bool!
	private var selectedIndex: Int?

	override func awakeWithContext(context: AnyObject?) {
		super.awakeWithContext(context)

		let c = context as! [NSObject : AnyObject]
		sectionIndex = c[SECTION_KEY] as! Int

		prs = ((c[TYPE_KEY] as! String)=="PRS")

		setTitle(PullRequestSection.watchMenuTitles[sectionIndex])
	}

	override func willActivate() {
		super.willActivate()
		buildUI()
		atNextEvent() { [weak self] in
			if let i = self!.selectedIndex {
				self!.table.scrollToRowAtIndex(i)
				self!.selectedIndex = nil
			}
		}
	}

	@IBAction func markAllReadSelected() {
		if prs==true {
			presentControllerWithName("Command Controller", context: ["command": "markAllPrsRead", "sectionIndex": sectionIndex!])
		} else {
			presentControllerWithName("Command Controller", context: ["command": "markAllIssuesRead", "sectionIndex": sectionIndex!])
		}
	}

	@IBAction func refreshSelected() {
		presentControllerWithName("Command Controller", context: ["command": "refresh"])
	}

	override func table(table: WKInterfaceTable, didSelectRowAtIndex rowIndex: Int) {
		selectedIndex = rowIndex
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

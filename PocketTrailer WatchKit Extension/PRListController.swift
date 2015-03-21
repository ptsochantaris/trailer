
import WatchKit
import Foundation


class PRListController: WKInterfaceController {

    @IBOutlet weak var emptyLabel: WKInterfaceLabel!
    @IBOutlet weak var table: WKInterfaceTable!

    var prsInSection: [PullRequest]!

    var refreshWhenBack = false

    var sectionIndex: Int!

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

        sectionIndex = (context as NSDictionary)[SECTION_KEY] as Int

        setTitle(PullRequestSection.shortTitles[sectionIndex])

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

    override func contextForSegueWithIdentifier(segueIdentifier: String, inTable table: WKInterfaceTable, rowIndex: Int) -> AnyObject? {
        return [ PULL_REQUEST_KEY: prsInSection[rowIndex] ]
    }

    private func buildUI() {
        let f = PullRequest.requestForPullRequestsWithFilter(nil, sectionIndex: sectionIndex)
        prsInSection = mainObjectContext.executeFetchRequest(f, error: nil) as [PullRequest]

        table.setNumberOfRows(prsInSection.count, withRowType: "PRRow")

        if prsInSection.count==0 {
            table.setHidden(true)
            emptyLabel.setHidden(false)
        } else {
            table.setHidden(false)
            emptyLabel.setHidden(true)

            var index = 0
            for pr in prsInSection {
                let controller = table.rowControllerAtIndex(index++) as PRRow
                controller.setPullRequest(pr)
            }
        }
    }
}


import WatchKit

class SectionController: WKInterfaceController {

    @IBOutlet weak var emptyLabel: WKInterfaceLabel!
    @IBOutlet weak var table: WKInterfaceTable!

    var titles = [String]()

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

    override func contextForSegueWithIdentifier(segueIdentifier: String, inTable table: WKInterfaceTable, rowIndex: Int) -> AnyObject? {
        return [ SECTION_KEY: rowIndex+1 ]
    }

    private func buildUI() {
        let totalPrs = PullRequest.countAllRequestsInMoc(mainObjectContext)

        if totalPrs==0 {

            table.setHidden(true)
            table.setNumberOfRows(0, withRowType: "TopRow")
            emptyLabel.setHidden(false)

            let a = DataManager.reasonForEmptyWithFilter(nil)
            emptyLabel.setAttributedText(a)
            setTitle("No PRs")

        } else {

            setTitle("\(totalPrs) PRs")

            table.setHidden(false)
            emptyLabel.setHidden(true)

            table.setNumberOfRows(5, withRowType: "SectionRow")

            for f in MINE_INDEX...OTHER_INDEX {
                let controller = table.rowControllerAtIndex(f) as SectionRow
                switch(f) {
                case MINE_INDEX:
                    titles.append(controller.setRow(PullRequestSection.Mine, PullRequestSection.shortTitles[f+1]))
                case PARTICIPATED_INDEX:
                    titles.append(controller.setRow(PullRequestSection.Participated, PullRequestSection.shortTitles[f+1]))
                case MERGED_INDEX:
                    titles.append(controller.setRow(PullRequestSection.Merged, PullRequestSection.shortTitles[f+1]))
                case CLOSED_INDEX:
                    titles.append(controller.setRow(PullRequestSection.Closed, PullRequestSection.shortTitles[f+1]))
                case OTHER_INDEX:
                    titles.append(controller.setRow(PullRequestSection.All, PullRequestSection.shortTitles[f+1]))
                default: break
                }
            }
        }
    }
}

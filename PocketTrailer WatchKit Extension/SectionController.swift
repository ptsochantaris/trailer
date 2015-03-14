//
//  TopController.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 14/03/2015.
//
//

import WatchKit

class SectionController: WKInterfaceController {

    @IBOutlet weak var emptyLabel: WKInterfaceLabel!
    @IBOutlet weak var table: WKInterfaceTable!

    var titles = [String]()

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

        dataReadonly = true

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
                    titles.append(controller.setRow(PullRequestSection.Mine, "Mine"))
                case PARTICIPATED_INDEX:
                    titles.append(controller.setRow(PullRequestSection.Participated, "Participated"))
                case MERGED_INDEX:
                    titles.append(controller.setRow(PullRequestSection.Merged, "Merged"))
                case CLOSED_INDEX:
                    titles.append(controller.setRow(PullRequestSection.Closed, "Closed"))
                case OTHER_INDEX:
                    titles.append(controller.setRow(PullRequestSection.All, "Others"))
                default: break
                }
            }
        }
    }

    override func willActivate() {
        super.willActivate()
    }

    override func didDeactivate() {
        super.didDeactivate()
    }

    @IBAction func clearMergedSelected() {
        presentControllerWithName("Command Controller", context: "clearAllMerged")
    }

    @IBAction func clearClosedSelected() {
        presentControllerWithName("Command Controller", context: "clearAllClosed")
    }

    @IBAction func markAllReadSelected() {
        presentControllerWithName("Command Controller", context: "markAllRead")
    }

    @IBAction func refreshSelected() {
        presentControllerWithName("Command Controller", context: "refresh")
    }

    override func contextForSegueWithIdentifier(segueIdentifier: String, inTable table: WKInterfaceTable, rowIndex: Int) -> AnyObject? {
        return [ TITLE_KEY: titles[rowIndex], SECTION_KEY: rowIndex+1 ]
    }
}

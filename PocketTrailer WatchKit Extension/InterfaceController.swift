//
//  TopController.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 14/03/2015.
//
//

import WatchKit
import Foundation


class InterfaceController: WKInterfaceController {

    @IBOutlet weak var emptyLabel: WKInterfaceLabel!
    @IBOutlet weak var table: WKInterfaceTable!

    var titles = [String]()

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

        ExtensionGlobals.go()

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

            table.setNumberOfRows(5, withRowType: "TopRow")

            for f in MINE_INDEX...OTHER_INDEX {
                let controller = table.rowControllerAtIndex(f) as TopRow
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

        ExtensionGlobals.done()
    }

    override func willActivate() {
        super.willActivate()
    }

    override func didDeactivate() {
        super.didDeactivate()
    }

    @IBAction func clearMergedSelected() {

    }

    @IBAction func clearClosedSelected() {

    }

    @IBAction func markAllReadSelected() {

    }

    override func contextForSegueWithIdentifier(segueIdentifier: String, inTable table: WKInterfaceTable, rowIndex: Int) -> AnyObject? {
        let controller = table.rowControllerAtIndex(rowIndex) as TopRow
        return [ TITLE_KEY: titles[rowIndex], SECTION_KEY: rowIndex+1 ]
    }
}

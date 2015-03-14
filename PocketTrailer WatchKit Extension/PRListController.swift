//
//  PRListController.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 14/03/2015.
//
//

import WatchKit
import Foundation


class PRListController: WKInterfaceController {

    @IBOutlet weak var emptyLabel: WKInterfaceLabel!
    @IBOutlet weak var table: WKInterfaceTable!

    var prsInSection: [PullRequest]!

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

        let contextData = context as NSDictionary
        setTitle(contextData[TITLE_KEY] as? String)

        let sectionIndex = contextData[SECTION_KEY] as Int

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
        return [ PULL_REQUEST_KEY: prsInSection[rowIndex] ]
    }
}

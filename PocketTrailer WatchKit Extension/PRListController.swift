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

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

        let contextData = context as NSDictionary
        setTitle(contextData[TITLE_KEY] as? String)

        let sectionIndex = contextData[SECTION_KEY] as Int

        ExtensionGlobals.go()

        let f = PullRequest.requestForPullRequestsWithFilter(nil, sectionIndex: sectionIndex)
        let prsInSection = mainObjectContext.executeFetchRequest(f, error: nil) as [PullRequest]

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

        ExtensionGlobals.done()
    }

    override func willActivate() {
        super.willActivate()
    }

    override func didDeactivate() {
        super.didDeactivate()
    }

}

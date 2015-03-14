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

            table.setNumberOfRows(6, withRowType: "TopRow")

            for f in 0..<6 {
                let controller = table.rowControllerAtIndex(f) as TopRow
                switch(f) {
                case 0:
                    controller.setRow(PullRequest.countRequestsInSection(PullRequestSection.Mine.rawValue, moc: mainObjectContext), "Mine")
                case 1:
                    controller.setRow(PullRequest.countRequestsInSection(PullRequestSection.Participated.rawValue, moc: mainObjectContext), "Participated")
                case 2:
                    controller.setRow(PullRequest.countRequestsInSection(PullRequestSection.Merged.rawValue, moc: mainObjectContext), "Merged")
                case 3:
                    controller.setRow(PullRequest.countRequestsInSection(PullRequestSection.Closed.rawValue, moc: mainObjectContext), "Closed")
                case 4:
                    controller.setRow(PullRequest.badgeCountInMoc(mainObjectContext), "Unread")
                case 5:
                    controller.setRow(PullRequest.countRequestsInSection(PullRequestSection.All.rawValue, moc: mainObjectContext), "Others")
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
}

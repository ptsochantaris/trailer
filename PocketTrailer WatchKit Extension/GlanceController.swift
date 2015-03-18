//
//  GlanceController.swift
//  PocketTrailer WatchKit Extension
//
//  Created by Paul Tsochantaris on 11/03/2015.
//
//

import WatchKit
import Foundation
import CoreData

class GlanceController: WKInterfaceController {

    @IBOutlet weak var totalCount: WKInterfaceLabel!
    @IBOutlet weak var myCount: WKInterfaceLabel!
    @IBOutlet weak var mergedCount: WKInterfaceLabel!
    @IBOutlet weak var closedCount: WKInterfaceLabel!
    @IBOutlet weak var participatedCount: WKInterfaceLabel!
    @IBOutlet weak var unreadCount: WKInterfaceLabel!
    @IBOutlet weak var lastUpdate: WKInterfaceLabel!

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

        dataReadonly = true
		Settings.clearCache()

        let totalPrs = PullRequest.countAllRequestsInMoc(mainObjectContext)

        if totalPrs == 0 {

            totalCount.setHidden(true)
            mergedCount.setHidden(true)
            closedCount.setHidden(true)
            participatedCount.setHidden(true)
            unreadCount.setHidden(true)
            lastUpdate.setHidden(true)

            let a = DataManager.reasonForEmptyWithFilter(nil)
            myCount.setAttributedText(a)

        } else {

            totalCount.setHidden(false)
            mergedCount.setHidden(false)
            closedCount.setHidden(false)
            participatedCount.setHidden(false)
            unreadCount.setHidden(false)
            lastUpdate.setHidden(false)

            totalCount.setText(NSString(format: "%d", totalPrs))

            setCountOfLabel(myCount,
                toCount: PullRequest.countRequestsInSection(PullRequestSection.Mine.rawValue, moc: mainObjectContext),
                appending: "MINE")

            setCountOfLabel(participatedCount,
                toCount: PullRequest.countRequestsInSection(PullRequestSection.Participated.rawValue, moc: mainObjectContext),
                appending: "PARTICIPATED")

            setCountOfLabel(mergedCount,
                toCount: PullRequest.countRequestsInSection(PullRequestSection.Merged.rawValue, moc: mainObjectContext),
                appending: "MERGED")

            setCountOfLabel(closedCount,
                toCount: PullRequest.countRequestsInSection(PullRequestSection.Closed.rawValue, moc: mainObjectContext),
                appending: "CLOSED")

            setCountOfLabel(unreadCount,
                toCount: PullRequest.badgeCountInMoc(mainObjectContext),
                appending: "UNREAD COMMENTS")

            if let lastRefresh = Settings.lastSuccessfulRefresh {
                let d = NSDateFormatter()
                d.dateStyle = NSDateFormatterStyle.ShortStyle
                d.timeStyle = NSDateFormatterStyle.ShortStyle
                lastUpdate.setText("Updated "+d.stringFromDate(lastRefresh))
                lastUpdate.setAlpha(0.9)
            } else {
                lastUpdate.setText("Not updated yet")
                lastUpdate.setAlpha(0.4)
            }
        }
    }

    func setCountOfLabel(label: WKInterfaceLabel, toCount: Int, appending: String) {
        if toCount > 0 {
            label.setAlpha(0.9)
            label.setText("\(toCount) \(appending)")
        } else {
            label.setText("0 \(appending)")
            label.setAlpha(0.4)
        }
    }

    override func willActivate() {
        super.willActivate()
    }

    override func didDeactivate() {
        super.didDeactivate()
    }

}

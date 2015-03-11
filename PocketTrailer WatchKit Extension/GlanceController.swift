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

let app = WatchKitGlobals()
let api = app

class GlanceController: WKInterfaceController {

    @IBOutlet weak var totalCount: WKInterfaceLabel!
    @IBOutlet weak var myCount: WKInterfaceLabel!
    @IBOutlet weak var participatedCount: WKInterfaceLabel!
    @IBOutlet weak var unreadCount: WKInterfaceLabel!

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

        totalCount.setText(NSString(format: "%d", PullRequest.countAllRequestsInMoc(mainObjectContext)))
        myCount.setText(NSString(format: "%d MINE", PullRequest.countOwnRequestsInMoc(mainObjectContext)))
        participatedCount.setText(NSString(format: "%d PARTICIPATED", PullRequest.countParticipatedRequestsInMoc(mainObjectContext)))
        unreadCount.setText(NSString(format: "%d UNREAD COMMENTS", PullRequest.badgeCountInMoc(mainObjectContext)))
    }

    override func willActivate() {
        super.willActivate()
    }

    override func didDeactivate() {
        super.didDeactivate()
    }

}

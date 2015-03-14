//
//  PRDetailController.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 14/03/2015.
//
//

import WatchKit
import Foundation


class PRDetailController: WKInterfaceController {

    @IBOutlet weak var table: WKInterfaceTable!

    var pullRequest: PullRequest!

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

        let contextData = context as NSDictionary
        pullRequest = contextData[PULL_REQUEST_KEY] as PullRequest

        self.setTitle(pullRequest.title)
    }

    override func willActivate() {
        super.willActivate()
    }

    override func didDeactivate() {
        super.didDeactivate()
    }

    @IBAction func refreshSelected() {
        presentControllerWithName("Command Controller", context: "refresh")
    }
}

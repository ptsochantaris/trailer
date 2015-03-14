//
//  PRDetailController.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 14/03/2015.
//
//

import WatchKit
import Foundation

let shortDateFormatter = { () -> NSDateFormatter in
    let d = NSDateFormatter()
    d.dateStyle = NSDateFormatterStyle.ShortStyle
    d.timeStyle = NSDateFormatterStyle.ShortStyle
    return d
    }()

class PRDetailController: WKInterfaceController {

    @IBOutlet weak var table: WKInterfaceTable!

    var pullRequest: PullRequest!

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

        let contextData = context as NSDictionary
        pullRequest = contextData[PULL_REQUEST_KEY] as PullRequest

        self.setTitle(pullRequest.title)

        var rowTypes = ["LabelRow"]

        for c in pullRequest.comments.allObjects as [PRComment] {
            rowTypes.append("CommentRow")
        }
        table.setRowTypes(rowTypes)

        (table.rowControllerAtIndex(0) as LabelRow).labelL.setText(pullRequest.body)

        var index = 1
        for c in pullRequest.comments.allObjects as [PRComment] {
            let controller = table.rowControllerAtIndex(index++) as CommentRow
            controller.usernameL.setText((c.userName ?? "(unknown)") + " " + shortDateFormatter.stringFromDate(c.createdAt ?? NSDate()))
            controller.commentL.setText(c.body)
        }
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

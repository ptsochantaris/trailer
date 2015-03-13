//
//  TodayViewController.swift
//  PocketTrailer Today Extension
//
//  Created by Paul Tsochantaris on 13/03/2015.
//
//

import UIKit
import Foundation
import NotificationCenter

let app = ExtensionGlobals()
let api = app

class TodayViewController: UIViewController, NCWidgetProviding {
        
    @IBOutlet weak var label: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        app.go()

        paragraph.paragraphSpacingBefore = 6
        self.update()
    }

    private let paragraph = NSMutableParagraphStyle()

    private var brightAttributes: [NSObject: AnyObject] {
        return [
            NSForegroundColorAttributeName: UIColor.whiteColor(),
            NSParagraphStyleAttributeName: paragraph ]
    }

    private var normalAttributes: [NSObject: AnyObject] {
        return [
            NSForegroundColorAttributeName: UIColor.lightGrayColor(),
            NSParagraphStyleAttributeName: paragraph ]
    }

    private var dimAttributes: [NSObject: AnyObject] {
        return [
            NSForegroundColorAttributeName: UIColor.darkGrayColor(),
            NSParagraphStyleAttributeName: paragraph ]
    }

    private var redAttributes: [NSObject: AnyObject] {
        return [
            NSForegroundColorAttributeName: UIColor.redColor(),
            NSParagraphStyleAttributeName: paragraph ]
    }

    private var smallAttributes: [NSObject: AnyObject] {
        return [
            NSForegroundColorAttributeName: UIColor.lightGrayColor(),
            NSFontAttributeName: UIFont.systemFontOfSize(UIFont.smallSystemFontSize()),
            NSParagraphStyleAttributeName: paragraph ]
    }

    private func update() {
        let a = NSMutableAttributedString(string: NSString(format: "%d Total PRs",
            PullRequest.countAllRequestsInMoc(mainObjectContext)),
            attributes: brightAttributes)

        let colon = NSAttributedString(string: ": ", attributes: normalAttributes)
        a.appendAttributedString(colon)

        append(a,
            toCount: PullRequest.countRequestsInSection(PullRequestSection.Mine.rawValue, moc: mainObjectContext),
            appending: "Mine, ")

        append(a,
            toCount: PullRequest.countRequestsInSection(PullRequestSection.Participated.rawValue, moc: mainObjectContext),
            appending: "Participated, ")

        append(a,
            toCount: PullRequest.countRequestsInSection(PullRequestSection.Merged.rawValue, moc: mainObjectContext),
            appending: "Merged, ")

        append(a,
            toCount: PullRequest.countRequestsInSection(PullRequestSection.Closed.rawValue, moc: mainObjectContext),
            appending: "Closed, ")

        append(a,
            toCount: PullRequest.badgeCountInMoc(mainObjectContext),
            appending: "Unread comments")

        var text: String

        if let lastRefresh = Settings.lastSuccessfulRefresh {
            let d = NSDateFormatter()
            d.dateStyle = NSDateFormatterStyle.ShortStyle
            d.timeStyle = NSDateFormatterStyle.ShortStyle
            text = "\nUpdated " + d.stringFromDate(lastRefresh)
        } else {
            text = "\nNot updated yet"
        }
        a.appendAttributedString(NSAttributedString(string: text, attributes: smallAttributes))
        
        label.attributedText = a
        
        self.view.setNeedsUpdateConstraints()
    }

    func widgetPerformUpdateWithCompletionHandler(completionHandler: ((NCUpdateResult) -> Void)!) {
        // Perform any setup necessary in order to update the view.

        // If an error is encountered, use NCUpdateResult.Failed
        // If there's no update required, use NCUpdateResult.NoData
        // If there's an update, use NCUpdateResult.NewData

        self.update()

        completionHandler(NCUpdateResult.NewData)
    }

    func append(a: NSMutableAttributedString, toCount: Int, appending: String) {
        var text: String
        var attributes: [NSObject: AnyObject]
        if toCount > 0 {
            attributes = normalAttributes
            text = "\(toCount)\u{a0}\(appending)"
        } else {
            attributes = dimAttributes
            text = "0\u{a0}\(appending)"
        }
        a.appendAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}

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

var app: ExtensionGlobals!
var api: ExtensionGlobals!

class TodayViewController: UIViewController, NCWidgetProviding {
        
    @IBOutlet weak var label: UILabel!
    var button: UIButton!

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
            NSForegroundColorAttributeName: UIColor.grayColor(),
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

    override func viewDidLoad() {
        super.viewDidLoad()

        paragraph.paragraphSpacing = 6

        button = UIButton.buttonWithType(UIButtonType.Custom) as UIButton
        button.addTarget(self, action: Selector("tapped"), forControlEvents: UIControlEvents.TouchUpInside)
        button.setBackgroundImage(imageFromColor(UIColor(white: 1.0, alpha: 0.2)), forState: UIControlState.Highlighted)
        self.view.addSubview(button)

        self.update()
    }

    func tapped() {
        self.extensionContext?.openURL(NSURL(string: "pockettrailer://")!, completionHandler: nil)
    }

    override func viewDidLayoutSubviews() {
        label.preferredMaxLayoutWidth = label.frame.size.width
        button.frame = self.view.bounds
    }

    func widgetMarginInsetsForProposedMarginInsets(defaultMarginInsets: UIEdgeInsets) -> UIEdgeInsets {
        return UIEdgeInsetsMake(defaultMarginInsets.top+11, defaultMarginInsets.left+10, defaultMarginInsets.bottom-11, defaultMarginInsets.right+10)
    }

    private func update() {

        ExtensionGlobals.go()

        let totalCount = PullRequest.countAllRequestsInMoc(mainObjectContext)

        let a = NSMutableAttributedString(string: NSString(format: "%d Total PRs", totalCount), attributes: brightAttributes)

        a.appendAttributedString(NSAttributedString(string: ": ", attributes: normalAttributes))

        append(a, toCount: PullRequest.countRequestsInSection(PullRequestSection.Mine.rawValue,         moc: mainObjectContext), appending: "Mine, ")
        append(a, toCount: PullRequest.countRequestsInSection(PullRequestSection.Participated.rawValue, moc: mainObjectContext), appending: "Participated, ")
        append(a, toCount: PullRequest.countRequestsInSection(PullRequestSection.Merged.rawValue,       moc: mainObjectContext), appending: "Merged, ")
        append(a, toCount: PullRequest.countRequestsInSection(PullRequestSection.Closed.rawValue,       moc: mainObjectContext), appending: "Closed, ")

        ////////////////////////////

        var text: String
        var attributes: [NSObject: AnyObject]

        let toCount = PullRequest.badgeCountInMoc(mainObjectContext)
        if toCount > 0 {
            attributes = redAttributes
            text = "\(toCount)\u{a0}unread\u{a0}comments"
        } else {
            attributes = dimAttributes
            text = "No\u{a0}unread\u{a0}comments"
        }
        a.appendAttributedString(NSAttributedString(string: text, attributes: attributes))

        ////////////////////////////

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

        ExtensionGlobals.done()
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

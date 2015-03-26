
import WatchKit
import Foundation
import CoreData

class GlanceController: WKInterfaceController {

    @IBOutlet weak var totalCount: WKInterfaceLabel!
    @IBOutlet weak var myCount: WKInterfaceLabel!
    @IBOutlet weak var mergedCount: WKInterfaceLabel!
    @IBOutlet weak var closedCount: WKInterfaceLabel!
    @IBOutlet weak var participatedCount: WKInterfaceLabel!
	@IBOutlet weak var otherCount: WKInterfaceLabel!
    @IBOutlet weak var unreadCount: WKInterfaceLabel!
    @IBOutlet weak var lastUpdate: WKInterfaceLabel!

	@IBOutlet weak var prIcon: WKInterfaceImage!
	@IBOutlet weak var issueIcon: WKInterfaceImage!

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

        dataReadonly = true
		Settings.clearCache()

		prIcon.setHidden(Settings.showIssuesInGlance)
		issueIcon.setHidden(!Settings.showIssuesInGlance)
		mergedCount.setHidden(Settings.showIssuesInGlance)

		let totalItems = Settings.showIssuesInGlance ? Issue.countAllIssuesInMoc(mainObjectContext) : PullRequest.countAllRequestsInMoc(mainObjectContext)

		for l in [totalCount, mergedCount, closedCount, participatedCount, otherCount, unreadCount, lastUpdate] {
			l.setHidden(totalItems == 0)
		}

        if totalItems == 0 {

			let a = Settings.showIssuesInGlance ? DataManager.reasonForEmptyIssuesWithFilter(nil) : DataManager.reasonForEmptyWithFilter(nil)
            myCount.setAttributedText(a)

        } else {

            totalCount.setText(NSString(format: "%d", totalItems) as String)

			setCountOfLabel(myCount, forSection: PullRequestSection.Mine)
            setCountOfLabel(participatedCount, forSection: PullRequestSection.Participated)
			setCountOfLabel(mergedCount, forSection: PullRequestSection.Merged)
            setCountOfLabel(closedCount, forSection: PullRequestSection.Closed)
			setCountOfLabel(otherCount, forSection: PullRequestSection.All)

			let badgeCount = Settings.showIssuesInGlance ? Issue.badgeCountInMoc(mainObjectContext) : PullRequest.badgeCountInMoc(mainObjectContext)
			if badgeCount == 0 {
				unreadCount.setText("NO UNREAD COMMENTS")
				unreadCount.setAlpha(0.4)
			} else if badgeCount == 1 {
				unreadCount.setText("1 UNREAD COMMENT")
				unreadCount.setAlpha(1.0)
			} else {
				unreadCount.setText("\(badgeCount) UNREAD COMMENTS")
				unreadCount.setAlpha(1.0)
			}

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

	func setCountOfLabel(label: WKInterfaceLabel, forSection: PullRequestSection) {
		let toCount: Int
		if Settings.showIssuesInGlance {
			toCount = Issue.countIssuesInSection(forSection.rawValue, moc: mainObjectContext)
		} else {
			toCount = PullRequest.countRequestsInSection(forSection.rawValue, moc: mainObjectContext)
		}
		let appending = forSection.watchMenuName().uppercaseString
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

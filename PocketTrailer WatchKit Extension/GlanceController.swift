
import WatchKit
import Foundation
import CoreData

final class GlanceController: WKInterfaceController {

    @IBOutlet weak var totalCount: WKInterfaceLabel!

	@IBOutlet weak var myCount: WKInterfaceLabel!
	@IBOutlet weak var myGroup: WKInterfaceGroup!

	@IBOutlet weak var mergedCount: WKInterfaceLabel!
	@IBOutlet weak var mergedGroup: WKInterfaceGroup!

	@IBOutlet weak var closedCount: WKInterfaceLabel!
	@IBOutlet weak var closedGroup: WKInterfaceGroup!

	@IBOutlet weak var participatedCount: WKInterfaceLabel!
	@IBOutlet weak var participatedGroup: WKInterfaceGroup!

	@IBOutlet weak var otherCount: WKInterfaceLabel!
	@IBOutlet weak var otherGroup: WKInterfaceGroup!

	@IBOutlet weak var unreadCount: WKInterfaceLabel!
	@IBOutlet weak var unreadGroup: WKInterfaceGroup!

	@IBOutlet weak var lastUpdate: WKInterfaceLabel!

	@IBOutlet weak var prIcon: WKInterfaceImage!
	@IBOutlet weak var issueIcon: WKInterfaceImage!

	func setCountOfLabel(label: WKInterfaceLabel, forSection: PullRequestSection, group: WKInterfaceGroup) {
		let toCount: Int
		if Settings.showIssuesInGlance {
			toCount = Issue.countIssuesInSection(forSection, moc: mainObjectContext)
		} else {
			toCount = PullRequest.countRequestsInSection(forSection, moc: mainObjectContext)
		}
		let appending = forSection.watchMenuName().uppercaseString
        if toCount > 0 {
            group.setAlpha(1.0)
            label.setText("\(toCount) \(appending)")
        } else {
            label.setText("0 \(appending)")
            group.setAlpha(0.4)
        }
    }

    override func willActivate() {

		dataReadonly = true
		Settings.clearCache()

		let totalItems = Settings.showIssuesInGlance ? Issue.countAllIssuesInMoc(mainObjectContext) : PullRequest.countAllRequestsInMoc(mainObjectContext)

		for l in [closedGroup, participatedGroup, otherGroup, unreadGroup, lastUpdate] {
			l.setHidden(totalItems == 0)
		}
		mergedGroup.setHidden(Settings.showIssuesInGlance || totalItems == 0)
		prIcon.setHidden(Settings.showIssuesInGlance)
		issueIcon.setHidden(!Settings.showIssuesInGlance)

		totalCount.setText("\(totalItems)")

		if totalItems == 0 {

			let a = Settings.showIssuesInGlance ? DataManager.reasonForEmptyIssuesWithFilter(nil) : DataManager.reasonForEmptyWithFilter(nil)
			myCount.setAttributedText(a)
			myGroup.setAlpha(1.0)

		} else {

			setCountOfLabel(myCount, forSection: PullRequestSection.Mine, group: myGroup)
			setCountOfLabel(participatedCount, forSection: PullRequestSection.Participated, group: participatedGroup)
			setCountOfLabel(mergedCount, forSection: PullRequestSection.Merged, group: mergedGroup)
			setCountOfLabel(closedCount, forSection: PullRequestSection.Closed, group: closedGroup)
			setCountOfLabel(otherCount, forSection: PullRequestSection.All, group: otherGroup)

			let badgeCount = Settings.showIssuesInGlance ? Issue.badgeCountInMoc(mainObjectContext) : PullRequest.badgeCountInMoc(mainObjectContext)
			if badgeCount == 0 {
				unreadCount.setText("NONE UNREAD")
				unreadGroup.setAlpha(0.3)
			} else if badgeCount == 1 {
				unreadCount.setText("1 COMMENT")
				unreadGroup.setAlpha(1.0)
			} else {
				unreadCount.setText("\(badgeCount) COMMENTS")
				unreadGroup.setAlpha(1.0)
			}

			if let lastRefresh = Settings.lastSuccessfulRefresh {
				let d = NSDateFormatter()
				d.dateStyle = NSDateFormatterStyle.ShortStyle
				d.timeStyle = NSDateFormatterStyle.ShortStyle
				lastUpdate.setText("Refreshed "+d.stringFromDate(lastRefresh))
				lastUpdate.setAlpha(0.7)
			} else {
				lastUpdate.setText("Not updated yet")
				lastUpdate.setAlpha(0.3)
			}
		}

		super.willActivate()
    }
}

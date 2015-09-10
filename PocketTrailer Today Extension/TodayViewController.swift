
import UIKit
import CoreData
import Foundation
import NotificationCenter

let app = { () -> ExtensionGlobals! in
	Settings.checkMigration()
	DataManager.checkMigration()
	return ExtensionGlobals()
	}()

let api = app

final class ExtensionGlobals {

	var refreshesSinceLastLabelsCheck = [NSManagedObjectID:Int]()
	var refreshesSinceLastStatusCheck = [NSManagedObjectID:Int]()
	var isRefreshing = false
	var preferencesDirty = false
	var lastRepoCheck = never()

	func postNotificationOfType(type: PRNotificationType, forItem: NSManagedObject) {}
	func setMinimumBackgroundFetchInterval(interval: NSTimeInterval) -> Void {}
	func clearAllBadLinks() -> Void {}
	func haveCachedAvatar(path: String, tryLoadAndCallback: (IMAGE_CLASS?, String) -> Void) -> Bool { return false }
	func cachePathForAvatar(u: String) -> (String, String) { return ("", "") }
}

final class TodayViewController: UIViewController, NCWidgetProviding {

	@IBOutlet weak var prLabel: UILabel!
	@IBOutlet weak var issuesLabel: UILabel!
	@IBOutlet weak var updatedLabel: UILabel!

	var prButton: UIButton!
	var issuesButton: UIButton!

	private let paragraph = NSMutableParagraphStyle()

	private var brightAttributes: [String: AnyObject] {
		return [
			NSForegroundColorAttributeName: UIColor.whiteColor(),
			NSFontAttributeName: UIFont.systemFontOfSize(UIFont.systemFontSize()+2.0),
			NSParagraphStyleAttributeName: paragraph ]
	}

	private var normalAttributes: [String: AnyObject] {
		return [
			NSForegroundColorAttributeName: UIColor.lightGrayColor(),
			NSFontAttributeName: UIFont.systemFontOfSize(UIFont.systemFontSize()+2.0),
			NSParagraphStyleAttributeName: paragraph ]
	}

	private var dimAttributes: [String: AnyObject] {
		return [
			NSForegroundColorAttributeName: UIColor.grayColor(),
			NSFontAttributeName: UIFont.systemFontOfSize(UIFont.systemFontSize()+2.0),
			NSParagraphStyleAttributeName: paragraph ]
	}

	private var redAttributes: [String: AnyObject] {
		return [
			NSForegroundColorAttributeName: UIColor.redColor(),
			NSFontAttributeName: UIFont.systemFontOfSize(UIFont.systemFontSize()+2.0),
			NSParagraphStyleAttributeName: paragraph ]
	}

	private var smallAttributes: [String: AnyObject] {
		return [
			NSForegroundColorAttributeName: UIColor.lightGrayColor(),
			NSFontAttributeName: UIFont.systemFontOfSize(UIFont.smallSystemFontSize()),
			NSParagraphStyleAttributeName: paragraph ]
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		paragraph.paragraphSpacing = 4

		prButton = UIButton(type: UIButtonType.Custom)
		prButton.addTarget(self, action: Selector("prTapped"), forControlEvents: UIControlEvents.TouchUpInside)
		prButton.setBackgroundImage(imageFromColor(UIColor(white: 1.0, alpha: 0.2)), forState: UIControlState.Highlighted)
		view.addSubview(prButton)

		issuesButton = UIButton(type: UIButtonType.Custom)
		issuesButton.addTarget(self, action: Selector("issuesTapped"), forControlEvents: UIControlEvents.TouchUpInside)
		issuesButton.setBackgroundImage(imageFromColor(UIColor(white: 1.0, alpha: 0.2)), forState: UIControlState.Highlighted)
		view.addSubview(issuesButton)

		update()
	}

	func prTapped() {
		extensionContext?.openURL(NSURL(string: "pockettrailer://pullRequests")!, completionHandler: nil)
	}

	func issuesTapped() {
		extensionContext?.openURL(NSURL(string: "pockettrailer://issues")!, completionHandler: nil)
	}

	override func viewDidLayoutSubviews() {
		prLabel.preferredMaxLayoutWidth = prLabel.frame.size.width
		prButton.frame = prLabel.frame

		issuesLabel.preferredMaxLayoutWidth = issuesLabel.frame.size.width
		issuesButton.frame = issuesLabel.frame
	}

	private func update() {

		Settings.clearCache()

		let totalCount = PullRequest.countAllRequestsInMoc(mainObjectContext)
		var a = NSMutableAttributedString(string: "\(totalCount) PRs: ", attributes: brightAttributes)
		if totalCount>0 {
			appendPr(a, section: PullRequestSection.Mine)
			appendPr(a, section: PullRequestSection.Participated)
			appendPr(a, section: PullRequestSection.Merged)
			appendPr(a, section: PullRequestSection.Closed)
			appendPr(a, section: PullRequestSection.All)
			appendCommentCount(a, number: PullRequest.badgeCountInMoc(mainObjectContext))
		}
		else
		{
			let reason = DataManager.reasonForEmptyWithFilter(nil).mutableCopy() as! NSMutableAttributedString
			reason.addAttribute(NSParagraphStyleAttributeName, value: paragraph, range: NSMakeRange(0, a.length))
			a.appendAttributedString(reason)
		}
		prLabel.attributedText = a

		if Repo.interestedInIssues() {
			let totalCount = Issue.countAllIssuesInMoc(mainObjectContext)
			a = NSMutableAttributedString(string: "\(totalCount) Issues: ", attributes: brightAttributes)
			if totalCount>0 {
				appendIssue(a, section: PullRequestSection.Mine)
				appendIssue(a, section: PullRequestSection.Participated)
				appendIssue(a, section: PullRequestSection.Merged)
				appendIssue(a, section: PullRequestSection.Closed)
				appendIssue(a, section: PullRequestSection.All)
				appendCommentCount(a, number: Issue.badgeCountInMoc(mainObjectContext))
			}
			else
			{
				let reason = DataManager.reasonForEmptyIssuesWithFilter(nil).mutableCopy() as! NSMutableAttributedString
				reason.addAttribute(NSParagraphStyleAttributeName, value: paragraph, range: NSMakeRange(0, a.length))
				a.appendAttributedString(reason)
			}
			issuesLabel.attributedText = a
		} else {
			issuesLabel.attributedText = nil
		}

		if let lastRefresh = Settings.lastSuccessfulRefresh {
			let d = NSDateFormatter()
			d.dateStyle = NSDateFormatterStyle.ShortStyle
			d.timeStyle = NSDateFormatterStyle.ShortStyle
			updatedLabel.attributedText = NSAttributedString(string: "Updated " + d.stringFromDate(lastRefresh), attributes: smallAttributes)
		} else {
			updatedLabel.attributedText = NSAttributedString(string: "Not updated yet", attributes: smallAttributes)
		}
	}

	func widgetPerformUpdateWithCompletionHandler(completionHandler: ((NCUpdateResult) -> Void)) {
		// Perform any setup necessary in order to update the view.

		// If an error is encountered, use NCUpdateResult.Failed
		// If there's no update required, use NCUpdateResult.NoData
		// If there's an update, use NCUpdateResult.NewData

		update()

		completionHandler(NCUpdateResult.NewData)
	}

	private func appendCommentCount(a: NSMutableAttributedString, number: Int) {
		if number > 1 {
			a.appendAttributedString(NSAttributedString(string: "\(number)\u{a0}unread\u{a0}comments", attributes: redAttributes))
		} else if number == 1 {
			a.appendAttributedString(NSAttributedString(string: "1\u{a0}unread\u{a0}comment", attributes: redAttributes))
		} else {
			a.appendAttributedString(NSAttributedString(string: "No\u{a0}unread\u{a0}comments", attributes: dimAttributes))
		}
	}

	func appendPr(a: NSMutableAttributedString, section: PullRequestSection) {
		let count = PullRequest.countRequestsInSection(section, moc: mainObjectContext)
		if count > 0 {
			let text = "\(count)\u{a0}\(section.watchMenuName()), "
			a.appendAttributedString(NSAttributedString(string: text, attributes: normalAttributes))
		} else {
			let text = "0\u{a0}\(section.watchMenuName()), "
			a.appendAttributedString(NSAttributedString(string: text, attributes: dimAttributes))
		}
	}

	func appendIssue(a: NSMutableAttributedString, section: PullRequestSection) {
		let count = Issue.countIssuesInSection(section, moc: mainObjectContext)
		if count > 0 {
			let text = "\(count)\u{a0}\(section.watchMenuName()), "
			a.appendAttributedString(NSAttributedString(string: text, attributes: normalAttributes))
		} else {
			let text = "0\u{a0}\(section.watchMenuName()), "
			a.appendAttributedString(NSAttributedString(string: text, attributes: dimAttributes))
		}
	}

	////////////////// With many thanks to http://stackoverflow.com/questions/27679096/how-to-determine-the-today-extension-left-margin-properly-in-ios-8

	struct ScreenSize {
		static let SCREEN_WIDTH = UIScreen.mainScreen().bounds.size.width
		static let SCREEN_HEIGHT = UIScreen.mainScreen().bounds.size.height
		static let SCREEN_MAX_LENGTH = max(ScreenSize.SCREEN_WIDTH, ScreenSize.SCREEN_HEIGHT)
		static let SCREEN_MIN_LENGTH = min(ScreenSize.SCREEN_WIDTH, ScreenSize.SCREEN_HEIGHT)
	}

	struct DeviceType {
		static let iPhone4 =  UIDevice.currentDevice().userInterfaceIdiom == .Phone && ScreenSize.SCREEN_MAX_LENGTH < 568.0
		static let iPhone5 = UIDevice.currentDevice().userInterfaceIdiom == .Phone && ScreenSize.SCREEN_MAX_LENGTH == 568.0
		static let iPhone6 = UIDevice.currentDevice().userInterfaceIdiom == .Phone && ScreenSize.SCREEN_MAX_LENGTH == 667.0
		static let iPhone6Plus = UIDevice.currentDevice().userInterfaceIdiom == .Phone && ScreenSize.SCREEN_MAX_LENGTH == 736.0
		static let iPad = UIDevice.currentDevice().userInterfaceIdiom == .Pad
	}

	func widgetMarginInsetsForProposedMarginInsets(defaultMarginInsets: UIEdgeInsets) -> UIEdgeInsets {

		var insets = defaultMarginInsets
		let isPortrait = UIScreen.mainScreen().bounds.size.width < UIScreen.mainScreen().bounds.size.height

		insets.top = 11.0
		insets.right = 10.0
		insets.bottom = 29.0
		if DeviceType.iPhone6Plus { insets.left = isPortrait ? 53.0 : 82.0 }
		else if DeviceType.iPhone6 { insets.left = 49.0 }
		else if DeviceType.iPhone5 { insets.left = 49.0 }
		else if DeviceType.iPhone4 { insets.left = 49.0 }
		else if DeviceType.iPad { insets.left = 58.0 }
		return insets
	}
}

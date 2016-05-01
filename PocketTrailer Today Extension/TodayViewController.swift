
import UIKit
import CoreData
import Foundation
import NotificationCenter

final class TodayViewController: UIViewController, NCWidgetProviding {

	@IBOutlet weak var prLabel: UILabel!
	@IBOutlet weak var issuesLabel: UILabel!
	@IBOutlet weak var updatedLabel: UILabel!

	var prButton: UIButton!
	var issuesButton: UIButton!

	@IBOutlet weak var prImage: UIImageView!
	@IBOutlet weak var issueImage: UIImageView!

	private let paragraph = NSMutableParagraphStyle()

	private var brightAttributes: [String : AnyObject] {
		return [
			NSForegroundColorAttributeName: UIColor.whiteColor(),
			NSFontAttributeName: UIFont.systemFontOfSize(UIFont.systemFontSize()+2.0),
			NSParagraphStyleAttributeName: paragraph ]
	}

	private var normalAttributes: [String : AnyObject] {
		return [
			NSForegroundColorAttributeName: UIColor.lightGrayColor(),
			NSFontAttributeName: UIFont.systemFontOfSize(UIFont.systemFontSize()+2.0),
			NSParagraphStyleAttributeName: paragraph ]
	}

	private var dimAttributes: [String : AnyObject] {
		return [
			NSForegroundColorAttributeName: UIColor.darkGrayColor(),
			NSFontAttributeName: UIFont.systemFontOfSize(UIFont.systemFontSize()+2.0),
			NSParagraphStyleAttributeName: paragraph ]
	}

	private var redAttributes: [String : AnyObject] {
		return [
			NSForegroundColorAttributeName: UIColor.redColor(),
			NSFontAttributeName: UIFont.systemFontOfSize(UIFont.systemFontSize()+2.0),
			NSParagraphStyleAttributeName: paragraph ]
	}

	private var smallAttributes: [String : AnyObject] {
		return [
			NSForegroundColorAttributeName: UIColor.lightGrayColor(),
			NSFontAttributeName: UIFont.systemFontOfSize(UIFont.smallSystemFontSize()),
			NSParagraphStyleAttributeName: paragraph ]
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		prImage.image = UIImage(named: "prsTab")?.imageWithRenderingMode(UIImageRenderingMode.AlwaysTemplate)
		issueImage.image = UIImage(named: "issuesTab")?.imageWithRenderingMode(UIImageRenderingMode.AlwaysTemplate)

		paragraph.paragraphSpacing = 4

		prButton = UIButton(type: UIButtonType.Custom)
		prButton.addTarget(self, action: #selector(TodayViewController.prTapped), forControlEvents: UIControlEvents.TouchUpInside)
		prButton.setBackgroundImage(imageFromColor(UIColor(white: 1.0, alpha: 0.2)), forState: UIControlState.Highlighted)
		view.addSubview(prButton)

		issuesButton = UIButton(type: UIButtonType.Custom)
		issuesButton.addTarget(self, action: #selector(TodayViewController.issuesTapped), forControlEvents: UIControlEvents.TouchUpInside)
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

		updatedLabel.preferredMaxLayoutWidth = updatedLabel.frame.size.width
	}

	private func update() {

		if let overview = NSDictionary(contentsOfURL: (NSFileManager.defaultManager().containerURLForSecurityApplicationGroupIdentifier("group.Trailer")!).URLByAppendingPathComponent("overview.plist")) {

			let prs = overview["prs"] as! [String:AnyObject]
			var totalCount = prs["total"] as! Int
			var a = NSMutableAttributedString(string: "\(totalCount): ", attributes: brightAttributes)
			if totalCount>0 {
				append(a, from: prs, section: .Mine)
				append(a, from: prs, section: .Participated)
				append(a, from: prs, section: .Mentioned)
				append(a, from: prs, section: .Merged)
				append(a, from: prs, section: .Closed)
				append(a, from: prs, section: .All)
				append(a, from: prs, section: .Snoozed)
				appendCommentCount(a, number: prs["unread"] as! Int)
			} else {
				a.appendAttributedString(NSAttributedString(string: prs["error"] as! String, attributes: [NSParagraphStyleAttributeName: paragraph]))
			}
			prLabel.attributedText = a

			let issues = overview["issues"] as! [String:AnyObject]
			totalCount = issues["total"] as! Int
			a = NSMutableAttributedString(string: "\(totalCount): ", attributes: brightAttributes)
			if totalCount>0 {
				append(a, from: issues, section: .Mine)
				append(a, from: issues, section: .Participated)
				append(a, from: issues, section: .Mentioned)
				append(a, from: issues, section: .Closed)
				append(a, from: issues, section: .All)
				append(a, from: issues, section: .Snoozed)
				appendCommentCount(a, number: issues["unread"] as! Int)
			} else {
				a.appendAttributedString(NSAttributedString(string: issues["error"] as! String, attributes: [NSParagraphStyleAttributeName: paragraph]))
			}
			issuesLabel.attributedText = a

			let lastRefresh = overview["lastUpdated"] as! NSDate
			if lastRefresh == NSDate.distantPast() {
				updatedLabel.attributedText = NSAttributedString(string: "Not updated yet", attributes: smallAttributes)
			} else {
				let d = NSDateFormatter()
				d.dateStyle = NSDateFormatterStyle.ShortStyle
				d.timeStyle = NSDateFormatterStyle.ShortStyle
				d.doesRelativeDateFormatting = true
				updatedLabel.attributedText = NSAttributedString(string: "Updated " + d.stringFromDate(lastRefresh), attributes: smallAttributes)
			}
		} else {
			issuesLabel.attributedText = nil
			prLabel.attributedText = NSAttributedString(string: "--", attributes: dimAttributes)
			issuesLabel.attributedText = NSAttributedString(string: "--", attributes: dimAttributes)
			updatedLabel.attributedText = NSAttributedString(string: "Not updated yet", attributes: smallAttributes)
		}
	}

	func widgetPerformUpdateWithCompletionHandler(completionHandler: ((NCUpdateResult) -> Void)) {
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

	func append(a: NSMutableAttributedString, from: [String:AnyObject], section: Section) {
		let count = (from[section.apiName()] as! [String:AnyObject])["total"] as! Int
		if count > 0 {
			let text = "\(count)\u{a0}\(section.watchMenuName()), "
			a.appendAttributedString(NSAttributedString(string: text, attributes: normalAttributes))
		} else {
			let text = "0\u{a0}\(section.watchMenuName()), "
			a.appendAttributedString(NSAttributedString(string: text, attributes: dimAttributes))
		}
	}

	private func imageFromColor(color: UIColor) -> UIImage {
		let rect = CGRectMake(0, 0, 1, 1)
		UIGraphicsBeginImageContext(rect.size)
		let context = UIGraphicsGetCurrentContext()
		CGContextSetFillColorWithColor(context, color.CGColor)
		CGContextFillRect(context, rect)
		let img = UIGraphicsGetImageFromCurrentImageContext()
		UIGraphicsEndImageContext()
		return img
	}

	func widgetMarginInsetsForProposedMarginInsets(defaultMarginInsets: UIEdgeInsets) -> UIEdgeInsets {
		var insets = defaultMarginInsets
		insets.bottom -= 15.0
		return insets
	}
}

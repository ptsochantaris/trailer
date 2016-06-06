
import UIKit
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

		func imageFromColor(color: UIColor) -> UIImage {
			let rect = CGRectMake(0, 0, 1, 1)
			UIGraphicsBeginImageContext(rect.size)
			let context = UIGraphicsGetCurrentContext()
			CGContextSetFillColorWithColor(context, color.CGColor)
			CGContextFillRect(context, rect)
			let img = UIGraphicsGetImageFromCurrentImageContext()
			UIGraphicsEndImageContext()
			return img
		}

		prImage.image = UIImage(named: "prsTab")?.imageWithRenderingMode(UIImageRenderingMode.AlwaysTemplate)
		issueImage.image = UIImage(named: "issuesTab")?.imageWithRenderingMode(UIImageRenderingMode.AlwaysTemplate)

		paragraph.paragraphSpacing = 4

		prButton = UIButton(type: UIButtonType.Custom)
		prButton.addTarget(self, action: #selector(TodayViewController.widgetTapped), forControlEvents: .TouchUpInside)
		prButton.setBackgroundImage(imageFromColor(UIColor(white: 1.0, alpha: 0.2)), forState: .Highlighted)
		view.addSubview(prButton)

		issuesButton = UIButton(type: UIButtonType.Custom)
		issuesButton.addTarget(self, action: #selector(TodayViewController.widgetTapped), forControlEvents: .TouchUpInside)
		issuesButton.setBackgroundImage(imageFromColor(UIColor(white: 1.0, alpha: 0.2)), forState: .Highlighted)
		view.addSubview(issuesButton)

		update()
	}

	func widgetTapped() {
		extensionContext?.openURL(NSURL(string: "pockettrailer://")!, completionHandler: nil)
	}

	override func viewDidLayoutSubviews() {
		prLabel.preferredMaxLayoutWidth = prLabel.frame.size.width
		prButton.frame = prLabel.frame

		issuesLabel.preferredMaxLayoutWidth = issuesLabel.frame.size.width
		issuesButton.frame = issuesLabel.frame

		updatedLabel.preferredMaxLayoutWidth = updatedLabel.frame.size.width
	}

	private func update() {

		func append(a: NSMutableAttributedString, count: Int, section: Section) {
			if count > 0 {
				let text = "\(count)\u{a0}\(section.watchMenuName()), "
				a.appendAttributedString(NSAttributedString(string: text, attributes: normalAttributes))
			}
		}

		func appendCommentCount(a: NSMutableAttributedString, number: Int) {
			if number > 1 {
				a.appendAttributedString(NSAttributedString(string: "\(number)\u{a0}unread\u{a0}comments", attributes: redAttributes))
			} else if number == 1 {
				a.appendAttributedString(NSAttributedString(string: "1\u{a0}unread\u{a0}comment", attributes: redAttributes))
			} else {
				a.appendAttributedString(NSAttributedString(string: "No\u{a0}unread\u{a0}comments", attributes: dimAttributes))
			}
		}

		if let result = NSDictionary(contentsOfURL: (NSFileManager.defaultManager().containerURLForSecurityApplicationGroupIdentifier("group.Trailer")!).URLByAppendingPathComponent("overview.plist")) {

			func writeOutSection(type: String) -> NSAttributedString {
				var totalOpen = 0
				var totalUnread = 0
				var totalMine = 0
				var totalParticipated = 0
				var totalMentioned = 0
				var totalSnoozed = 0
				var totalMerged = 0
				var totalClosed = 0
				var totalOther = 0

				for r in result["views"] as! [[String : AnyObject]] {
					if let v = r[type] as? [String : AnyObject] {
						totalMine += v[Section.Mine.apiName()]?["total"] as? Int ?? 0
						totalParticipated += v[Section.Participated.apiName()]?["total"] as? Int ?? 0
						totalMentioned += v[Section.Mentioned.apiName()]?["total"] as? Int ?? 0
						totalSnoozed += v[Section.Snoozed.apiName()]?["total"] as? Int ?? 0
						totalOther += v[Section.All.apiName()]?["total"] as? Int ?? 0
						totalMerged += v[Section.Merged.apiName()]?["total"] as? Int ?? 0
						totalClosed += v[Section.Closed.apiName()]?["total"] as? Int ?? 0
						totalUnread += v["unread"] as? Int ?? 0
						totalOpen += v["total_open"] as? Int ?? 0
					}
				}

				let totalCount = totalMerged+totalMine+totalParticipated+totalClosed+totalMentioned+totalSnoozed+totalOther
				let a = NSMutableAttributedString(string: "\(totalCount): ", attributes: brightAttributes)
				if totalCount>0 {
					append(a, count: totalMine, section: .Mine)
					append(a, count: totalParticipated, section: .Participated)
					append(a, count: totalMentioned, section: .Mentioned)
					append(a, count: totalMerged, section: .Merged)
					append(a, count: totalClosed, section: .Closed)
					append(a, count: totalOther, section: .All)
					append(a, count: totalSnoozed, section: .Snoozed)
					appendCommentCount(a, number: totalUnread)
				} else {
					a.appendAttributedString(NSAttributedString(string: result["error"] as! String, attributes: [NSParagraphStyleAttributeName: paragraph]))
				}
				return a.copy() as! NSAttributedString
			}

			prLabel.attributedText = writeOutSection("prs")
			issuesLabel.attributedText = writeOutSection("issues")

			let lastRefresh = result["lastUpdated"] as! NSDate
			if lastRefresh == NSDate.distantPast() {
				updatedLabel.attributedText = NSAttributedString(string: "Not updated yet", attributes: smallAttributes)
			} else {
				updatedLabel.attributedText = NSAttributedString(string: "Updated \(shortDateFormatter.stringFromDate(lastRefresh))", attributes: smallAttributes)
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

	func widgetMarginInsetsForProposedMarginInsets(defaultMarginInsets: UIEdgeInsets) -> UIEdgeInsets {
		var insets = defaultMarginInsets
		insets.bottom -= 15.0
		return insets
	}
}

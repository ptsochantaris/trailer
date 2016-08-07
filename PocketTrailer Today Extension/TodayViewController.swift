
import UIKit
import Foundation
import NotificationCenter

final class TodayViewController: UIViewController, NCWidgetProviding {

	@IBOutlet weak var prLabel: UILabel!
	@IBOutlet weak var issuesLabel: UILabel!
	@IBOutlet weak var updatedLabel: UILabel!

	var linkButton: UIButton!

	@IBOutlet weak var prImage: UIImageView!
	@IBOutlet weak var issueImage: UIImageView!

	private let paragraph = NSMutableParagraphStyle()
	private let newOS = ProcessInfo().isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 10, minorVersion: 0, patchVersion: 0))
	private var titleAttributes: [String : AnyObject] {
		return [
			NSForegroundColorAttributeName: newOS ? UIColor.black : UIColor.white,
			NSFontAttributeName: UIFont.systemFont(ofSize: UIFont.systemFontSize+2.0),
			NSParagraphStyleAttributeName: paragraph ]
	}

	private var normalAttributes: [String : AnyObject] {
		return [
			NSForegroundColorAttributeName: UIColor.darkGray,
			NSFontAttributeName: UIFont.systemFont(ofSize: UIFont.systemFontSize+2.0),
			NSParagraphStyleAttributeName: paragraph ]
	}

	private var dimAttributes: [String : AnyObject] {
		return [
			NSForegroundColorAttributeName: UIColor.lightGray,
			NSFontAttributeName: UIFont.systemFont(ofSize: UIFont.systemFontSize+2.0),
			NSParagraphStyleAttributeName: paragraph ]
	}

	private var redAttributes: [String : AnyObject] {
		return [
			NSForegroundColorAttributeName: UIColor.red,
			NSFontAttributeName: UIFont.systemFont(ofSize: UIFont.systemFontSize+2.0),
			NSParagraphStyleAttributeName: paragraph ]
	}

	private var smallAttributes: [String : AnyObject] {
		return [
			NSForegroundColorAttributeName: UIColor.lightGray,
			NSFontAttributeName: UIFont.systemFont(ofSize: UIFont.smallSystemFontSize),
			NSParagraphStyleAttributeName: paragraph ]
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		func imageFromColor(_ color: UIColor) -> UIImage {
			let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
			UIGraphicsBeginImageContext(rect.size)
			let context = UIGraphicsGetCurrentContext()
			context?.setFillColor(color.cgColor)
			context?.fill(rect)
			let img = UIGraphicsGetImageFromCurrentImageContext()
			UIGraphicsEndImageContext()
			return img!
		}

		prImage.image = UIImage(named: "prsTab")?.withRenderingMode(.alwaysTemplate)
		issueImage.image = UIImage(named: "issuesTab")?.withRenderingMode(.alwaysTemplate)

		if newOS {
			prImage.tintColor = UIColor.black
			issueImage.tintColor = UIColor.black
		}

		paragraph.paragraphSpacing = 4

		linkButton = UIButton(type: UIButtonType.custom)
		linkButton.addTarget(self, action: #selector(TodayViewController.widgetTapped), for: .touchUpInside)
		linkButton.setBackgroundImage(imageFromColor(UIColor(white: 1.0, alpha: 0.2)), for: .highlighted)
		view.addSubview(linkButton)

		update()
	}

	func widgetTapped() {
		extensionContext?.open(URL(string: "pockettrailer://")!, completionHandler: nil)
	}

	override func viewDidLayoutSubviews() {
		linkButton.frame = prLabel.frame.union(updatedLabel.frame)
		let H = linkButton.frame.origin.y + linkButton.frame.size.height
		let offset: CGFloat = newOS ? 10 : 0
		preferredContentSize = CGSize(width: view.frame.size.width, height: H + offset)
		super.viewDidLayoutSubviews()
	}

	func widgetMarginInsets(forProposedMarginInsets defaultMarginInsets: UIEdgeInsets) -> UIEdgeInsets {
		if newOS {
			return defaultMarginInsets
		} else {
			var i = defaultMarginInsets
			i.bottom -= 15
			return i
		}
	}

	private func update() {

		func append(_ a: NSMutableAttributedString, count: Int, section: Section) {
			if count > 0 {
				let text = "\(count)\u{a0}\(section.watchMenuName()), "
				a.append(NSAttributedString(string: text, attributes: normalAttributes))
			}
		}

		func appendCommentCount(_ a: NSMutableAttributedString, number: Int) {
			if number > 1 {
				a.append(NSAttributedString(string: "\(number)\u{a0}unread\u{a0}comments", attributes: redAttributes))
			} else if number == 1 {
				a.append(NSAttributedString(string: "1\u{a0}unread\u{a0}comment", attributes: redAttributes))
			} else {
				a.append(NSAttributedString(string: "No\u{a0}unread\u{a0}comments", attributes: dimAttributes))
			}
		}

		if let result = NSDictionary(contentsOf: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Trailer")!.appendingPathComponent("overview.plist")) {

			func writeOutSection(_ type: String) -> NSAttributedString {
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
						totalMine += v[Section.mine.apiName()]?["total"] as? Int ?? 0
						totalParticipated += v[Section.participated.apiName()]?["total"] as? Int ?? 0
						totalMentioned += v[Section.mentioned.apiName()]?["total"] as? Int ?? 0
						totalSnoozed += v[Section.snoozed.apiName()]?["total"] as? Int ?? 0
						totalOther += v[Section.all.apiName()]?["total"] as? Int ?? 0
						totalMerged += v[Section.merged.apiName()]?["total"] as? Int ?? 0
						totalClosed += v[Section.closed.apiName()]?["total"] as? Int ?? 0
						totalUnread += v["unread"] as? Int ?? 0
						totalOpen += v["total_open"] as? Int ?? 0
					}
				}

				let totalCount = totalMerged+totalMine+totalParticipated+totalClosed+totalMentioned+totalSnoozed+totalOther
				let a = NSMutableAttributedString(string: "\(totalCount): ", attributes: titleAttributes)
				if totalCount > 0 {
					append(a, count: totalMine, section: .mine)
					append(a, count: totalParticipated, section: .participated)
					append(a, count: totalMentioned, section: .mentioned)
					append(a, count: totalMerged, section: .merged)
					append(a, count: totalClosed, section: .closed)
					append(a, count: totalOther, section: .all)
					append(a, count: totalSnoozed, section: .snoozed)
					appendCommentCount(a, number: totalUnread)
				} else {
					a.append(NSAttributedString(string: result["error"] as! String, attributes: [NSParagraphStyleAttributeName: paragraph]))
				}
				return a.copy() as! NSAttributedString
			}

			prLabel.attributedText = writeOutSection("prs")
			issuesLabel.attributedText = writeOutSection("issues")

			let lastRefresh = result["lastUpdated"] as! Date
			if lastRefresh == Date.distantPast {
				updatedLabel.attributedText = NSAttributedString(string: "Not updated yet", attributes: smallAttributes)
			} else {
				updatedLabel.attributedText = NSAttributedString(string: "Updated \(shortDateFormatter.string(from: lastRefresh))", attributes: smallAttributes)
			}
		} else {
			issuesLabel.attributedText = nil
			prLabel.attributedText = NSAttributedString(string: "--", attributes: dimAttributes)
			issuesLabel.attributedText = NSAttributedString(string: "--", attributes: dimAttributes)
			updatedLabel.attributedText = NSAttributedString(string: "Not updated yet", attributes: smallAttributes)
		}
	}

	func widgetPerformUpdate(completionHandler: ((NCUpdateResult) -> Void)) {
		update()
		completionHandler(.newData)
	}
}

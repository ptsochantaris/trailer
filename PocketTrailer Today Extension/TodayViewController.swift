
import UIKit
import Foundation
import NotificationCenter

final class TodayViewController: UIViewController, NCWidgetProviding {

	@IBOutlet private weak var prLabel: UILabel!
	@IBOutlet private weak var issuesLabel: UILabel!
	@IBOutlet private weak var updatedLabel: UILabel!
	@IBOutlet private weak var prImage: UIImageView!
	@IBOutlet private weak var issueImage: UIImageView!

	private var linkButton = UIButton(type: .custom)
	private let paragraph = NSMutableParagraphStyle()

	private var titleAttributes: [NSAttributedString.Key : Any] {
		return [
            .foregroundColor: UIColor(named: "strong")!,
			.font: UIFont.systemFont(ofSize: UIFont.systemFontSize + 2),
			.paragraphStyle: paragraph ]
	}

	private var normalAttributes: [NSAttributedString.Key : Any] {
		return [
			.foregroundColor: UIColor(named: "text")!,
			.font: UIFont.systemFont(ofSize: UIFont.systemFontSize + 2),
			.paragraphStyle: paragraph ]
	}

	private var dimAttributes: [NSAttributedString.Key : Any] {
		return [
			.foregroundColor: UIColor(named: "dimText")!,
			.font: UIFont.systemFont(ofSize: UIFont.systemFontSize + 2),
			.paragraphStyle: paragraph ]
	}

	private var redAttributes: [NSAttributedString.Key : Any] {
		return [
			.foregroundColor: UIColor.red,
			.font: UIFont.systemFont(ofSize: UIFont.systemFontSize + 2),
			.paragraphStyle: paragraph ]
	}

	private var smallAttributes: [NSAttributedString.Key : Any] {
		return [
			.foregroundColor: UIColor(named: "dimText")!,
			.font: UIFont.systemFont(ofSize: UIFont.smallSystemFontSize),
			.paragraphStyle: paragraph ]
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		extensionContext?.widgetLargestAvailableDisplayMode = .expanded

		func image(from color: UIColor) -> UIImage {
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

		paragraph.paragraphSpacing = 4

		linkButton.addTarget(self, action: #selector(widgetTapped), for: .touchUpInside)
		linkButton.setBackgroundImage(image(from: UIColor(white: 1.0, alpha: 0.2)), for: .highlighted)
		view.addSubview(linkButton)

		update()
	}

	@objc private func widgetTapped() {
		extensionContext?.open(URL(string: "pockettrailer://")!, completionHandler: nil)
	}

	func widgetActiveDisplayModeDidChange(_ activeDisplayMode: NCWidgetDisplayMode, withMaximumSize maxSize: CGSize) {
		update()
	}

	private func update() {

		func append(_ a: NSMutableAttributedString, count: Int, section: Section) {
			if count > 0 {
				let text = "\(count)\u{a0}\(section.watchMenuName), "
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

			func writeOutSection(_ type: String) -> NSAttributedString? {
				var totalOpen = 0
				var totalUnread = 0
				var totalMine = 0
				var totalParticipated = 0
				var totalMentioned = 0
				var totalSnoozed = 0
				var totalMerged = 0
				var totalClosed = 0
				var totalOther = 0

				for r in result["views"] as! [[AnyHashable : Any]] {
					if let v = r[type] as? [AnyHashable : Any] {
						totalMine += (v[Section.mine.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
						totalParticipated += (v[Section.participated.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
						totalMentioned += (v[Section.mentioned.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
						totalSnoozed += (v[Section.snoozed.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
						totalOther += (v[Section.all.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
						totalMerged += (v[Section.merged.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
						totalClosed += (v[Section.closed.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
						totalUnread += v["unread"] as? Int ?? 0
						totalOpen += v["total_open"] as? Int ?? 0
					}
				}

				let totalCount = totalMerged+totalMine+totalParticipated+totalClosed+totalMentioned+totalSnoozed+totalOther
				let a = NSMutableAttributedString()
				if totalCount > 0 {
					a.append(NSAttributedString(string: "\(totalCount): ", attributes: titleAttributes))
					if extensionContext?.widgetActiveDisplayMode == .compact {
						appendCommentCount(a, number: totalUnread)
					} else {
						append(a, count: totalMine, section: .mine)
						append(a, count: totalParticipated, section: .participated)
						append(a, count: totalMentioned, section: .mentioned)
						append(a, count: totalMerged, section: .merged)
						append(a, count: totalClosed, section: .closed)
						append(a, count: totalOther, section: .all)
						append(a, count: totalSnoozed, section: .snoozed)
						appendCommentCount(a, number: totalUnread)
					}
				} else {
					let e = result["error"] as? String ?? "No items"
					a.append(NSAttributedString(string: e, attributes: titleAttributes))
				}
				return a.copy() as? NSAttributedString
			}
			
			prLabel.attributedText = writeOutSection("prs")
			issuesLabel.attributedText = writeOutSection("issues")
			updatedLabel.attributedText = NSAttributedString(string: agoFormat(prefix: "updated", since: result["lastUpdated"] as? Date).capitalized, attributes: smallAttributes)
		} else {
			issuesLabel.attributedText = nil
			prLabel.attributedText = NSAttributedString(string: "--", attributes: dimAttributes)
			issuesLabel.attributedText = NSAttributedString(string: "--", attributes: dimAttributes)
			updatedLabel.attributedText = NSAttributedString(string: "Not updated yet", attributes: smallAttributes)
		}

	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		linkButton.frame = prLabel.frame.union(updatedLabel.frame)
		let H = linkButton.frame.origin.y + linkButton.frame.size.height
		preferredContentSize = CGSize(width: view.frame.size.width, height: H + 23)
	}

	func widgetPerformUpdate(completionHandler: @escaping (NCUpdateResult) -> Void) {
		update()
		completionHandler(.newData)
	}
}

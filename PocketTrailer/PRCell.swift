
import UIKit

let statusAttributes: [String : AnyObject] = {
	let paragraphStyle = NSMutableParagraphStyle()
	paragraphStyle.paragraphSpacing = 6.0

	return [
		NSFontAttributeName: UIFont(name: "Menlo-Regular", size: 10)!,
		NSParagraphStyleAttributeName: paragraphStyle
	]
}()

final class PRCell: UITableViewCell {

	private let unreadCount = CountLabel(frame: CGRectZero)
	private let readCount = CountLabel(frame: CGRectZero)
	private var failedToLoadImage: String?
	private var waitingForImageInPath: String?

	@IBOutlet weak var _image: UIImageView!
	@IBOutlet weak var _title: UILabel!
	@IBOutlet weak var _description: UILabel!
	@IBOutlet weak var _statuses: UILabel!
	@IBOutlet weak var statusToAvatarDistance: NSLayoutConstraint!
	@IBOutlet weak var statusToDescriptionDistance: NSLayoutConstraint!
	@IBOutlet weak var statusToBottomDistance: NSLayoutConstraint!

	override func awakeFromNib() {

		unreadCount.textColor = UIColor.whiteColor()
		contentView.addSubview(unreadCount)

		readCount.textColor = UIColor.darkGrayColor()
		contentView.addSubview(readCount)

		_image.layer.cornerRadius = 25
		_image.clipsToBounds = true

		let bg = UIView()
		bg.backgroundColor = UIColor(red: 0.82, green: 0.88, blue: 0.97, alpha: 1.0)
		selectedBackgroundView = bg

		contentView.addConstraints([

			NSLayoutConstraint(item: _image,
				attribute: .Leading,
				relatedBy: .Equal,
				toItem: readCount,
				attribute: .Leading,
				multiplier: 1,
				constant: 3),

			NSLayoutConstraint(item: _image,
				attribute: .CenterY,
				relatedBy: .Equal,
				toItem: readCount,
				attribute: .CenterY,
				multiplier: 1,
				constant: -21),

			NSLayoutConstraint(item: _image,
				attribute: .Leading,
				relatedBy: .Equal,
				toItem: unreadCount,
				attribute: .Leading,
				multiplier: 1,
				constant: 3),

			NSLayoutConstraint(item: _image,
				attribute: .CenterY,
				relatedBy: .Equal,
				toItem: unreadCount,
				attribute: .CenterY,
				multiplier: 1,
				constant: 21)
			])

		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(PRCell.networkStateChanged), name: kReachabilityChangedNotification, object: nil)
	}

	func networkStateChanged() {
		atNextEvent(self) { S in
			if let f = S.failedToLoadImage where api.currentNetworkStatus != .NotReachable {
				S.loadImageAtPath(f)
			}
		}
	}

	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}

	func setPullRequest(pullRequest: PullRequest) {

		let muted = pullRequest.muted?.boolValue ?? false

		let detailFont = UIFont.systemFontOfSize(UIFont.smallSystemFontSize())
		_title.attributedText = pullRequest.titleWithFont(_title.font, labelFont: detailFont.fontWithSize(detailFont.pointSize-2), titleColor: UIColor.darkTextColor())
		_description.attributedText = pullRequest.subtitleWithFont(detailFont, lightColor: UIColor.lightGrayColor(), darkColor: UIColor.darkGrayColor())
		setCountsImageAndFade(pullRequest, muted)

		var statusText : NSMutableAttributedString?
		var statusCount = 0
		if Settings.showStatusItems {
			let statusItems = pullRequest.displayedStatuses
			statusCount = statusItems.count
			while statusCount > 0 {
				statusText = NSMutableAttributedString()
				for status in statusItems {
					var lineAttributes = statusAttributes
					lineAttributes[NSForegroundColorAttributeName] = status.colorForDisplay
					statusText?.appendAttributedString(NSAttributedString(string: status.displayText, attributes: lineAttributes))
					statusCount -= 1
					if statusCount > 0 {
						statusText?.appendAttributedString(NSAttributedString(string: "\n", attributes: lineAttributes))
					}
				}
			}
		}
		_statuses.attributedText = statusText

		if let statusString = statusText?.string {
			statusToAvatarDistance.constant = 9.0
			statusToDescriptionDistance.constant = 9.0
			statusToBottomDistance.constant = 3.0
			var title = pullRequest.accessibleTitle()
			if muted {
				title = "(Muted) - \(title)"
			}
			accessibilityLabel = "\(title), \(unreadCount.text) unread comments, \(readCount.text) total comments, \(pullRequest.accessibleSubtitle). \(statusCount) statuses: \(statusString)"
		} else {
			statusToAvatarDistance.constant = 0.0
			statusToDescriptionDistance.constant = 0.0
			statusToBottomDistance.constant = 4.0
			accessibilityLabel = "\(pullRequest.accessibleTitle()), \(unreadCount.text) unread comments, \(readCount.text) total comments, \(pullRequest.accessibleSubtitle)"
		}
	}

	func setIssue(issue: Issue) {

		let muted = issue.muted?.boolValue ?? false

		let detailFont = UIFont.systemFontOfSize(UIFont.smallSystemFontSize())
		_title.attributedText = issue.titleWithFont(_title.font, labelFont: detailFont.fontWithSize(detailFont.pointSize-2), titleColor: UIColor.darkTextColor())
		_description.attributedText = issue.subtitleWithFont(detailFont, lightColor: UIColor.lightGrayColor(), darkColor: UIColor.darkGrayColor())
		_statuses.attributedText = nil

		statusToAvatarDistance.constant = 0.0
		statusToDescriptionDistance.constant = 0.0
		statusToBottomDistance.constant = 4.0

		setCountsImageAndFade(issue, muted)
		var title = issue.accessibleTitle()
		if muted {
			title = "(Muted) - \(title)"
		}
		accessibilityLabel = "\(title), \(unreadCount.text) unread comments, \(readCount.text) total comments, \(issue.accessibleSubtitle)"
	}

	private func setCountsImageAndFade(item: ListableItem, _ muted: Bool) {
		let _commentsTotal = item.totalComments?.integerValue ?? 0
		let _commentsNew = item.unreadComments?.integerValue ?? 0
		let fade = muted || item.isSnoozing

		readCount.text = itemCountFormatter.stringFromNumber(_commentsTotal)
		readCount.hidden = (_commentsTotal == 0)

		unreadCount.hidden = (_commentsNew == 0)
		unreadCount.text = itemCountFormatter.stringFromNumber(_commentsNew)

		let a = fade ? DISABLED_FADE : 1.0
		readCount.alpha = a
		unreadCount.alpha = a
		_image.alpha = a
		_title.alpha = a
		_statuses.alpha = a
		_description.alpha = a

		loadImageAtPath(item.userAvatarUrl)
	}

	private func loadImageAtPath(imagePath: String?) {
		waitingForImageInPath = imagePath
		if let path = imagePath {
			if (!api.haveCachedAvatar(path) { [weak self] image, _ in
				if self?.waitingForImageInPath == path {
					if image != nil {
						// image loaded
						self?._image.image = image
						self?.failedToLoadImage = nil
					} else {
						// load failed / no image
						self?._image.image = UIImage(named: "avatarPlaceHolder")
						self?.failedToLoadImage = imagePath
					}
					self?.waitingForImageInPath = nil
				}
			}) {
				// prepare UI for over-the-network load
				_image.image = UIImage(named: "avatarPlaceHolder")
				failedToLoadImage = nil
			}
		} else {
			failedToLoadImage = nil
		}
	}

	override func setSelected(selected: Bool, animated: Bool) {
		super.setSelected(selected, animated:animated)
		tone()
	}

	override func setHighlighted(highlighted: Bool, animated: Bool) {
		super.setHighlighted(highlighted, animated:animated)
		tone()
	}

	private func tone() {
		unreadCount.backgroundColor = UIColor.redColor()
		readCount.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
	}
}
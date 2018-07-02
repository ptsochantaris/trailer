
import UIKit

let statusAttributes: [NSAttributedStringKey : Any] = {
	let paragraphStyle = NSMutableParagraphStyle()
	paragraphStyle.paragraphSpacing = 6.0
	paragraphStyle.lineSpacing = 1
	paragraphStyle.headIndent = 19

	return [
		NSAttributedStringKey.font: UIFont(name: "Menlo-Regular", size: 10)!,
		NSAttributedStringKey.paragraphStyle: paragraphStyle
	]
}()

final class PRCell: UITableViewCell {

	private let unreadCount = CountLabel(frame: CGRect())
	private let readCount = CountLabel(frame: CGRect())
	private var failedToLoadImage: String?
	private var waitingForImageInPath: String?

	@IBOutlet private weak var _image: UIImageView!
	@IBOutlet private weak var _title: UILabel!
	@IBOutlet private weak var _description: UILabel!
	@IBOutlet private weak var _statuses: UILabel!
	@IBOutlet private weak var statusToAvatarDistance: NSLayoutConstraint!
	@IBOutlet private weak var statusToDescriptionDistance: NSLayoutConstraint!
	@IBOutlet private weak var statusToBottomDistance: NSLayoutConstraint!

	override func awakeFromNib() {

		unreadCount.textColor = .white
		contentView.addSubview(unreadCount)

		readCount.textColor = .darkGray
		contentView.addSubview(readCount)

		_image.layer.cornerRadius = 25
		_image.clipsToBounds = true

		let bg = UIView()
		bg.backgroundColor = UIColor(red: 0.82, green: 0.88, blue: 0.97, alpha: 1.0)
		selectedBackgroundView = bg

		contentView.addConstraints([

			NSLayoutConstraint(item: _image,
			                   attribute: .leading,
			                   relatedBy: .equal,
			                   toItem: readCount,
			                   attribute: .leading,
			                   multiplier: 1,
			                   constant: 3),

			NSLayoutConstraint(item: _image,
			                   attribute: .centerY,
			                   relatedBy: .equal,
			                   toItem: readCount,
			                   attribute: .centerY,
			                   multiplier: 1,
			                   constant: -21),

			NSLayoutConstraint(item: _image,
			                   attribute: .leading,
			                   relatedBy: .equal,
			                   toItem: unreadCount,
			                   attribute: .leading,
			                   multiplier: 1,
			                   constant: 3),

			NSLayoutConstraint(item: _image,
			                   attribute: .centerY,
			                   relatedBy: .equal,
			                   toItem: unreadCount,
			                   attribute: .centerY,
			                   multiplier: 1,
			                   constant: 21)
			])

		NotificationCenter.default.addObserver(self, selector: #selector(networkStateChanged), name: ReachabilityChangedNotification, object: nil)
	}

	@objc private func networkStateChanged() {
		atNextEvent(self) { S in
			if let f = S.failedToLoadImage, API.currentNetworkStatus != .NotReachable {
				S.loadImageAtPath(imagePath: f)
			}
		}
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	func setPullRequest(pullRequest: PullRequest) {


		let detailFont = UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)
		_title.attributedText = pullRequest.title(with: _title.font, labelFont: detailFont.withSize(detailFont.pointSize-2), titleColor: .darkText)
		_description.attributedText = pullRequest.subtitle(with: detailFont, lightColor: .lightGray, darkColor: .darkGray)

		let muted = pullRequest.muted
		setCountsImageAndFade(item: pullRequest, muted: muted)

		var statusText : NSMutableAttributedString?
		var statusCount = 0
		if pullRequest.shouldShowStatuses {
			let statusItems = pullRequest.displayedStatuses
			statusCount = statusItems.count
			while statusCount > 0 {
				statusText = NSMutableAttributedString()
				for status in statusItems {
					var lineAttributes = statusAttributes
					lineAttributes[NSAttributedStringKey.foregroundColor] = status.colorForDisplay
					statusText?.append(NSAttributedString(string: status.displayText, attributes: lineAttributes))
					statusCount -= 1
					if statusCount > 0 {
						statusText?.append(NSAttributedString(string: "\n", attributes: lineAttributes))
					}
				}
			}
		}
		_statuses.attributedText = statusText

		if let statusString = statusText?.string {
			statusToAvatarDistance.constant = 9.0
			statusToDescriptionDistance.constant = 9.0
			statusToBottomDistance.constant = 3.0
			var title = pullRequest.accessibleTitle
			if muted {
				title = "(Muted) - \(title)"
			}
			accessibilityLabel = "\(title), \(S(unreadCount.text)) unread comments, \(S(readCount.text)) total comments, \(pullRequest.accessibleSubtitle). \(statusCount) statuses: \(statusString)"
		} else {
			statusToAvatarDistance.constant = 0.0
			statusToDescriptionDistance.constant = 0.0
			statusToBottomDistance.constant = 4.0
			accessibilityLabel = "\(pullRequest.accessibleTitle), \(S(unreadCount.text)) unread comments, \(S(readCount.text)) total comments, \(pullRequest.accessibleSubtitle)"
		}
	}

	func setIssue(issue: Issue) {

		let detailFont = UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)
		_title.attributedText = issue.title(with: _title.font, labelFont: detailFont.withSize(detailFont.pointSize-2), titleColor: .darkText)
		_description.attributedText = issue.subtitle(with: detailFont, lightColor: .lightGray, darkColor: .darkGray)
		_statuses.attributedText = nil

		statusToAvatarDistance.constant = 0.0
		statusToDescriptionDistance.constant = 0.0
		statusToBottomDistance.constant = 4.0

		let muted = issue.muted
		setCountsImageAndFade(item: issue, muted: muted)
		var title = issue.accessibleTitle
		if muted {
			title = "(Muted) - \(title)"
		}
		accessibilityLabel = "\(title), \(S(unreadCount.text)) unread comments, \(S(readCount.text)) total comments, \(issue.accessibleSubtitle)"
	}

	private func setCountsImageAndFade(item: ListableItem, muted: Bool) {
		let _commentsTotal = Int(item.totalComments)
		let _commentsNew = Int(item.unreadComments)
		let fade = muted || item.isSnoozing

		readCount.text = itemCountFormatter.string(for: _commentsTotal)
		readCount.isHidden = _commentsTotal == 0

		if let p = item as? PullRequest, Settings.markPrsAsUnreadOnNewCommits, p.hasNewCommits {
			unreadCount.isHidden = false
			unreadCount.text = _commentsNew == 0 ? "!" : itemCountFormatter.string(for: _commentsNew)
		} else {
			unreadCount.isHidden = _commentsNew == 0
			unreadCount.text = itemCountFormatter.string(for: _commentsNew)
		}

		let a = fade ? DISABLED_FADE : 1.0
		readCount.alpha = a
		unreadCount.alpha = a
		_image.alpha = a
		_title.alpha = a
		_statuses.alpha = a
		_description.alpha = a

		loadImageAtPath(imagePath: item.userAvatarUrl)
	}

	private func loadImageAtPath(imagePath: String?) {
		waitingForImageInPath = imagePath
		if let path = imagePath {
			if (!API.haveCachedAvatar(from: path) { [weak self] image, _ in
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

	override func setSelected(_ selected: Bool, animated: Bool) {
		super.setSelected(selected, animated: animated)
		tone()
	}

	override func setHighlighted(_ highlighted: Bool, animated: Bool) {
		super.setHighlighted(highlighted, animated: animated)
		tone()
	}

	private func tone() {
		unreadCount.backgroundColor = .red
		readCount.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
	}
}

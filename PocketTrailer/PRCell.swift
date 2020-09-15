
import UIKit

let statusAttributes: [NSAttributedString.Key : Any] = {
	let paragraphStyle = NSMutableParagraphStyle()
	paragraphStyle.paragraphSpacing = 6.0
	paragraphStyle.lineSpacing = 1
	paragraphStyle.headIndent = 19

	return [
		NSAttributedString.Key.font: UIFont(name: "Menlo-Regular", size: 10)!,
		NSAttributedString.Key.paragraphStyle: paragraphStyle
	]
}()

final class PRCell: UITableViewCell {

	private let unreadCount = CountLabel(frame: CGRect())
	private let readCount = CountLabel(frame: CGRect())
	private var failedToLoadImage: String?
	private var waitingForImageInPath: String?

	@IBOutlet private weak var _image: UIImageView!
	@IBOutlet private weak var _title: UILabel!
	@IBOutlet private weak var _labels: UILabel!
    @IBOutlet private weak var _description: UILabel!
	@IBOutlet private weak var _statuses: UILabel!

	override func awakeFromNib() {

		unreadCount.textColor = .white
		contentView.addSubview(unreadCount)

        readCount.textColor = .label
		contentView.addSubview(readCount)

		_image.layer.cornerRadius = 25
		_image.clipsToBounds = true

		contentView.addConstraints([

			NSLayoutConstraint(item: _image!,
			                   attribute: .leading,
			                   relatedBy: .equal,
			                   toItem: readCount,
			                   attribute: .leading,
			                   multiplier: 1,
			                   constant: 3),

			NSLayoutConstraint(item: _image!,
			                   attribute: .centerY,
			                   relatedBy: .equal,
			                   toItem: readCount,
			                   attribute: .centerY,
			                   multiplier: 1,
			                   constant: -21),

			NSLayoutConstraint(item: _image!,
			                   attribute: .leading,
			                   relatedBy: .equal,
			                   toItem: unreadCount,
			                   attribute: .leading,
			                   multiplier: 1,
			                   constant: 3),

			NSLayoutConstraint(item: _image!,
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
        DispatchQueue.main.async { [weak self] in
            guard let S = self else { return }
			if let f = S.failedToLoadImage, API.currentNetworkStatus != .NotReachable {
				S.loadImageAtPath(imagePath: f)
			}
		}
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}
    
    private weak var item: ListableItem?

	func setPullRequest(pullRequest: PullRequest) {
        item = pullRequest
        
        let separator = traitCollection.containsTraits(in: compactTraits) ? "\n" : "   "
        
		let detailFont = _description.font!
        _title.attributedText = pullRequest.title(with: _title.font, labelFont: detailFont, titleColor: UIColor.label, numberColor: UIColor.secondaryLabel)

        let l = pullRequest.labelsAttributedString(labelFont: _labels.font)
        _labels.attributedText = l
        _labels.isHidden = (l?.length ?? 0) == 0

        let sub = pullRequest.subtitle(with: detailFont, lightColor: UIColor.secondaryLabel, darkColor: UIColor.label, separator: separator)
        let r = pullRequest.reviewsAttributedString(labelFont: detailFont)
        if let r = r, r.length > 0 {
            let s = NSMutableAttributedString(attributedString: r)
            s.append(NSAttributedString(string: "\n"))
            s.append(sub)
            _description.attributedText = s
        } else {
            _description.attributedText = sub
        }

		let muted = pullRequest.muted
		setCountsImageAndFade(item: pullRequest, muted: muted)

		var statusText : NSMutableAttributedString?
        var totalStatuses = 0
		if pullRequest.interestedInStatuses {
			let statusItems = pullRequest.displayedStatuses
			var statusCount = statusItems.count
            totalStatuses = statusCount
            var lineAttributes = statusAttributes

            statusText = NSMutableAttributedString()
            for status in statusItems {
                lineAttributes[.foregroundColor] = status.colorForDisplay
                statusText?.append(NSAttributedString(string: status.displayText, attributes: lineAttributes))
                statusCount -= 1
                if statusCount > 0 {
                    statusText?.append(NSAttributedString(string: "\n", attributes: lineAttributes))
                }
            }
		}
		_statuses.attributedText = statusText
        _statuses.isHidden = totalStatuses == 0 

		if totalStatuses > 0, let statusString = statusText?.string {
			var title = pullRequest.accessibleTitle
			if muted {
				title = "(Muted) - \(title)"
			}
			accessibilityLabel = "\(title), \(S(unreadCount.text)) unread comments, \(S(readCount.text)) total comments, \(pullRequest.accessibleSubtitle). \(totalStatuses) statuses: \(statusString)"
		} else {
			accessibilityLabel = "\(pullRequest.accessibleTitle), \(S(unreadCount.text)) unread comments, \(S(readCount.text)) total comments, \(pullRequest.accessibleSubtitle)"
		}
	}

	func setIssue(issue: Issue) {
        item = issue
        
        let separator = traitCollection.containsTraits(in: compactTraits) ? "\n" : "   "

        let detailFont = _description.font!
        _title.attributedText = issue.title(with: _title.font, labelFont: detailFont, titleColor: UIColor.label, numberColor: UIColor.secondaryLabel)

        let l = issue.labelsAttributedString(labelFont: _labels.font)
        _labels.attributedText = l
        _labels.isHidden = (l?.length ?? 0) == 0

        _description.attributedText = issue.subtitle(with: detailFont, lightColor: UIColor.secondaryLabel, darkColor: UIColor.label, separator: separator)

        _statuses.attributedText = nil
        _statuses.isHidden = true

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

		readCount.text = numberFormatter.string(for: _commentsTotal)
		readCount.isHidden = _commentsTotal == 0

		if let p = item as? PullRequest, Settings.markPrsAsUnreadOnNewCommits, p.hasNewCommits {
			unreadCount.isHidden = false
			unreadCount.text = _commentsNew == 0 ? "!" : numberFormatter.string(for: _commentsNew)
		} else {
			unreadCount.isHidden = _commentsNew == 0
			unreadCount.text = numberFormatter.string(for: _commentsNew)
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
		unreadCount.badgeColor = .appRed
        readCount.badgeColor = .systemFill
	}
}

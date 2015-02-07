
import UIKit

let itemCountFormatter = { () -> NSNumberFormatter in
	let f = NSNumberFormatter()
	f.numberStyle = NSNumberFormatterStyle.DecimalStyle
	return f
}()

class PRCell: UITableViewCell {

	private let unreadCount = UILabel(frame: CGRectZero)
	private let readCount = UILabel(frame: CGRectZero)
	private var failedToLoadImage: NSString?
	private var waitingForImageInPath: NSString?
	@IBOutlet var _image: UIImageView!
	@IBOutlet var _title: UILabel!
	@IBOutlet var _description: UILabel!

	override func awakeFromNib() {
		unreadCount.textColor = UIColor.whiteColor()
		unreadCount.textAlignment = NSTextAlignment.Center
		unreadCount.layer.cornerRadius = 8.5
		unreadCount.clipsToBounds = true
		unreadCount.font = UIFont.boldSystemFontOfSize(12)
		unreadCount.hidden = true
		contentView.addSubview(unreadCount)

		readCount.textColor = UIColor.darkGrayColor()
		readCount.textAlignment = NSTextAlignment.Center
		readCount.layer.cornerRadius = 9.0
		readCount.clipsToBounds = true
		readCount.font = UIFont.systemFontOfSize(12)
		readCount.hidden = true
		contentView.addSubview(readCount)
		
		NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("networkStateChanged"), name: kReachabilityChangedNotification, object: nil)
	}

	func networkStateChanged() {
		dispatch_async(dispatch_get_main_queue()) { [weak self] in
			if self!.failedToLoadImage == nil { return }
			if api.currentNetworkStatus != NetworkStatus.NotReachable {
				self!.loadImageAtPath(self!.failedToLoadImage)
			}
		}
	}

	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}

	func setPullRequest(pullRequest: PullRequest) {
		let detailFont = UIFont.systemFontOfSize(UIFont.smallSystemFontSize())
		_title.attributedText = pullRequest.titleWithFont(_title.font, labelFont: detailFont.fontWithSize(detailFont.pointSize-2), titleColor: UIColor.darkTextColor())
		_description.attributedText = pullRequest.subtitleWithFont(detailFont, lightColor: UIColor.lightGrayColor(), darkColor: UIColor.darkGrayColor())

		var _commentsNew = 0
		let _commentsTotal = pullRequest.totalComments?.integerValue ?? 0

		if Settings.showCommentsEverywhere || pullRequest.isMine() || pullRequest.commentedByMe() {
			_commentsNew = pullRequest.unreadComments?.integerValue ?? 0
		}

		readCount.text = itemCountFormatter.stringFromNumber(_commentsTotal)
		let readSize = readCount.sizeThatFits(CGSizeMake(200, 14))
		readCount.frame = CGRectMake(0, 0, readSize.width+10, 17)
		readCount.hidden = (_commentsTotal == 0)

		unreadCount.hidden = (_commentsNew == 0)
		unreadCount.text = itemCountFormatter.stringFromNumber(_commentsNew)
		let unreadSize = unreadCount.sizeThatFits(CGSizeMake(200, 18))
		unreadCount.frame = CGRectMake(0, 0, unreadSize.width+10, 17)

		loadImageAtPath(pullRequest.userAvatarUrl)

		accessibilityLabel = "\(pullRequest.accessibleTitle()), \(unreadCount.text) unread comments, \(readCount.text) total comments, \(pullRequest.accessibleSubtitle())"

		setNeedsLayout()
	}

	private func loadImageAtPath(imagePath: NSString?) {
		waitingForImageInPath = imagePath
		if let path = imagePath {
			if !api.haveCachedAvatar(path, tryLoadAndCallback: { [weak self] image in
				if self!.waitingForImageInPath == path {
					if image != nil {
						// image loaded
						self!._image.image = image
						self!.failedToLoadImage = nil
					} else {
						// load failed / no image
						self!._image.image = UIImage(named: "avatarPlaceHolder")
						self!.failedToLoadImage = imagePath
					}
					self!.waitingForImageInPath = nil
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

	override func layoutSubviews() {
		super.layoutSubviews()

		let topLeft = CGPointMake(_image.frame.origin.x, _image.frame.origin.y)
		unreadCount.center = topLeft
		contentView.bringSubviewToFront(unreadCount)

		let bottomRight = CGPointMake(topLeft.x+_image.frame.size.width, topLeft.y+_image.frame.size.height)
		readCount.center = bottomRight
		contentView.bringSubviewToFront(readCount)
	}

	override func setSelected(selected: Bool, animated: Bool) {
		super.setSelected(selected, animated:animated)
		tone(selected)
	}

	override func setHighlighted(highlighted: Bool, animated: Bool) {
		super.setHighlighted(highlighted, animated:animated)
		tone(highlighted)
	}

	func tone(tone: Bool)
	{
		unreadCount.backgroundColor = UIColor.redColor()
		readCount.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
	}
}
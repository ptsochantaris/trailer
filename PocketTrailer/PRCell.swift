import UIKit

private let statusAttributes: [NSAttributedString.Key: Any] = {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.paragraphSpacing = 6.0
    paragraphStyle.lineSpacing = 1
    paragraphStyle.headIndent = 19

    return [
        NSAttributedString.Key.font: UIFont(name: "Menlo-Regular", size: 10)!,
        NSAttributedString.Key.paragraphStyle: paragraphStyle
    ]
}()

private let closeAttributes = [NSAttributedString.Key.foregroundColor: UIColor.appLabel, NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .footnote)]

final class PRCell: UITableViewCell {
    private let unreadCount = CountLabel(frame: CGRect())
    private let readCount = CountLabel(frame: CGRect())
    private var failedToLoadImage: String?
    private var waitingForImageInPath: String?

    @IBOutlet private var _image: UIImageView!
    @IBOutlet private var _title: UILabel!
    @IBOutlet private var _labels: UILabel!
    @IBOutlet private var _description: UILabel!
    @IBOutlet private var _statuses: UILabel!

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
        Task {
            if let failedToLoadImage, API.currentNetworkStatus != .notReachable {
                loadImageAtPath(imagePath: failedToLoadImage)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private weak var item: ListableItem?

    func setPullRequest(pullRequest: PullRequest, settings: Settings.Cache) {
        item = pullRequest

        let separator = traitCollection.containsTraits(in: compactTraits) ? "\n" : "   "

        let detailFont = _description.font!
        _title.attributedText = pullRequest.title(with: _title.font, labelFont: detailFont, titleColor: UIColor.label, numberColor: UIColor.secondaryLabel, settings: settings)

        let l = pullRequest.labelsAttributedString(labelFont: _labels.font, settings: settings)
        _labels.attributedText = l
        _labels.isHidden = (l?.length ?? 0) == 0

        let sub = pullRequest.subtitle(with: detailFont, lightColor: UIColor.secondaryLabel, darkColor: UIColor.label, separator: separator, settings: settings)

        for issue in pullRequest.closesIssues.sorted(by: { $0.number < $1.number }) {
            sub.insert(NSAttributedString(string: "Closes Issue #\(issue.number)\n", attributes: closeAttributes), at: 0)
        }

        let r = pullRequest.reviewsAttributedString(labelFont: detailFont, settings: settings)
        if let r, r.length > 0 {
            let s = NSMutableAttributedString(attributedString: r)
            s.append(NSAttributedString(string: "\n"))
            s.append(sub)
            _description.attributedText = s
        } else {
            _description.attributedText = sub
        }

        let muted = pullRequest.muted
        setCountsImageAndFade(item: pullRequest, muted: muted, settings: settings)

        var statusText: NSMutableAttributedString?
        var totalStatuses = 0
        if pullRequest.section.shouldListStatuses(settings: settings) {
            let statusItems = pullRequest.displayedStatusLines(settings: settings)
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
            var title = pullRequest.accessibleTitle(settings: settings)
            if muted {
                title = "(Muted) - \(title)"
            }
            accessibilityLabel = "\(title), \(unreadCount.text.orEmpty) unread comments, \(readCount.text.orEmpty) total comments, \(pullRequest.accessibleSubtitle(settings: settings)). \(totalStatuses) statuses: \(statusString)"
        } else {
            accessibilityLabel = "\(pullRequest.accessibleTitle(settings: settings)), \(unreadCount.text.orEmpty) unread comments, \(readCount.text.orEmpty) total comments, \(pullRequest.accessibleSubtitle(settings: settings))"
        }
    }

    func setIssue(issue: Issue, settings: Settings.Cache) {
        item = issue

        let separator = traitCollection.containsTraits(in: compactTraits) ? "\n" : "   "

        let detailFont = _description.font!
        _title.attributedText = issue.title(with: _title.font, labelFont: detailFont, titleColor: UIColor.label, numberColor: UIColor.secondaryLabel, settings: settings)

        let l = issue.labelsAttributedString(labelFont: _labels.font, settings: settings)
        _labels.attributedText = l
        _labels.isHidden = (l?.length ?? 0) == 0

        _description.attributedText = issue.subtitle(with: detailFont, lightColor: UIColor.secondaryLabel, darkColor: UIColor.label, separator: separator, settings: settings)

        _statuses.attributedText = nil
        _statuses.isHidden = true

        let muted = issue.muted
        setCountsImageAndFade(item: issue, muted: muted, settings: settings)
        var title = issue.accessibleTitle(settings: settings)
        if muted {
            title = "(Muted) - \(title)"
        }
        accessibilityLabel = "\(title), \(unreadCount.text.orEmpty) unread comments, \(readCount.text.orEmpty) total comments, \(issue.accessibleSubtitle(settings: settings))"
    }

    private func setCountsImageAndFade(item: ListableItem, muted: Bool, settings: Settings.Cache) {
        let _commentsTotal = Int(item.totalComments)
        let _commentsNew = Int(item.unreadComments)
        let fade = muted || item.isSnoozing

        readCount.text = _commentsTotal.formatted()
        readCount.isHidden = _commentsTotal == 0

        if let p = item.asPr, settings.markPrsAsUnreadOnNewCommits, p.hasNewCommits {
            unreadCount.isHidden = false
            unreadCount.text = _commentsNew == 0 ? "!" : _commentsNew.formatted()
        } else {
            unreadCount.isHidden = _commentsNew == 0
            unreadCount.text = _commentsNew.formatted()
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
        _image.image = .avatarPlaceHolder
        failedToLoadImage = nil
        if let imagePath {
            Task {
                let image = try? await HTTP.avatar(from: imagePath)
                if waitingForImageInPath == imagePath {
                    _image.image = image
                    failedToLoadImage = image == nil ? imagePath : nil
                    waitingForImageInPath = nil
                }
            }
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

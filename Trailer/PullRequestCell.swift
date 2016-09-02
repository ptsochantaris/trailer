
let statusAttributes: [String : Any] = {

	let paragraphStyle = NSMutableParagraphStyle()
	paragraphStyle.headIndent = 92.0

	var a = [String : Any]() // swift bug will crash the app if this is declared as a literal
	a[NSFontAttributeName] = NSFont(name: "Monaco", size: 9)
	a[NSParagraphStyleAttributeName] = paragraphStyle
	return a
}()

final class PullRequestCell: TrailerCell {

	init(pullRequest: PullRequest) {

		super.init(frame: NSZeroRect, item: pullRequest)

		let _commentsNew = pullRequest.unreadComments
		let _commentsTotal = pullRequest.totalComments

		let _title = pullRequest.title(with: titleFont, labelFont: detailFont, titleColor: unselectedTitleColor)
		let _subtitle = pullRequest.subtitle(with: detailFont, lightColor: .gray, darkColor: .darkGray)

		var W = MENU_WIDTH-LEFTPADDING-app.scrollBarWidth

		let showUnpin = (pullRequest.condition != ItemCondition.open.rawValue) || pullRequest.markUnmergeable
		if showUnpin { W -= REMOVE_BUTTON_WIDTH } else { W -= 4.0 }

		let showAvatar = !S(pullRequest.userAvatarUrl).isEmpty && !Settings.hideAvatars
		if showAvatar { W -= AVATAR_SIZE+AVATAR_PADDING } else { W += 4.0 }

		let titleHeight = ceil(_title.boundingRect(with: CGSize(width: W - 4.0, height: .greatestFiniteMagnitude), options: stringDrawingOptions).size.height)
		let subtitleHeight = ceil(_subtitle.boundingRect(with: CGSize(width: W - 4.0, height: .greatestFiniteMagnitude), options: stringDrawingOptions).size.height+4.0)

		var statusRects = [NSRect]()
		var statuses: [PRStatus]?
		var statusLines: [String]?
		var bottom: CGFloat, cellPadding: CGFloat
		var statusBottom = CGFloat(0)

		if Settings.showStatusItems {
			cellPadding = 10
			bottom = ceil(cellPadding * 0.5)
			let S = pullRequest.displayedStatuses
			statusLines = [String]()
			statusLines?.reserveCapacity(S.count)
			statusRects.reserveCapacity(S.count)
			statuses = S
			for s in S.reversed() {
				let text = s.displayText
				let H = ceil(text.boundingRect(with: CGSize(width: W, height: .greatestFiniteMagnitude),
				                               options: stringDrawingOptions,
				                               attributes: statusAttributes).size.height)
				statusRects.append(NSMakeRect(LEFTPADDING, bottom+statusBottom, W, H))
				statusLines?.append(text)
				statusBottom += H
			}
		} else {
			cellPadding = 6.0
			bottom = ceil(cellPadding * 0.5)
		}

		frame = NSMakeRect(0, 0, MENU_WIDTH, titleHeight + subtitleHeight + statusBottom + cellPadding)
		let faded = pullRequest.shouldSkipNotifications
		addCounts(_commentsTotal, _commentsNew, faded)

		var titleRect = NSMakeRect(LEFTPADDING, subtitleHeight + bottom + statusBottom, W, titleHeight)
		var dateRect = NSMakeRect(LEFTPADDING, statusBottom + bottom, W, subtitleHeight)
		var pinRect = NSMakeRect(LEFTPADDING + W, floor((bounds.size.height-24)*0.5), REMOVE_BUTTON_WIDTH-10, 24)

		let shift: CGFloat
		if showAvatar {
			let userImage = AvatarView(
				frame: NSMakeRect(LEFTPADDING, bounds.size.height-AVATAR_SIZE-7.0, AVATAR_SIZE, AVATAR_SIZE),
				url: S(pullRequest.userAvatarUrl))
			if faded { userImage.alphaValue = DISABLED_FADE }
			addSubview(userImage)
			shift = AVATAR_PADDING+AVATAR_SIZE
		} else {
			shift = -4
		}
		pinRect = pinRect.offsetBy(dx: shift, dy: 0)
		dateRect = dateRect.offsetBy(dx: shift, dy: 0)
		titleRect = titleRect.offsetBy(dx: shift, dy: 0)
		statusRects = statusRects.map { $0.offsetBy(dx: shift, dy: 0) }

		if showUnpin {
			if pullRequest.condition == ItemCondition.open.rawValue {
				let unmergeableLabel = CenterTextField(frame: pinRect)
				unmergeableLabel.textColor = .red
				unmergeableLabel.font = NSFont(name: "Menlo-Regular", size: 8.0)
				unmergeableLabel.alignment = .center
				unmergeableLabel.stringValue = "Cannot be merged"
				addSubview(unmergeableLabel)
			}
			else
			{
				let unpin = NSButton(frame: pinRect)
				unpin.title = "Remove"
				unpin.target = self
				unpin.action = #selector(unPinSelected)
				unpin.setButtonType(.momentaryLight)
				unpin.bezelStyle = .roundRect
				unpin.font = NSFont.systemFont(ofSize: 10.0)
				addSubview(unpin)
			}
		}

		title = CenterTextField(frame: titleRect)
		title.attributedStringValue = _title
		addSubview(title)

		let subtitle = CenterTextField(frame: dateRect)
		subtitle.attributedStringValue = _subtitle
		addSubview(subtitle)

		if faded {
			title.alphaValue = DISABLED_FADE
			subtitle.alphaValue = DISABLED_FADE
		}

		if let s = statuses, let lines = statusLines {
			var rectIndex = statusRects.count-1
			for status in s {
				let frame = statusRects[rectIndex]

				let statusLabel = LinkField(frame: frame)
				statusLabel.targetUrl = status.targetUrl
				statusLabel.needsCommand = !Settings.makeStatusItemsSelectable
				statusLabel.attributedStringValue = NSAttributedString(string: lines[rectIndex], attributes: statusAttributes)
				statusLabel.textColor = status.colorForDisplay
				if faded {
					statusLabel.alphaValue = DISABLED_FADE
				}
				addSubview(statusLabel)
				rectIndex -= 1
			}
		}

		updateMenu()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}

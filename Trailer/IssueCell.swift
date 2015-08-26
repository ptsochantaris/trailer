
final class IssueCell: TrailerCell {

	init(issue: Issue) {

		super.init(frame: NSZeroRect)

		dataItemId = issue.objectID
		detailFont = NSFont.menuFontOfSize(10.0)
		titleFont = NSFont.menuFontOfSize(13.0)

		unselectedTitleColor = goneDark ? NSColor.controlHighlightColor() : NSColor.controlTextColor()

		var _commentsNew = 0
		let _commentsTotal = issue.totalComments?.integerValue ?? 0
		let sectionIndex = issue.sectionIndex?.integerValue ?? 0
		if sectionIndex==PullRequestSection.Mine.rawValue || sectionIndex==PullRequestSection.Participated.rawValue || Settings.showCommentsEverywhere {
			_commentsNew = issue.unreadComments?.integerValue ?? 0
		}

		let _title = issue.titleWithFont(titleFont, labelFont: detailFont, titleColor: unselectedTitleColor)
		let _subtitle = issue.subtitleWithFont(detailFont, lightColor: NSColor.grayColor(), darkColor: NSColor.darkGrayColor())

		var W = MENU_WIDTH-LEFTPADDING-app.scrollBarWidth

		let showUnpin = issue.condition?.integerValue != PullRequestCondition.Open.rawValue
		if showUnpin { W -= REMOVE_BUTTON_WIDTH } else { W -= 4.0 }

		let showAvatar = !(issue.userAvatarUrl ?? "").isEmpty && !Settings.hideAvatars
		if showAvatar { W -= AVATAR_SIZE+AVATAR_PADDING } else { W += 4.0 }

		let titleHeight = ceil(_title.boundingRectWithSize(CGSizeMake(W-4.0, CGFloat.max), options: stringDrawingOptions).size.height)
		let subtitleHeight = ceil(_subtitle.boundingRectWithSize(CGSizeMake(W-4.0, CGFloat.max), options: stringDrawingOptions).size.height+4.0)

		var statusRects = [NSValue]()
		let statuses: [PRStatus]? = nil
		var bottom: CGFloat, CELL_PADDING: CGFloat

		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.headIndent = 92.0

		var statusAttributes = [String : AnyObject]()
		statusAttributes[NSFontAttributeName] = NSFont(name: "Monaco", size: 9)
		statusAttributes[NSParagraphStyleAttributeName] = paragraphStyle

		CELL_PADDING = 6.0
		bottom = ceil(CELL_PADDING * 0.5)

		frame = NSMakeRect(0, 0, MENU_WIDTH, titleHeight+subtitleHeight+CELL_PADDING)
		addCounts(_commentsTotal, _commentsNew)

		var titleRect = NSMakeRect(LEFTPADDING, subtitleHeight+bottom, W, titleHeight)
		var dateRect = NSMakeRect(LEFTPADDING, bottom, W, subtitleHeight)
		var pinRect = NSMakeRect(LEFTPADDING+W, floor((bounds.size.height-24)*0.5), REMOVE_BUTTON_WIDTH-10, 24)

		var shift: CGFloat = -4
		if showAvatar {
			let userImage = AvatarView(
				frame: NSMakeRect(LEFTPADDING, bounds.size.height-AVATAR_SIZE-7.0, AVATAR_SIZE, AVATAR_SIZE),
				url: issue.userAvatarUrl ?? "")
			addSubview(userImage)
			shift = AVATAR_PADDING+AVATAR_SIZE
		}
		pinRect = NSOffsetRect(pinRect, shift, 0)
		dateRect = NSOffsetRect(dateRect, shift, 0)
		titleRect = NSOffsetRect(titleRect, shift, 0)
		var replacementRects = [NSValue]()
		for rv in statusRects {
			replacementRects.append(NSValue(rect: CGRectOffset(rv.rectValue, shift, 0)))
		}
		statusRects = replacementRects

		if showUnpin {
			if (issue.condition?.integerValue ?? 0)==PullRequestCondition.Open.rawValue {
				let unmergeableLabel = CenterTextField(frame: pinRect)
				unmergeableLabel.textColor = NSColor.redColor()
				unmergeableLabel.font = NSFont(name: "Monaco", size: 8.0)
				unmergeableLabel.alignment = NSTextAlignment.Center
				unmergeableLabel.stringValue = "Cannot be merged"
				addSubview(unmergeableLabel)
			}
			else
			{
				let unpin = NSButton(frame: pinRect)
				unpin.title = "Remove"
				unpin.target = self
				unpin.action = Selector("unPinSelected")
				unpin.setButtonType(NSButtonType.MomentaryLightButton)
				unpin.bezelStyle = NSBezelStyle.RoundRectBezelStyle
				unpin.font = NSFont.systemFontOfSize(10.0)
				addSubview(unpin)
			}
		}

		title = CenterTextField(frame: titleRect)
		title.attributedStringValue = _title
		addSubview(title)

		let subtitle = CenterTextField(frame: dateRect)
		subtitle.attributedStringValue = _subtitle
		addSubview(subtitle)

		if let s = statuses {
			for count in 0 ..< statusRects.count {
				let frame = statusRects[statusRects.count-count-1].rectValue
				let statusLabel = LinkField(frame: frame)
				let status = s[count]

				statusLabel.targetUrl = status.targetUrl
				statusLabel.needsCommand = !Settings.makeStatusItemsSelectable
				statusLabel.attributedStringValue = NSAttributedString(string: status.displayText(), attributes: statusAttributes)
				statusLabel.textColor = status.colorForDisplay()
				addSubview(statusLabel)
			}
		}

		if let n = issue.number {
			addMenuWithTitle("Issue #\(n)")
		} else {
			addMenuWithTitle("Issue Options")
		}
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}

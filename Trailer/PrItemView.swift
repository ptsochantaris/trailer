
class PrItemView: NSTableCellView {

	var trackingArea: NSTrackingArea!
	var pullRequestId: NSManagedObjectID
	var title: CenterTextField!
	var unselectedTitleColor: COLOR_CLASS
	var detailFont: FONT_CLASS, titleFont: FONT_CLASS

	init(pullRequest: PullRequest) {
		pullRequestId = pullRequest.objectID
		detailFont = NSFont.menuFontOfSize(10.0)
		titleFont = NSFont.menuFontOfSize(13.0)

		let v = app.statusItem.view as StatusItemView
		let goneDark = MenuWindow.usingVibrancy() && v.darkMode
		unselectedTitleColor = goneDark ? COLOR_CLASS.controlHighlightColor() : COLOR_CLASS.controlTextColor()

		super.init(frame: NSZeroRect)
		canDrawSubviewsIntoLayer = true

		var _commentsNew = 0;
		let _commentsTotal = pullRequest.totalComments?.integerValue ?? 0
		let sectionIndex = pullRequest.sectionIndex?.integerValue ?? 0
		if(sectionIndex==PullRequestSection.Mine.rawValue || sectionIndex==PullRequestSection.Participated.rawValue || Settings.showCommentsEverywhere) {
			_commentsNew = pullRequest.unreadComments?.integerValue ?? 0
		}

		let _title = pullRequest.titleWithFont(titleFont, labelFont: detailFont, titleColor: unselectedTitleColor)

		let _subtitle = pullRequest.subtitleWithFont(detailFont,
			lightColor: goneDark ? COLOR_CLASS.lightGrayColor() : COLOR_CLASS.grayColor(),
			darkColor: goneDark ? COLOR_CLASS.grayColor() : COLOR_CLASS.darkGrayColor())

		var W = CGFloat(MENU_WIDTH-LEFTPADDING)-CGFloat(app.scrollBarWidth)
		let showUnpin = (pullRequest.condition?.integerValue != PullRequestCondition.Open.rawValue) || pullRequest.markUnmergeable()
		if(showUnpin) { W -= CGFloat(REMOVE_BUTTON_WIDTH) }
		let showAvatar = (pullRequest.userAvatarUrl?.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) ?? 0) > 0 && !Settings.hideAvatars
		if(showAvatar) { W -= CGFloat(AVATAR_SIZE+AVATAR_PADDING) } else { W += 4.0 }

		let drawingOptions = NSStringDrawingOptions.UsesLineFragmentOrigin | NSStringDrawingOptions.UsesFontLeading
		let titleHeight = ceil(_title.boundingRectWithSize(CGSizeMake(W, CGFloat(FLT_MAX)), options: drawingOptions).size.height)
		let subtitleHeight = ceil(_subtitle.boundingRectWithSize(CGSizeMake(W, CGFloat(FLT_MAX)), options: drawingOptions).size.height+4.0)

		var statusRects = [NSValue]()
		var statuses: [PRStatus]? = nil
		var bottom: CGFloat, CELL_PADDING: CGFloat
		var statusBottom = CGFloat(0)

		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.headIndent = 92.0;

		var statusAttributes = [NSObject:AnyObject]()
		statusAttributes[NSFontAttributeName] = NSFont(name: "Monaco", size: 9)
		statusAttributes[NSParagraphStyleAttributeName] = paragraphStyle

		if(Settings.showStatusItems) {
			CELL_PADDING = 10
			bottom = ceil(CELL_PADDING * 0.5)
			statuses = pullRequest.displayedStatuses()
			for s in statuses! {
				let H = ceil(s.displayText().boundingRectWithSize(CGSizeMake(W, CGFloat(FLT_MAX)),
					options: NSStringDrawingOptions.UsesLineFragmentOrigin|NSStringDrawingOptions.UsesFontLeading,
					attributes: statusAttributes).size.height)
				statusRects.append(NSValue(rect: NSMakeRect(CGFloat(LEFTPADDING), bottom+statusBottom, W, H)))
				statusBottom += H
			}
		} else {
			CELL_PADDING = 6.0
			bottom = ceil(CELL_PADDING * 0.5)
		}

		frame = NSMakeRect(0, 0, CGFloat(MENU_WIDTH), titleHeight+subtitleHeight+statusBottom+CGFloat(CELL_PADDING))
		var titleRect = NSMakeRect(CGFloat(LEFTPADDING), subtitleHeight+bottom+statusBottom, W, titleHeight)
		var dateRect = NSMakeRect(CGFloat(LEFTPADDING), statusBottom+bottom, W, subtitleHeight)
		var pinRect = NSMakeRect(CGFloat(LEFTPADDING)+W, floor((bounds.size.height-24)*0.5), CGFloat(REMOVE_BUTTON_WIDTH-10), 24)

		var shift: CGFloat = -4
		if(showAvatar) {
			let userImage = AvatarView(
				frame: NSMakeRect(CGFloat(LEFTPADDING), (bounds.size.height-CGFloat(AVATAR_SIZE))*0.5, CGFloat(AVATAR_SIZE), CGFloat(AVATAR_SIZE)),
				url: pullRequest.userAvatarUrl ?? "")
			addSubview(userImage)
			shift = CGFloat(AVATAR_PADDING+AVATAR_SIZE)
		}
		pinRect = NSOffsetRect(pinRect, shift, 0)
		dateRect = NSOffsetRect(dateRect, shift, 0)
		titleRect = NSOffsetRect(titleRect, shift, 0)
		var replacementRects = [NSValue]()
		for rv in statusRects {
			replacementRects.append(NSValue(rect: CGRectOffset(rv.rectValue, shift, 0)))
		}
		statusRects = replacementRects

		if(showUnpin) {
			if((pullRequest.condition?.integerValue ?? 0)==PullRequestCondition.Open.rawValue) {
				let unmergeableLabel = CenterTextField(frame: pinRect)
				unmergeableLabel.textColor = COLOR_CLASS.redColor()
				unmergeableLabel.font = NSFont(name: "Monaco", size: 8.0)
				unmergeableLabel.alignment = NSTextAlignment.CenterTextAlignment
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
				statusLabel.textColor = goneDark ? status.colorForDarkDisplay() : status.colorForDisplay()
				addSubview(statusLabel)
			}
		}

		let commentCounts = CommentCounts(frame: NSMakeRect(0, 0, CGFloat(LEFTPADDING), bounds.size.height), unreadCount:_commentsNew, totalCount:_commentsTotal)
		addSubview(commentCounts)

		menu = NSMenu(title: "PR Options")
		let i = menu!.insertItemWithTitle("Copy URL", action: Selector("copyThisPr"), keyEquivalent: "c", atIndex: 0)
		i?.keyEquivalentModifierMask = Int(NSEventModifierFlags.CommandKeyMask.rawValue)
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

	func unPinSelected() {
		app.unPinSelectedFor(associatedPullRequest())
	}

	override func mouseEntered(theEvent: NSEvent?) {
		if(!app.isManuallyScrolling) { selected = true }
	}

	override func mouseExited(theEvent: NSEvent?) {
		selected = false
	}

	var selected: Bool = false {
		didSet {
			var finalColor: COLOR_CLASS = unselectedTitleColor
			if selected {
				app.mainMenu.prTable.selectRowIndexes(NSIndexSet(index: app.mainMenu.prTable.rowForView(self)), byExtendingSelection: false)
				if (app.statusItem.view as StatusItemView).darkMode { finalColor = COLOR_CLASS.darkGrayColor() }
			} else {
				app.mainMenu.prTable.deselectRow(app.mainMenu.prTable.rowForView(self))
			}
			title.attributedStringValue = associatedPullRequest().titleWithFont(titleFont, labelFont: detailFont, titleColor: finalColor)
		}
	}

	func copyThisPr() {
		let p = NSPasteboard.generalPasteboard()
		p.clearContents()
		p.declareTypes([NSStringPboardType], owner: self)
		p.setString(stringForCopy(), forType: NSStringPboardType)
	}

	func associatedPullRequest() -> PullRequest {
		return mainObjectContext.existingObjectWithID(pullRequestId, error: nil) as PullRequest
	}

	func stringForCopy() -> String {
		return associatedPullRequest().webUrl ?? ""
	}

	override func updateTrackingAreas() {
		if trackingArea != nil { removeTrackingArea(trackingArea) }

		trackingArea = NSTrackingArea(rect: bounds,
			options: NSTrackingAreaOptions.MouseEnteredAndExited | NSTrackingAreaOptions.ActiveInKeyWindow,
			owner: self,
			userInfo: nil)

		addTrackingArea(trackingArea)

		let mouseLocation = convertPoint(window?.mouseLocationOutsideOfEventStream ?? NSZeroPoint, fromView: nil)

		if NSPointInRect(mouseLocation, bounds) {
			mouseEntered(nil)
		} else if !selected {
			mouseExited(nil)
		}
	}
}

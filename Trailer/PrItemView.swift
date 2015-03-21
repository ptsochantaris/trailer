
class PrItemView: NSTableCellView {

	private var trackingArea: NSTrackingArea!
	private var pullRequestId: NSManagedObjectID
	private var title: CenterTextField!
	private var unselectedTitleColor: NSColor
	private var detailFont: NSFont, titleFont: NSFont

	init(pullRequest: PullRequest) {
		pullRequestId = pullRequest.objectID
		detailFont = NSFont.menuFontOfSize(10.0)
		titleFont = NSFont.menuFontOfSize(13.0)

		let v = app.prStatusItem.view as StatusItemView
		let goneDark = MenuWindow.usingVibrancy() && v.darkMode
		unselectedTitleColor = goneDark ? NSColor.controlHighlightColor() : NSColor.controlTextColor()

		var _commentsNew = 0
		let _commentsTotal = pullRequest.totalComments?.integerValue ?? 0
		let sectionIndex = pullRequest.sectionIndex?.integerValue ?? 0
		if sectionIndex==PullRequestSection.Mine.rawValue || sectionIndex==PullRequestSection.Participated.rawValue || Settings.showCommentsEverywhere {
			_commentsNew = pullRequest.unreadComments?.integerValue ?? 0
		}

		let _title = pullRequest.titleWithFont(titleFont, labelFont: detailFont, titleColor: unselectedTitleColor)

		let _subtitle = pullRequest.subtitleWithFont(detailFont,
			lightColor: goneDark ? NSColor.lightGrayColor() : NSColor.grayColor(),
			darkColor: goneDark ? NSColor.grayColor() : NSColor.darkGrayColor())

		var W = MENU_WIDTH-LEFTPADDING-app.scrollBarWidth
		let showUnpin = (pullRequest.condition?.integerValue != PullRequestCondition.Open.rawValue) || pullRequest.markUnmergeable()
		if showUnpin { W -= REMOVE_BUTTON_WIDTH }
		let showAvatar = !(pullRequest.userAvatarUrl ?? "").isEmpty && !Settings.hideAvatars
		if showAvatar { W -= AVATAR_SIZE+AVATAR_PADDING } else { W += 4.0 }

		let drawingOptions = stringDrawingOptions
		let titleHeight = ceil(_title.boundingRectWithSize(CGSizeMake(W, CGFloat.max), options: drawingOptions).size.height)
		let subtitleHeight = ceil(_subtitle.boundingRectWithSize(CGSizeMake(W, CGFloat.max), options: drawingOptions).size.height+4.0)

		var statusRects = [NSValue]()
		var statuses: [PRStatus]? = nil
		var bottom: CGFloat, CELL_PADDING: CGFloat
		var statusBottom = CGFloat(0)

		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.headIndent = 92.0

		var statusAttributes = [NSObject:AnyObject]()
		statusAttributes[NSFontAttributeName] = NSFont(name: "Monaco", size: 9)
		statusAttributes[NSParagraphStyleAttributeName] = paragraphStyle

		if Settings.showStatusItems {
			CELL_PADDING = 10
			bottom = ceil(CELL_PADDING * 0.5)
			statuses = pullRequest.displayedStatuses()
			for s in statuses! {
				let H = ceil(s.displayText().boundingRectWithSize(CGSizeMake(W, CGFloat.max),
					options: stringDrawingOptions,
					attributes: statusAttributes).size.height)
				statusRects.append(NSValue(rect: NSMakeRect(LEFTPADDING, bottom+statusBottom, W, H)))
				statusBottom += H
			}
		} else {
			CELL_PADDING = 6.0
			bottom = ceil(CELL_PADDING * 0.5)
		}

		super.init(frame: NSMakeRect(0, 0, MENU_WIDTH, titleHeight+subtitleHeight+statusBottom+CELL_PADDING))
		addCounts(_commentsTotal, _commentsNew, goneDark)

		var titleRect = NSMakeRect(LEFTPADDING, subtitleHeight+bottom+statusBottom, W, titleHeight)
		var dateRect = NSMakeRect(LEFTPADDING, statusBottom+bottom, W, subtitleHeight)
		var pinRect = NSMakeRect(LEFTPADDING+W, floor((bounds.size.height-24)*0.5), REMOVE_BUTTON_WIDTH-10, 24)

		var shift: CGFloat = -4
		if showAvatar {
			let userImage = AvatarView(
				frame: NSMakeRect(LEFTPADDING, (bounds.size.height-AVATAR_SIZE)*0.5, AVATAR_SIZE, AVATAR_SIZE),
				url: pullRequest.userAvatarUrl ?? "")
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
			if (pullRequest.condition?.integerValue ?? 0)==PullRequestCondition.Open.rawValue {
				let unmergeableLabel = CenterTextField(frame: pinRect)
				unmergeableLabel.textColor = NSColor.redColor()
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
		if !app.isManuallyScrolling { selected = true }
	}

	override func mouseExited(theEvent: NSEvent?) {
		selected = false
	}

	var selected: Bool = false {
		didSet {
			var finalColor: NSColor = unselectedTitleColor
			if selected {
				app.prMenu.table.selectRowIndexes(NSIndexSet(index: app.prMenu.table.rowForView(self)), byExtendingSelection: false)
				if (app.prStatusItem.view as StatusItemView).darkMode { finalColor = NSColor.darkGrayColor() }
			} else {
				app.prMenu.table.deselectRow(app.prMenu.table.rowForView(self))
			}
			title.attributedStringValue = associatedPullRequest().titleWithFont(titleFont, labelFont: detailFont, titleColor: finalColor)
			highlight(selected)
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

	//////////////////////////// Counts

	private var countBackground: FilledView?
	private var newBackground: FilledView?
	private var countView: CenterTextField?
	private var countColor: NSColor?

	private func addCounts(totalCount: Int, _ unreadCount: Int, _ goneDark: Bool) {

		if totalCount == 0 {
			return
		}

		let pCenter = NSMutableParagraphStyle()
		pCenter.alignment = NSTextAlignment.CenterTextAlignment

		countColor = goneDark ? NSColor.controlLightHighlightColor() : NSColor.controlTextColor()

		let countString = NSAttributedString(string: itemCountFormatter.stringFromNumber(totalCount)!, attributes: [
			NSFontAttributeName: NSFont.menuFontOfSize(11),
			NSForegroundColorAttributeName: countColor!,
			NSParagraphStyleAttributeName: pCenter])

		var width = max(BASE_BADGE_SIZE, countString.size.width+10)
		var height = BASE_BADGE_SIZE
		var bottom = (bounds.size.height-height)*0.5
		var left = (LEFTPADDING-width)*0.5

		let c = FilledView(frame: NSIntegralRect(NSMakeRect(left, bottom, width, height)))
		c.cornerRadius = 4.0

		countView = CenterTextField(frame: c.bounds)
        countView?.vibrant = false
		countView!.attributedStringValue = countString
		c.addSubview(countView!)
		addSubview(c)

		countBackground = c

		if unreadCount > 0 {

			let alertString = NSAttributedString(string: itemCountFormatter.stringFromNumber(unreadCount)!, attributes: [
				NSFontAttributeName: NSFont.menuFontOfSize(8),
				NSForegroundColorAttributeName: NSColor.whiteColor(),
				NSParagraphStyleAttributeName: pCenter])

			bottom += height
			width = max(SMALL_BADGE_SIZE, alertString.size.width+8)
			height = SMALL_BADGE_SIZE
			bottom -= height * 0.5 + 1
			left -= width * 0.5

			let cc = FilledView(frame: NSIntegralRect(NSMakeRect(left, bottom, width, height)))
			cc.cornerRadius = floor(SMALL_BADGE_SIZE*0.5)

			let alertCount = CenterTextField(frame: cc.bounds)
            alertCount.vibrant = false
			alertCount.attributedStringValue = alertString
			cc.addSubview(alertCount)
			addSubview(cc)

			newBackground = cc;
		}

		highlight(false)
	}

	private func highlight(on: Bool) -> Void {
		if let c = countBackground {
			var color: NSColor
			if MenuWindow.usingVibrancy() && (app.prStatusItem.view as StatusItemView).darkMode {
				color = on ? NSColor.blackColor() : MAKECOLOR(0.94, 0.94, 0.94, 1.0)
				c.borderColor = color
				newBackground?.backgroundColor = MAKECOLOR(1.0, 0.1, 0.1, 1.0)
			} else {
				color = countColor!
				c.backgroundColor = MAKECOLOR(0.94, 0.94, 0.94, 1.0)
				newBackground?.backgroundColor = MAKECOLOR(1.0, 0.4, 0.4, 1.0)
			}
			if let a = countView?.attributedStringValue.mutableCopy() as? NSMutableAttributedString {
				a.addAttribute(NSForegroundColorAttributeName, value: color, range: NSMakeRange(0, a.length))
				countView?.attributedStringValue = a
			}
		}
	}
}

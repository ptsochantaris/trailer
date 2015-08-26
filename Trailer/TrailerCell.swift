
class TrailerCell: NSTableCellView {

	var trackingArea: NSTrackingArea!
	var dataItemId: NSManagedObjectID!
	var title: CenterTextField!
	var unselectedTitleColor: NSColor!
	var detailFont: NSFont!, titleFont: NSFont!

	var goneDark: Bool {
		return MenuWindow.usingVibrancy() && app.darkMode
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func unPinSelected() {
		app.unPinSelectedFor(associatedDataItem())
	}

	override func mouseEntered(theEvent: NSEvent?) {
		if !app.isManuallyScrolling { selected = true }
	}

	override func mouseExited(theEvent: NSEvent?) {
		selected = false
	}

	var selected: Bool = false {
		didSet {

			let table = app.prMenu.visible ? app.prMenu.table : app.issuesMenu.table

			var finalColor: NSColor = unselectedTitleColor
			if selected {
				table.selectRowIndexes(NSIndexSet(index: table.rowForView(self)), byExtendingSelection: false)
				if goneDark { finalColor = NSColor.darkGrayColor() }
			} else {
				table.deselectRow(table.rowForView(self))
			}

			let item = associatedDataItem()
			if let pr = item as? PullRequest {
				title.attributedStringValue = pr.titleWithFont(titleFont, labelFont: detailFont, titleColor: finalColor)
			} else if let issue = item as? Issue {
				title.attributedStringValue = issue.titleWithFont(titleFont, labelFont: detailFont, titleColor: finalColor)
			}
			highlight(selected)
		}
	}

    func openRepo() {
        if let u = associatedDataItem().repo.webUrl, url = NSURL(string: u) {
            NSWorkspace.sharedWorkspace().openURL(url)
        }
    }

	func copyToClipboard() {
		let p = NSPasteboard.generalPasteboard()
		p.clearContents()
		p.declareTypes([NSStringPboardType], owner: self)
		if let s = associatedDataItem().webUrl {
			p.setString(s, forType: NSStringPboardType)
		}
	}

	func copyNumberToClipboard() {
		let p = NSPasteboard.generalPasteboard()
		p.clearContents()
		p.declareTypes([NSStringPboardType], owner: self)
		if let s = associatedDataItem().number {
			p.setString("#\(s)", forType: NSStringPboardType)
		}
	}

	func addMenuWithTitle(title: String) {
        menu = NSMenu(title: title)
		menu!.insertItemWithTitle(title, action: Selector("copyNumberToClipboard"), keyEquivalent: "", atIndex: 0)
		menu!.insertItem(NSMenuItem.separatorItem(), atIndex: 1)
        let c = menu!.insertItemWithTitle("Copy URL", action: Selector("copyToClipboard"), keyEquivalent: "c", atIndex: 2)
        c?.keyEquivalentModifierMask = Int(NSEventModifierFlags.CommandKeyMask.rawValue)
        menu!.insertItemWithTitle("Open Repo", action: Selector("openRepo"), keyEquivalent: "", atIndex: 3)
    }

	func associatedDataItem() -> ListableItem {
		return existingObjectWithID(dataItemId) as! ListableItem
	}

	override func updateTrackingAreas() {
		if trackingArea != nil { removeTrackingArea(trackingArea) }

		trackingArea = NSTrackingArea(rect: bounds,
			options: [NSTrackingAreaOptions.MouseEnteredAndExited, NSTrackingAreaOptions.ActiveInKeyWindow],
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

	func addCounts(totalCount: Int, _ unreadCount: Int) {

		if totalCount == 0 {
			return
		}

		let pCenter = NSMutableParagraphStyle()
		pCenter.alignment = NSTextAlignment.Center

		let countString = NSAttributedString(string: itemCountFormatter.stringFromNumber(totalCount)!, attributes: [
			NSFontAttributeName: NSFont.menuFontOfSize(11),
			NSForegroundColorAttributeName: goneDark ? NSColor.controlLightHighlightColor() : NSColor.controlTextColor(),
			NSParagraphStyleAttributeName: pCenter])

		var width = max(BASE_BADGE_SIZE, countString.size().width+10)
		var height = BASE_BADGE_SIZE
		var bottom = bounds.size.height-height-10.0
		var left = (LEFTPADDING-width)*0.5

		let c = FilledView(frame: NSIntegralRect(NSMakeRect(left, bottom, width, height)))
		c.cornerRadius = floor(height/2.0)

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
			width = max(SMALL_BADGE_SIZE, alertString.size().width+8.0)
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

	private func highlight(on: Bool) {
		if let c = countBackground {
			var color: NSColor
			if goneDark {
				color = on ? NSColor.blackColor() : MAKECOLOR(0.94, 0.94, 0.94, 1.0)
				c.backgroundColor = on ? NSColor.whiteColor().colorWithAlphaComponent(0.3) : NSColor.blackColor().colorWithAlphaComponent(0.2)
				newBackground?.backgroundColor = MAKECOLOR(1.0, 0.1, 0.1, 1.0)
			} else {
				color = goneDark ? NSColor.controlLightHighlightColor() : NSColor.controlTextColor()
				c.backgroundColor = MAKECOLOR(0.92, 0.92, 0.92, 1.0)
				newBackground?.backgroundColor = MAKECOLOR(1.0, 0.4, 0.4, 1.0)
			}
			if let a = countView?.attributedStringValue.mutableCopy() as? NSMutableAttributedString {
				a.addAttribute(NSForegroundColorAttributeName, value: color, range: NSMakeRange(0, a.length))
				countView?.attributedStringValue = a
			}
		}
	}
}

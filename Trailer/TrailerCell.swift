
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
		if let i = associatedDataItem() {
			app.unPinSelectedFor(i)
		}
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
        if let u = associatedDataItem()?.repo.webUrl, url = NSURL(string: u) {
            NSWorkspace.sharedWorkspace().openURL(url)
        }
    }

	func copyToClipboard() {
		if let s = associatedDataItem()?.webUrl {
			let p = NSPasteboard.generalPasteboard()
			p.clearContents()
			p.declareTypes([NSStringPboardType], owner: self)
			p.setString(s, forType: NSStringPboardType)
		}
	}

	func copyNumberToClipboard() {
		if let s = associatedDataItem()?.number {
			let p = NSPasteboard.generalPasteboard()
			p.clearContents()
			p.declareTypes([NSStringPboardType], owner: self)
			p.setString("#\(s)", forType: NSStringPboardType)
		}
	}

	func updateMenu() {

		guard let item = associatedDataItem() else {
			menu = nil
			return
		}

		let title: String
		let muted = item.muted?.boolValue ?? false
		if let n = item.number {
			if item is PullRequest {
				title = muted ? "PR #\(n) (muted)" : "PR #\(n)"
			} else {
				title = muted ? "Issue #\(n) (muted)" : "Issue #\(n)"
			}
		} else {
			title = "PR Options"
		}

        let m = NSMenu(title: title)
		m.addItemWithTitle(title, action: #selector(TrailerCell.copyNumberToClipboard), keyEquivalent: "")
		m.addItem(NSMenuItem.separatorItem())
		
		if let c = m.addItemWithTitle("Copy URL", action: #selector(TrailerCell.copyToClipboard), keyEquivalent: "c") {
			c.keyEquivalentModifierMask = Int(NSEventModifierFlags.CommandKeyMask.rawValue)
		}

		if let c = m.addItemWithTitle("Open Repo", action: #selector(TrailerCell.openRepo), keyEquivalent: "o") {
			c.keyEquivalentModifierMask = Int(NSEventModifierFlags.CommandKeyMask.rawValue)
		}

		if muted {
			if let c = m.addItemWithTitle("Un-Mute", action: #selector(TrailerCell.unMuteSelected), keyEquivalent: "m") {
				c.keyEquivalentModifierMask = Int(NSEventModifierFlags.CommandKeyMask.rawValue)
			}
		} else {
			if let c = m.addItemWithTitle("Mute", action: #selector(TrailerCell.muteSelected), keyEquivalent: "m") {
				c.keyEquivalentModifierMask = Int(NSEventModifierFlags.CommandKeyMask.rawValue)
			}
		}

		if item.unreadComments?.integerValue > 0 {
			if let c = m.addItemWithTitle("Mark as read", action: #selector(TrailerCell.markReadSelected), keyEquivalent: "a") {
				c.keyEquivalentModifierMask = Int(NSEventModifierFlags.CommandKeyMask.rawValue)
			}
		} else {
			if let c = m.addItemWithTitle("Mark as unread", action: #selector(TrailerCell.markUnreadSelected), keyEquivalent: "a") {
				c.keyEquivalentModifierMask = Int(NSEventModifierFlags.CommandKeyMask.rawValue)
			}
		}

		if let s = item.sectionIndex?.integerValue, section = Section(rawValue: s) where !(section == .Closed || section == .Merged) {
			if let snooze = item.snoozeUntil {
				let title: String
				if snooze == NSDate.distantFuture() {
					title = String(format: "Wake")
				} else {
					title = String(format: "Wake (auto: %@)", itemDateFormatter.stringFromDate(snooze))
				}
				if let c = m.addItemWithTitle(title, action: #selector(TrailerCell.wakeUpSelected), keyEquivalent: "s") {
					c.keyEquivalentModifierMask = Int(NSEventModifierFlags.CommandKeyMask.rawValue)
				}
			} else {
				let snoozeItems = SnoozePreset.allSnoozePresetsInMoc(mainObjectContext)
				if snoozeItems.count > 0 {
					if let c = m.addItemWithTitle("Snooze...", action: nil, keyEquivalent: "") {
						let s = NSMenu(title: "Snooze")
						for i in snoozeItems {
							if let smi = s.addItemWithTitle(i.listDescription(), action: #selector(TrailerCell.snoozeSelected(_:)), keyEquivalent: "") {
								smi.representedObject = i.objectID
							}
						}
						s.addItemWithTitle("Configure...", action: #selector(TrailerCell.snoozeConfigSelected), keyEquivalent: "")
						c.submenu = s
					}
				}
			}
		}

		menu = m
    }

	func snoozeConfigSelected() {
		app.showPreferencesWindow(6)
	}

	func snoozeSelected(sender: NSMenuItem) {
		if let item = associatedDataItem(), oid = sender.representedObject as? NSManagedObjectID, snoozeItem = existingObjectWithID(oid) as? SnoozePreset {
			item.snoozeUntil = snoozeItem.wakeupDateFromNow()
			item.postProcess()
			saveAndRequestMenuUpdate(item)
		}
	}

	func wakeUpSelected() {
		if let item = associatedDataItem() {
			item.snoozeUntil = nil
			item.postProcess()
			saveAndRequestMenuUpdate(item)
		}
	}

	func markReadSelected() {
		if let item = associatedDataItem() {
			item.catchUpWithComments()
			saveAndRequestMenuUpdate(item)
		}
	}

	func markUnreadSelected() {
		if let item = associatedDataItem() {
			item.latestReadCommentDate = never()
			item.postProcess()
			saveAndRequestMenuUpdate(item)
		}
	}

	func muteSelected() {
		if let item = associatedDataItem() {
			item.setMute(true)
			saveAndRequestMenuUpdate(item)
		}
	}

	func unMuteSelected() {
		if let item = associatedDataItem() {
			item.setMute(false)
			saveAndRequestMenuUpdate(item)
		}
	}

	private func saveAndRequestMenuUpdate(item: ListableItem) {
		DataManager.saveDB()
		if item is PullRequest {
			app.updatePrMenu()
		} else {
			app.updateIssuesMenu()
		}
	}

	func associatedDataItem() -> ListableItem? {
		return existingObjectWithID(dataItemId) as? ListableItem
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

	func addCounts(totalCount: Int, _ unreadCount: Int, _ faded: Bool) {

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
        countView!.vibrant = false
		countView!.attributedStringValue = countString
		if faded { countView!.alphaValue = DISABLED_FADE }
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
			if faded { alertCount.alphaValue = DISABLED_FADE }
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

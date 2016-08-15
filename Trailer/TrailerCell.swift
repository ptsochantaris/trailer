
class TrailerCell: NSTableCellView {

	var trackingArea: NSTrackingArea!
	var dataItemId: NSManagedObjectID!
	var title: CenterTextField!
	var unselectedTitleColor: NSColor!
	var detailFont: NSFont!, titleFont: NSFont!

	var goneDark: Bool {
		return MenuWindow.isUsingVibrancy && app.darkMode
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func unPinSelected() {
		if let i = associatedDataItem {
			app.unPinSelected(for: i)
		}
	}

	override func mouseEntered(with theEvent: NSEvent?) {
		if !app.isManuallyScrolling { selected = true }
	}

	override func mouseExited(with theEvent: NSEvent?) {
		selected = false
	}

	var selected = false {
		didSet {

			guard let table = app.visibleWindow?.table else { return }

			var finalColor: NSColor = unselectedTitleColor
			if selected {
				table.selectRowIndexes(IndexSet(integer: table.row(for: self)), byExtendingSelection: false)
				if goneDark { finalColor = .darkGray }
			} else {
				table.deselectRow(table.row(for: self))
			}

			let item = associatedDataItem
			if let pr = item as? PullRequest {
				title.attributedStringValue = pr.title(with: titleFont, labelFont: detailFont, titleColor: finalColor)
			} else if let issue = item as? Issue {
				title.attributedStringValue = issue.title(with: titleFont, labelFont: detailFont, titleColor: finalColor)
			}
			highlight(selected)
		}
	}

    func openRepo() {
        if let u = associatedDataItem?.repo.webUrl, let url = URL(string: u) {
            NSWorkspace.shared().open(url)
        }
    }

	func copyToClipboard() {
		if let s = associatedDataItem?.webUrl {
			let p = NSPasteboard.general()
			p.clearContents()
			p.declareTypes([NSStringPboardType], owner: self)
			p.setString(s, forType: NSStringPboardType)
		}
	}

	func copyNumberToClipboard() {
		if let s = associatedDataItem?.number {
			let p = NSPasteboard.general()
			p.clearContents()
			p.declareTypes([NSStringPboardType], owner: self)
			p.setString("#\(s)", forType: NSStringPboardType)
		}
	}

	func updateMenu() {

		guard let item = associatedDataItem else {
			menu = nil
			return
		}

		let title: String
		let muted = item.muted
		let n = item.number
		if item is PullRequest {
			title = muted ? "PR #\(n) (muted)" : "PR #\(n)"
		} else {
			title = muted ? "Issue #\(n) (muted)" : "Issue #\(n)"
		}

        let m = NSMenu(title: title)
		m.addItem(withTitle: title, action: #selector(copyNumberToClipboard), keyEquivalent: "")
		m.addItem(NSMenuItem.separator())
		
		let c1 = m.addItem(withTitle: "Copy URL", action: #selector(copyToClipboard), keyEquivalent: "c")
		c1.keyEquivalentModifierMask = [.command]

		let c2 = m.addItem(withTitle: "Open Repo", action: #selector(openRepo), keyEquivalent: "o")
		c2.keyEquivalentModifierMask = [.command]

		if item.snoozeUntil == nil {
			if item.unreadComments > 0 {
				let c = m.addItem(withTitle: "Mark as read", action: #selector(markReadSelected), keyEquivalent: "a")
				c.keyEquivalentModifierMask = [.command]
			} else {
				let c = m.addItem(withTitle: "Mark as unread", action: #selector(markUnreadSelected), keyEquivalent: "a")
				c.keyEquivalentModifierMask = [.command]
			}
		}

		if let section = Section(item.sectionIndex), !(section == .closed || section == .merged) {

			if let snooze = item.snoozeUntil {
				let title: String
				if snooze == .distantFuture {
					title = String(format: "Wake")
				} else {
					title = String(format: "Wake (auto: %@)", itemDateFormatter.string(from: snooze))
				}
				let c = m.addItem(withTitle: title, action: #selector(wakeUpSelected), keyEquivalent: "0")
				c.keyEquivalentModifierMask = [.command, .shift]
			} else {

				if muted {
					let c = m.addItem(withTitle: "Un-Mute", action: #selector(unMuteSelected), keyEquivalent: "m")
					c.keyEquivalentModifierMask = [.command]
				} else {
					let c = m.addItem(withTitle: "Mute", action: #selector(muteSelected), keyEquivalent: "m")
					c.keyEquivalentModifierMask = [.command]
				}

				let snoozeItems = SnoozePreset.allSnoozePresets(in: mainObjectContext)
				if snoozeItems.count > 0 {
					var count = 1
					let c = m.addItem(withTitle: "Snooze...", action: nil, keyEquivalent: "")
					let s = NSMenu(title: "Snooze")
					for i in snoozeItems {
						let keyEquivalent = count < 10 ? "\(count)" : ""
						let smi = s.addItem(withTitle: i.listDescription, action: #selector(snoozeSelected), keyEquivalent: keyEquivalent)
						smi.representedObject = i.objectID
						if !keyEquivalent.isEmpty {
							smi.keyEquivalentModifierMask = [.command, .option]
							count += 1
						}
					}
					s.addItem(withTitle: "Configure...", action: #selector(snoozeConfigSelected), keyEquivalent: "")
					c.submenu = s
				}
			}
		}

		menu = m
    }

	func snoozeConfigSelected() {
		app.showPreferencesWindow(andSelect: 6)
	}

	func snoozeSelected(_ sender: NSMenuItem) {
		if let item = associatedDataItem, let oid = sender.representedObject as? NSManagedObjectID, let snoozeItem = existingObject(with: oid) as? SnoozePreset {
			item.snooze(using: snoozeItem)
			saveAndRequestMenuUpdate(item)
		}
	}

	func wakeUpSelected() {
		if let item = associatedDataItem {
			item.wakeUp()
			saveAndRequestMenuUpdate(item)
		}
	}

	func markReadSelected() {
		if let item = associatedDataItem {
			item.catchUpWithComments()
			saveAndRequestMenuUpdate(item)
		}
	}

	func markUnreadSelected() {
		if let item = associatedDataItem {
			item.latestReadCommentDate = .distantPast
			item.postProcess()
			saveAndRequestMenuUpdate(item)
		}
	}

	func muteSelected() {
		if let item = associatedDataItem {
			item.setMute(to: true)
			saveAndRequestMenuUpdate(item)
		}
	}

	func unMuteSelected() {
		if let item = associatedDataItem {
			item.setMute(to: false)
			saveAndRequestMenuUpdate(item)
		}
	}

	private func saveAndRequestMenuUpdate(_ item: ListableItem) {
		DataManager.saveDB()
		app.updateRelatedMenus(for: item)
	}

	var associatedDataItem: ListableItem? {
		return existingObject(with: dataItemId) as? ListableItem
	}

	override func updateTrackingAreas() {
		if trackingArea != nil { removeTrackingArea(trackingArea) }

		trackingArea = NSTrackingArea(rect: bounds,
			options: [NSTrackingAreaOptions.mouseEnteredAndExited, NSTrackingAreaOptions.activeInKeyWindow],
			owner: self,
			userInfo: nil)

		addTrackingArea(trackingArea)

		let mouseLocation = convert(window?.mouseLocationOutsideOfEventStream ?? NSZeroPoint, from: nil)

		if NSPointInRect(mouseLocation, bounds) {
			mouseEntered(with: nil)
		} else if !selected {
			mouseExited(with: nil)
		}
	}

	//////////////////////////// Counts

	private var countBackground: FilledView?
	private var newBackground: FilledView?
	private var countView: CenterTextField?

	func addCounts(_ totalCount: Int64, _ unreadCount: Int64, _ faded: Bool) {

		if totalCount == 0 {
			return
		}

		let pCenter = NSMutableParagraphStyle()
		pCenter.alignment = .center

		let countString = NSAttributedString(string: itemCountFormatter.string(from: Int(totalCount))!, attributes: [
			NSFontAttributeName: NSFont.menuFont(ofSize: 11),
			NSForegroundColorAttributeName: goneDark ? NSColor.controlLightHighlightColor : NSColor.controlTextColor,
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

			let alertString = NSAttributedString(string: itemCountFormatter.string(from: Int(unreadCount))!, attributes: [
				NSFontAttributeName: NSFont.menuFont(ofSize: 8),
				NSForegroundColorAttributeName: NSColor.white,
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

			newBackground = cc
		}

		highlight(false)
	}

	private func highlight(_ on: Bool) {
		if let c = countBackground {
			var color: NSColor
			if goneDark {
				color = on ? .black : NSColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1.0)
				c.backgroundColor = on ? NSColor.white.withAlphaComponent(DISABLED_FADE) : NSColor.black.withAlphaComponent(0.2)
				newBackground?.backgroundColor = NSColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 1.0)
			} else {
				color = goneDark ? .controlLightHighlightColor : .controlTextColor
				c.backgroundColor = NSColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1.0)
				newBackground?.backgroundColor = NSColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)
			}
			if let a = countView?.attributedStringValue.mutableCopy() as? NSMutableAttributedString {
				a.addAttribute(NSForegroundColorAttributeName, value: color, range: NSMakeRange(0, a.length))
				countView?.attributedStringValue = a
			}
		}
	}
}

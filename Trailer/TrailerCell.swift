
class TrailerCell: NSTableCellView {

	var title: CenterTextField!
	let unselectedTitleColor: NSColor
	let detailFont: NSFont!, titleFont: NSFont!

	private let dataItemId: NSManagedObjectID!
	private let isDark: Bool
	private var trackingArea: NSTrackingArea?

	init(frame frameRect: NSRect, item: ListableItem) {

		dataItemId = item.objectID
		detailFont = NSFont.menuFont(ofSize: 10.0)
		titleFont = NSFont.menuFont(ofSize: 13.0)

		isDark = Settings.useVibrancy && app.darkMode

		unselectedTitleColor = isDark ? .controlHighlightColor : .controlTextColor

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

			if let item = associatedDataItem {
				let titleColor = (selected && isDark) ? .darkGray : unselectedTitleColor
				title.attributedStringValue = item.title(with: titleFont, labelFont: detailFont, titleColor: titleColor)
			}

			if selected {
				table.selectRowIndexes(IndexSet(integer: table.row(for: self)), byExtendingSelection: false)
			} else {
				table.deselectRow(table.row(for: self))
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

	override func menu(for event: NSEvent) -> NSMenu? {

		guard let item = associatedDataItem else {
			return nil
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
			if item.hasUnreadCommentsOrAlert {
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
				if snooze == .distantFuture || snooze == autoSnoozeSentinelDate {
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

				let snoozeItems = SnoozePreset.allSnoozePresets(in: DataManager.main)
				if snoozeItems.count > 0 {
					var count = 1
					let c = m.addItem(withTitle: "Snooze…", action: nil, keyEquivalent: "")
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
					s.addItem(withTitle: "Configure…", action: #selector(snoozeConfigSelected), keyEquivalent: "")
					c.submenu = s
				}
			}
		}

		return m
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
		if let t = trackingArea {
			removeTrackingArea(t)
		}

		let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
		addTrackingArea(t)
		trackingArea = t

		if let mouseLocation = window?.mouseLocationOutsideOfEventStream {
			let localLocation = convert(mouseLocation, to: self)
			if NSPointInRect(localLocation, bounds) && !selected {
				mouseEntered(with: nil)
			} else if selected {
				mouseExited(with: nil)
			}
		}
	}

	//////////////////////////// Counts

	private var countBackground: FilledView?
	private var newBackground: FilledView?
	private var countView: CenterTextField?

	func addCounts(total: Int64, unread: Int64, alert: Bool, faded: Bool) {

		if total == 0 && !alert {
			return
		}

		let pCenter = NSMutableParagraphStyle()
		pCenter.alignment = .center

		let countString = NSAttributedString(string: itemCountFormatter.string(for: total)!, attributes: [
			NSFontAttributeName: NSFont.menuFont(ofSize: 11),
			NSForegroundColorAttributeName: isDark ? NSColor.controlLightHighlightColor : NSColor.controlTextColor,
			NSParagraphStyleAttributeName: pCenter])

		var height: CGFloat = 20
		var width = max(height, countString.size().width+10)
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

		if unread > 0 || alert {

			let alertText = unread==0 ? "!" : itemCountFormatter.string(for: unread)!
			let alertString = NSAttributedString(string: alertText, attributes: [
				NSFontAttributeName: NSFont.menuFont(ofSize: 8),
				NSForegroundColorAttributeName: NSColor.white,
				NSParagraphStyleAttributeName: pCenter])

			bottom += height
			height = 14
			width = max(height, alertString.size().width+8.0)
			bottom -= height * 0.5 + 1
			left -= width * 0.5

			let cc = FilledView(frame: NSIntegralRect(NSMakeRect(left, bottom, width, height)))
			cc.cornerRadius = floor(height*0.5)

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
			if isDark {
				color = on ? .black : NSColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1.0)
				c.backgroundColor = on ? NSColor.white.withAlphaComponent(DISABLED_FADE) : NSColor.black.withAlphaComponent(0.2)
				newBackground?.backgroundColor = NSColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 1.0)
			} else {
				color = .controlTextColor
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

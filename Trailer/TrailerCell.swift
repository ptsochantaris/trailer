
class TrailerCell: NSTableCellView {

	private static let statusAttributes: [String : Any] = {

		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.headIndent = 17

		return [
			NSFontAttributeName: NSFont(name: "Monaco", size: 9)!,
			NSParagraphStyleAttributeName: paragraphStyle
			] as [String:Any]
	}()


	private let detailFont = NSFont.menuFont(ofSize: 10.0)
	private let titleFont = NSFont.menuFont(ofSize: 13.0)

	private let dataItemId: NSManagedObjectID!
	private let isDark = Settings.useVibrancy && app.darkMode
	private let unselectedTitleColor: NSColor

	private var title: CenterTextField!
	private var trackingArea: NSTrackingArea?

	init(item: ListableItem) {

		dataItemId = item.objectID

		unselectedTitleColor = isDark ? .controlHighlightColor : .controlTextColor

		super.init(frame: .zero)

		let faded = item.shouldSkipNotifications

		var W = MENU_WIDTH-LEFTPADDING-app.scrollBarWidth

		let showUnpin = item.condition != ItemCondition.open.rawValue
		if showUnpin { W -= REMOVE_BUTTON_WIDTH } else { W -= 4 }

		let showAvatar = !(S(item.userAvatarUrl).isEmpty || Settings.hideAvatars)
		let shift: CGFloat = showAvatar ? AVATAR_SIZE + AVATAR_PADDING : -4
		W -= shift

		let bottom: CGFloat
		let cellPadding: CGFloat
		var statusBottom: CGFloat = 0
		let widthLimit = CGSize(width: W, height: .greatestFiniteMagnitude)

		if let pullRequest = item as? PullRequest, Settings.showStatusItems {
			cellPadding = 10
			bottom = 5

			for status in pullRequest.displayedStatuses.reversed() {
				let text = status.displayText
				let H = text.boundingRect(with: widthLimit, options: stringDrawingOptions, attributes: TrailerCell.statusAttributes).integral.size.height
				let rect = CGRect(x: LEFTPADDING + shift, y: bottom + statusBottom, width: W, height: H)
				statusBottom += H

				let statusLabel = LinkField(frame: rect)
				statusLabel.targetUrl = status.targetUrl
				statusLabel.needsCommand = !Settings.makeStatusItemsSelectable
				statusLabel.attributedStringValue = NSAttributedString(string: text, attributes: TrailerCell.statusAttributes)
				statusLabel.textColor = status.colorForDisplay
				statusLabel.alphaValue = faded ? DISABLED_FADE : 1.0
				addSubview(statusLabel)
			}

		} else {
			cellPadding = 6
			bottom = 3
		}

		let _title = item.title(with: titleFont, labelFont: detailFont, titleColor: unselectedTitleColor)
		let titleHeight = _title.boundingRect(with: widthLimit, options: stringDrawingOptions).integral.size.height

		let _subtitle = item.subtitle(with: detailFont, lightColor: .gray, darkColor: .darkGray)
		let subtitleHeight = _subtitle.boundingRect(with: widthLimit, options: stringDrawingOptions).integral.size.height + 4

		frame = CGRect(x: 0, y: 0, width: MENU_WIDTH, height: titleHeight + subtitleHeight + statusBottom + cellPadding)
		let hasNewCommits = (item as? PullRequest)?.hasNewCommits ?? false
		addCounts(total: item.totalComments, unread: item.unreadComments, alert: hasNewCommits, faded: faded)

		if showAvatar {
			let avatarRect = CGRect(x: LEFTPADDING, y: bounds.size.height-AVATAR_SIZE-7.0, width: AVATAR_SIZE, height: AVATAR_SIZE)
			let userImage = AvatarView(frame: avatarRect, url: S(item.userAvatarUrl))
			userImage.alphaValue = faded ? DISABLED_FADE : 1.0
			addSubview(userImage)
		}

		if showUnpin {
			let pinRect = CGRect(x: LEFTPADDING + W + shift, y: floor((bounds.size.height-24)*0.5), width: REMOVE_BUTTON_WIDTH-10, height: 24)
			let unpin = NSButton(frame: pinRect)
			unpin.title = "Remove"
			unpin.target = self
			unpin.action = #selector(unPinSelected)
			unpin.setButtonType(.momentaryLight)
			unpin.bezelStyle = .roundRect
			unpin.font = NSFont.systemFont(ofSize: 10.0)
			addSubview(unpin)
		}

		let titleRect = CGRect(x: LEFTPADDING + shift, y: subtitleHeight + bottom + statusBottom, width: W, height: titleHeight)
		title = CenterTextField(frame: titleRect)
		title.attributedStringValue = _title
		addSubview(title)

		let subtitleRect = CGRect(x: LEFTPADDING + shift, y: statusBottom + bottom, width: W, height: subtitleHeight)
		let subtitle = CenterTextField(frame: subtitleRect)
		subtitle.attributedStringValue = _subtitle
		addSubview(subtitle)

		if faded {
			title.alphaValue = DISABLED_FADE
			subtitle.alphaValue = DISABLED_FADE
		}
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

    func copyshorthandReferenceToClipboard() {
        if let s = associatedDataItem?.shorthandReference {
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
        
        let c2 = m.addItem(withTitle: "Copy Issue Reference", action: #selector(copyshorthandReferenceToClipboard), keyEquivalent: "s")
        c2.keyEquivalentModifierMask = [.command]


		let c3 = m.addItem(withTitle: "Open Repo", action: #selector(openRepo), keyEquivalent: "o")
		c3.keyEquivalentModifierMask = [.command]

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

		let c = FilledView(frame: CGRect(x: left, y: bottom, width: width, height: height).integral)
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

			let cc = FilledView(frame: CGRect(x: left, y: bottom, width: width, height: height).integral)
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
				a.addAttribute(NSForegroundColorAttributeName, value: color, range: NSRange(location: 0, length: a.length))
				countView?.attributedStringValue = a
			}
		}
	}
}

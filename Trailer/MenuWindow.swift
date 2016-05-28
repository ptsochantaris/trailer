
let newSystem = (floor(NSAppKitVersionNumber) > Double(NSAppKitVersionNumber10_9))

final class MenuWindow: NSWindow {

	@IBOutlet weak var scrollView: NSScrollView!
	@IBOutlet weak var header: ViewAllowsVibrancy!
	@IBOutlet weak var table: NSTableView!
	@IBOutlet weak var filter: NSSearchField!
	@IBOutlet weak var refreshMenuItem: NSMenuItem!

	var statusItem: NSStatusItem?

	var messageView: MessageView? {
		didSet {
			if let p = oldValue {
				p.removeFromSuperview()
			}
			if let m = messageView {
				contentView?.addSubview(m)
			}
		}
	}

	var itemDelegate: ItemDelegate! {
		didSet {
			table.setDataSource(itemDelegate)
			table.setDelegate(itemDelegate)
		}
	}

	private var windowVibrancy: NSView?

	override func awakeFromNib() {

		super.awakeFromNib()

		backgroundColor = NSColor.whiteColor()

        if newSystem {
            scrollView.contentView.wantsLayer = true
        }
	}

	class func usingVibrancy() -> Bool {
		return newSystem && Settings.useVibrancy
	}

	override func controlTextDidChange(obj: NSNotification) {
		app.controlTextDidChange(obj)
	}

	func updateVibrancy() {

		if MenuWindow.usingVibrancy() {

			if #available(OSX 10.10, *) {
			    appearance = NSAppearance(named: app.darkMode ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight)
				if windowVibrancy == nil {
					let w = NSVisualEffectView(frame: header.bounds)
					w.autoresizingMask = [NSAutoresizingMaskOptions.ViewHeightSizable, NSAutoresizingMaskOptions.ViewWidthSizable]
					w.blendingMode = NSVisualEffectBlendingMode.BehindWindow
					w.state = NSVisualEffectState.Active
					header.addSubview(w, positioned:NSWindowOrderingMode.Below, relativeTo:filter)
					windowVibrancy = w

					table.selectionHighlightStyle = NSTableViewSelectionHighlightStyle.SourceList
				}
			}

		} else {

            if let w = windowVibrancy {

                appearance = NSAppearance(named: NSAppearanceNameAqua)
                w.removeFromSuperview()
                windowVibrancy = nil
                table.selectionHighlightStyle = NSTableViewSelectionHighlightStyle.Regular
            }
		}
	}

	func showStatusItem() {
		if statusItem == nil {
			statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(NSVariableStatusItemLength)
		}
	}

	func hideStatusItem() {
		if let s = statusItem {
			s.statusBar.removeStatusItem(s)
			statusItem = nil
		}
	}

    override var canBecomeKeyWindow: Bool {
		return true
	}

	func menuWillOpen(menu: NSMenu) {
		if !appIsRefreshing {
			refreshMenuItem.title = " Refresh - \(api.lastUpdateDescription())"
		}
	}

	func scrollToTop() {
		table.scrollToBeginningOfDocument(nil)
	}

	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}

	@IBAction func markAllReadSelected(sender: NSMenuItem) {
		app.markAllReadSelectedFrom(self)
	}

	@IBAction func preferencesSelected(sender: NSMenuItem) {
		app.preferencesSelected()
	}

	@IBAction func refreshSelected(sender: NSMenuItem) {
		if Repo.countItemsOfType("Repo", moc: mainObjectContext) == 0 {
			app.preferencesSelected()
			return
		}
		app.startRefresh()
	}

	@IBAction func aboutSelected(sender: AnyObject) {
		app.showAboutWindow()
	}

	func sizeAndShow(show: Bool) {

		guard let siv = statusItem?.view as? StatusItemView else { return }
		guard let windowFrame = siv.window?.frame else { return }

		var S: NSScreen?
		for s in NSScreen.screens() ?? [] {
			if CGRectContainsRect(s.frame, windowFrame) {
				S = s
				break
			}
		}

		guard let screen = S else { return }

		var menuLeft = windowFrame.origin.x
		let rightSide = screen.visibleFrame.origin.x + screen.visibleFrame.size.width
		let overflow = (menuLeft+MENU_WIDTH)-rightSide
		if overflow > 0 {
			menuLeft -= overflow
		}

		var menuHeight = TOP_HEADER_HEIGHT
		let rowCount = table.numberOfRows
		let screenHeight = screen.visibleFrame.size.height
		if rowCount == 0 {
			menuHeight += 95
		} else {
			menuHeight += 10
			for f in 0..<rowCount {
				let rowView = table.viewAtColumn(0, row: f, makeIfNecessary: true)!
				menuHeight += rowView.frame.size.height + 2
				if menuHeight >= screenHeight {
					break
				}
			}
		}

		var bottom = screen.visibleFrame.origin.y
		if menuHeight < screenHeight {
			bottom += screenHeight-menuHeight
		} else {
			menuHeight = screenHeight
		}

		setFrame(CGRectMake(menuLeft, bottom, MENU_WIDTH, menuHeight), display: false, animate: false)

		if show {
			siv.highlighted = true
			table.deselectAll(nil)
			app.openingWindow = true
			level = Int(CGWindowLevelForKey(CGWindowLevelKey.FloatingWindowLevelKey))
			makeKeyAndOrderFront(self)
			NSApp.activateIgnoringOtherApps(true)
			app.openingWindow = false
		}
	}

	func reload() {
		messageView = nil
		itemDelegate.reloadData(filter.stringValue)
		table.reloadData()
	}

	func closeMenu() {
		if visible, let siv = statusItem?.view as? StatusItemView {
			siv.highlighted = false
			orderOut(nil)
			table.deselectAll(nil)
		}
	}

	func focusedItem() -> ListableItem? {
		let row = table.selectedRow
		var i: ListableItem?
		if row >= 0 {
			table.deselectAll(nil)
			i = itemDelegate.itemAtRow(row)
		}
		atNextEvent(self) { S in
			S.table.selectRowIndexes(NSIndexSet(index: row), byExtendingSelection: false)
		}
		return i
	}
}

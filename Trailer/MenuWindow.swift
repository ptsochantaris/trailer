
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
			table.dataSource = itemDelegate
			table.delegate = itemDelegate
		}
	}

	private var windowVibrancy: NSView?

	override func awakeFromNib() {

		super.awakeFromNib()

		backgroundColor = NSColor.white

        if newSystem {
            scrollView.contentView.wantsLayer = true
        }

		NotificationCenter.default.addObserver(self, selector: #selector(MenuWindow.refreshUpdate), name: SyncProgressUpdateNotification, object: nil)
	}

	class var isUsingVibrancy: Bool {
		return newSystem && Settings.useVibrancy
	}

	override func controlTextDidChange(_ obj: Notification) {
		app.controlTextDidChange(obj)
	}

	func updateVibrancy() {

		if MenuWindow.isUsingVibrancy {

			if #available(OSX 10.10, *) {
			    appearance = NSAppearance(named: app.darkMode ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight)
				if windowVibrancy == nil {
					let w = NSVisualEffectView(frame: header.bounds)
					w.autoresizingMask = [NSAutoresizingMaskOptions.viewHeightSizable, NSAutoresizingMaskOptions.viewWidthSizable]
					w.blendingMode = NSVisualEffectBlendingMode.behindWindow
					w.state = NSVisualEffectState.active
					header.addSubview(w, positioned:NSWindowOrderingMode.below, relativeTo:filter)
					windowVibrancy = w

					table.selectionHighlightStyle = NSTableViewSelectionHighlightStyle.sourceList
				}
			}

		} else {

            if let w = windowVibrancy {

                appearance = NSAppearance(named: NSAppearanceNameAqua)
                w.removeFromSuperview()
                windowVibrancy = nil
                table.selectionHighlightStyle = NSTableViewSelectionHighlightStyle.regular
            }
		}
	}

	var showStatusItem: StatusItemView {
		if statusItem == nil {
			statusItem = NSStatusBar.system().statusItem(withLength: NSVariableStatusItemLength)
			statusItem!.view = StatusItemView { [weak self] in
				if let S = self {
					if S.isVisible { S.closeMenu() } else { app.show(menu: S) }
				}
			}
		}
		return statusItem!.view as! StatusItemView
	}

	func hideStatusItem() {
		if let s = statusItem {
			s.statusBar.removeStatusItem(s)
			statusItem = nil
		}
	}

    override var canBecomeKey: Bool {
		return true
	}

	func menuWillOpen(_ menu: NSMenu) {
		if appIsRefreshing {
			refreshUpdate()
		} else {
			refreshMenuItem.title = " Refresh - \(api.lastUpdateDescription)"
		}
	}

	func refreshUpdate() {
		refreshMenuItem.title = " \(api.lastUpdateDescription)"
	}

	func scrollToTop() {
		table.scrollToBeginningOfDocument(nil)
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	@IBAction func markAllReadSelected(_ sender: NSMenuItem) {
		app.markAllReadSelected(from: self)
	}

	@IBAction func preferencesSelected(_ sender: NSMenuItem) {
		app.preferencesSelected()
	}

	@IBAction func refreshSelected(_ sender: NSMenuItem) {
		if Repo.countItems(ofType: "Repo", in: mainObjectContext) == 0 {
			app.preferencesSelected()
			return
		}
		app.startRefresh()
	}

	@IBAction func aboutSelected(_ sender: AnyObject) {
		app.showAboutWindow()
	}

	func size(andShow makeVisible: Bool) {

		guard let siv = statusItem?.view as? StatusItemView else { return }
		guard let windowFrame = siv.window?.frame else { return }

		var S: NSScreen?
		for s in NSScreen.screens() ?? [] {
			if s.frame.contains(windowFrame) {
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
				let rowView = table.view(atColumn: 0, row: f, makeIfNecessary: true)!
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

		setFrame(CGRect(x: menuLeft, y: bottom, width: MENU_WIDTH, height: menuHeight), display: false, animate: false)

		if makeVisible {
			siv.highlighted = true
			table.deselectAll(nil)
			app.openingWindow = true
			level = Int(CGWindowLevelForKey(CGWindowLevelKey.floatingWindow))
			makeKeyAndOrderFront(self)
			NSApp.activateIgnoringOtherApps(true)
			app.openingWindow = false
		}
	}

	func reload() {
		messageView = nil
		itemDelegate.reloadData(filter: filter.stringValue)
		table.reloadData()
	}

	func closeMenu() {
		if isVisible, let siv = statusItem?.view as? StatusItemView {
			siv.highlighted = false
			orderOut(nil)
			table.deselectAll(nil)
		}
	}

	func focusedItem(blink: Bool) -> ListableItem? {
		let row = table.selectedRow
		var i: ListableItem?
		if row >= 0 {
			if blink { table.deselectAll(nil) }
			i = itemDelegate.itemAtRow(row)
		}
		if blink {
			atNextEvent(self) { S in
				S.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
			}
		}
		return i
	}
}

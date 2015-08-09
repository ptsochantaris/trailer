
let newSystem = (floor(NSAppKitVersionNumber) > Double(NSAppKitVersionNumber10_9))

final class MenuWindow: NSWindow {

	@IBOutlet weak var scrollView: NSScrollView!
	@IBOutlet weak var header: ViewAllowsVibrancy!
	@IBOutlet weak var table: NSTableView!
	@IBOutlet weak var filter: NSSearchField!
	@IBOutlet weak var refreshMenuItem: NSMenuItem!

	var statusItem: NSStatusItem?
	var messageView: MessageView?

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
		if !app.isRefreshing {
			refreshMenuItem.title = " Refresh - " + api.lastUpdateDescription()
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
		if Repo.countVisibleReposInMoc(mainObjectContext) == 0 {
			app.preferencesSelected()
			return
		}
		app.startRefresh()
	}

	@IBAction func aboutSelected(sender: AnyObject) {
		app.showAboutWindow()
	}
}


let newSystem = (floor(NSAppKitVersionNumber) > Double(NSAppKitVersionNumber10_9))

final class MenuWindow: NSWindow {

	@IBOutlet weak var scrollView: NSScrollView!
	@IBOutlet weak var header: ViewAllowsVibrancy!
	@IBOutlet weak var table: NSTableView!
	@IBOutlet weak var filter: NSSearchField!
	@IBOutlet weak var refreshMenuItem: NSMenuItem!

	var statusItem: NSStatusItem?
	var messageView: MessageView?

	private var headerVibrant: NSVisualEffectView?

	override func awakeFromNib() {

		super.awakeFromNib()

		backgroundColor = NSColor.whiteColor()

        if newSystem {
            scrollView.automaticallyAdjustsContentInsets = false
			(contentView as! NSView).wantsLayer = true
        }

		let n = NSNotificationCenter.defaultCenter()
		n.addObserver(self, selector: Selector("updateVibrancy"), name: UPDATE_VIBRANCY_NOTIFICATION, object: nil)
		n.addObserver(self, selector: Selector("updateVibrancy"), name: DARK_MODE_CHANGED, object: nil)
	}

	class func usingVibrancy() -> Bool {
		return newSystem && Settings.useVibrancy
	}

	override func controlTextDidChange(obj: NSNotification) {
		app.controlTextDidChange(obj)
	}

	func updateVibrancy() {

		let vibrancy = MenuWindow.usingVibrancy()

		if newSystem {
			headerVibrant?.removeFromSuperview()
			headerVibrant = nil
		}

		if vibrancy {
			headerVibrant = NSVisualEffectView(frame: header.bounds)
			headerVibrant!.autoresizingMask = NSAutoresizingMaskOptions.ViewHeightSizable | NSAutoresizingMaskOptions.ViewWidthSizable
			headerVibrant!.blendingMode = NSVisualEffectBlendingMode.BehindWindow
			header.addSubview(headerVibrant!, positioned:NSWindowOrderingMode.Below, relativeTo:nil)

			appearance = NSAppearance(named: app.darkMode ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight)
			table.selectionHighlightStyle = NSTableViewSelectionHighlightStyle.SourceList
		} else {
			if newSystem {
				appearance = NSAppearance(named: NSAppearanceNameAqua)
                table.selectionHighlightStyle = NSTableViewSelectionHighlightStyle.Regular
            } else {
                table.backgroundColor = NSColor.whiteColor()
            }
		}
	}

	func showStatusItem() {
		if statusItem == nil {
			statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(-1) //NSVariableStatusItemLength
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

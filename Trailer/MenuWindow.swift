
let newSystem = (floor(NSAppKitVersionNumber) > Double(NSAppKitVersionNumber10_9))

final class MenuWindow: NSWindow {

	@IBOutlet weak var scrollView: NSScrollView!
	@IBOutlet weak var header: ViewAllowsVibrancy!
	@IBOutlet weak var table: NSTableView!
	@IBOutlet weak var filter: NSSearchField!
	@IBOutlet weak var refreshMenuItem: NSMenuItem!

	var statusItem: NSStatusItem?
	var messageView: MessageView?

	private var windowVibrancy: NSVisualEffectView?

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

		if MenuWindow.usingVibrancy() {

			appearance = NSAppearance(named: app.darkMode ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight)

			if windowVibrancy == nil {
				windowVibrancy = NSVisualEffectView(frame: contentView.bounds)
				windowVibrancy!.autoresizingMask = NSAutoresizingMaskOptions.ViewHeightSizable | NSAutoresizingMaskOptions.ViewWidthSizable
				windowVibrancy!.blendingMode = NSVisualEffectBlendingMode.BehindWindow
				windowVibrancy!.state = NSVisualEffectState.Active
				contentView.addSubview(windowVibrancy!, positioned:NSWindowOrderingMode.Below, relativeTo:table)

				table.selectionHighlightStyle = NSTableViewSelectionHighlightStyle.SourceList
			}

		} else {

			if windowVibrancy != nil {
				windowVibrancy!.removeFromSuperview()
				windowVibrancy = nil

				table.selectionHighlightStyle = NSTableViewSelectionHighlightStyle.Regular
			}

			if newSystem {
				appearance = NSAppearance(named: NSAppearanceNameAqua)
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

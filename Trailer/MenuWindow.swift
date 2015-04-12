
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
            scrollView.automaticallyAdjustsContentInsets = false
			(contentView as! NSView).wantsLayer = true
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

			appearance = NSAppearance(named: app.darkMode ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight)

			if windowVibrancy == nil {
				let w = NSVisualEffectView(frame: contentView.bounds)
				w.autoresizingMask = NSAutoresizingMaskOptions.ViewHeightSizable | NSAutoresizingMaskOptions.ViewWidthSizable
				w.blendingMode = NSVisualEffectBlendingMode.BehindWindow
				w.state = NSVisualEffectState.Active
				contentView.addSubview(w, positioned:NSWindowOrderingMode.Below, relativeTo:table)
				windowVibrancy = w

				table.selectionHighlightStyle = NSTableViewSelectionHighlightStyle.SourceList
			}

		} else {

			if let w = windowVibrancy {
				w.removeFromSuperview()
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


let newSystem = (floor(NSAppKitVersionNumber) > Double(NSAppKitVersionNumber10_9))

class MenuWindow: NSWindow {

	@IBOutlet weak var scrollView: NSScrollView!
	@IBOutlet weak var header: ViewAllowsVibrancy!
	@IBOutlet weak var table: NSTableView!
	@IBOutlet weak var filter: NSSearchField!

	private var headerVibrant: NSVisualEffectView?

	override func awakeFromNib() {

		super.awakeFromNib()

		backgroundColor = NSColor.whiteColor()

        if newSystem {
            scrollView.automaticallyAdjustsContentInsets = false
			(contentView as NSView).wantsLayer = true
        }

		let n = NSNotificationCenter.defaultCenter()
		n.addObserver(self, selector: Selector("updateVibrancy"), name: UPDATE_VIBRANCY_NOTIFICATION, object: nil)
		n.addObserver(self, selector: Selector("updateVibrancy"), name: DARK_MODE_CHANGED, object: nil)
	}

	class func usingVibrancy() -> Bool {
		return newSystem && Settings.useVibrancy
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

			appearance = NSAppearance(named: (app.prStatusItem.view as StatusItemView).darkMode ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight)
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

	func canBecomeKeyWindow() -> Bool {
		return true
	}

	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}
}

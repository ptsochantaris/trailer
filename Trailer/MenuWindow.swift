
let newSystem = (floor(NSAppKitVersionNumber) > Double(NSAppKitVersionNumber10_9))

class MenuWindow: NSWindow {

	@IBOutlet weak var scrollView: NSScrollView!
	@IBOutlet weak var header: ViewAllowsVibrancy!
	@IBOutlet weak var table: NSTableView!
	@IBOutlet weak var filter: NSSearchField!

	private var headerVibrant: NSVisualEffectView?

	override func awakeFromNib() {

		super.awakeFromNib()

        if newSystem {
            scrollView.automaticallyAdjustsContentInsets = false
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
			(contentView as NSView).wantsLayer = vibrancy
        }

		var bgColor: CGColorRef

		if vibrancy {
			scrollView.frame = contentView.bounds
			scrollView.contentInsets = NSEdgeInsetsMake(TOP_HEADER_HEIGHT, 0, 0, 0)

			bgColor = NSColor.clearColor().CGColor

			appearance = NSAppearance(named: (app.prStatusItem.view as StatusItemView).darkMode ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight)
			table.selectionHighlightStyle = NSTableViewSelectionHighlightStyle.SourceList

			headerVibrant = NSVisualEffectView(frame: header.bounds)
			headerVibrant!.autoresizingMask = NSAutoresizingMaskOptions.ViewHeightSizable | NSAutoresizingMaskOptions.ViewWidthSizable
			headerVibrant!.blendingMode = NSVisualEffectBlendingMode.WithinWindow
			header.addSubview(headerVibrant!, positioned:NSWindowOrderingMode.Below, relativeTo:nil)
		} else {
			let windowSize = contentView.bounds.size
			scrollView.frame = CGRectMake(0, 0, windowSize.width, windowSize.height-TOP_HEADER_HEIGHT)

			bgColor = NSColor.controlBackgroundColor().CGColor

			if newSystem {
				appearance = NSAppearance(named: NSAppearanceNameAqua)
                scrollView.contentInsets = NSEdgeInsetsMake(0, 0, 0, 0)
                table.selectionHighlightStyle = NSTableViewSelectionHighlightStyle.Regular
            } else {
                table.backgroundColor = NSColor.whiteColor()
            }
		}

		header.layer?.backgroundColor = bgColor

		if newSystem {
			scrollView.scrollerInsets = NSEdgeInsetsMake(4.0, 0, 0.0, 0)
		}
	}

	func canBecomeKeyWindow() -> Bool {
		return true
	}

	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}
}


class MenuWindow: NSWindow {

	@IBOutlet var scrollView: NSScrollView!
	@IBOutlet var header: ViewAllowsVibrancy!
	@IBOutlet var prTable: NSTableView!
	@IBOutlet weak var filter: NSSearchField!

	var headerVibrant: NSVisualEffectView?

	override func awakeFromNib() {

		super.awakeFromNib()

		(contentView as NSView).wantsLayer = true

		if scrollView.respondsToSelector(Selector("setAutomaticallyAdjustsContentInsets:")) {
			scrollView.automaticallyAdjustsContentInsets = false
		}

		let n = NSNotificationCenter.defaultCenter()
		n.addObserver(self, selector: Selector("updateVibrancy"), name: UPDATE_VIBRANCY_NOTIFICATION, object: nil)
		n.addObserver(self, selector: Selector("updateVibrancy"), name: DARK_MODE_CHANGED, object: nil)
	}

	class func usingVibrancy() -> Bool {
		return (NSAppKitVersionNumber>Double(NSAppKitVersionNumber10_9))
			&& (Settings.useVibrancy == true)
			&& (NSClassFromString("NSVisualEffectView") != nil)
	}

	func updateVibrancy() {

		headerVibrant?.removeFromSuperview()
		headerVibrant = nil

		var bgColor: CGColorRef

		if MenuWindow.usingVibrancy() { // we're on 10.10+ here
			scrollView.frame = contentView.bounds
			scrollView.contentInsets = NSEdgeInsetsMake(TOP_HEADER_HEIGHT, 0, 0, 0)

			bgColor = NSColor.clearColor().CGColor

			appearance = NSAppearance(named: (app.statusItem.view as StatusItemView).darkMode ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight)
			prTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyle.SourceList

			headerVibrant = NSVisualEffectView(frame: header.bounds)
			headerVibrant!.autoresizingMask = NSAutoresizingMaskOptions.ViewHeightSizable | NSAutoresizingMaskOptions.ViewWidthSizable
			headerVibrant!.blendingMode = NSVisualEffectBlendingMode.WithinWindow
			header.addSubview(headerVibrant!, positioned:NSWindowOrderingMode.Below, relativeTo:nil)
		} else {
			let windowSize = contentView.bounds.size
			scrollView.frame = CGRectMake(0, 0, windowSize.width, windowSize.height-TOP_HEADER_HEIGHT)

			bgColor = NSColor.controlBackgroundColor().CGColor

			if(NSAppKitVersionNumber>Double(NSAppKitVersionNumber10_9)) {
				appearance = NSAppearance(named: NSAppearanceNameAqua)
			}
			prTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyle.Regular

			if scrollView.respondsToSelector(Selector("setContentInsets:")) {
				scrollView.contentInsets = NSEdgeInsetsMake(0, 0, 0, 0)
			}
		}

		header.layer!.backgroundColor = bgColor;

		if scrollView.respondsToSelector(Selector("setScrollerInsets:")) {
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


class MenuWindow: NSWindow {

	@IBOutlet var scrollView: NSScrollView!
	@IBOutlet var header: ViewAllowsVibrancy!
	@IBOutlet var prTable: NSTableView!
	@IBOutlet weak var filter: NSSearchField!

	private var vibrancyLayers: [NSVisualEffectView]?

	override func awakeFromNib() {

		super.awakeFromNib()

		(self.contentView as NSView).wantsLayer = true

		if self.scrollView!.respondsToSelector(Selector("setAutomaticallyAdjustsContentInsets:")) {
			self.scrollView!.automaticallyAdjustsContentInsets = false
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

		if let layers = vibrancyLayers {
			for v in layers { v.removeFromSuperview() }
			vibrancyLayers = nil
		}

		var bgColor: CGColorRef

		if MenuWindow.usingVibrancy() { // we're on 10.10+ here
			self.scrollView!.frame = self.contentView.bounds
			self.scrollView!.contentInsets = NSEdgeInsetsMake(CGFloat(TOP_HEADER_HEIGHT), 0, 0, 0)

			bgColor = COLOR_CLASS.clearColor().CGColor

			self.appearance = NSAppearance(named: (app.statusItem.view as StatusItemView).darkMode ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight)
			self.prTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyle.SourceList

			let headerVibrant = NSVisualEffectView(frame: self.header!.bounds)
			headerVibrant.autoresizingMask = NSAutoresizingMaskOptions.ViewHeightSizable | NSAutoresizingMaskOptions.ViewWidthSizable
			headerVibrant.blendingMode = NSVisualEffectBlendingMode.WithinWindow
			self.header!.addSubview(headerVibrant, positioned:NSWindowOrderingMode.Below, relativeTo:nil)

			let windowVibrant = NSVisualEffectView(frame: self.contentView.bounds)
			windowVibrant.autoresizingMask = NSAutoresizingMaskOptions.ViewHeightSizable | NSAutoresizingMaskOptions.ViewWidthSizable
			windowVibrant.blendingMode = NSVisualEffectBlendingMode.BehindWindow
			self.contentView.addSubview(windowVibrant, positioned:NSWindowOrderingMode.Below, relativeTo:nil)

			vibrancyLayers = [windowVibrant,headerVibrant]
		} else {
			let windowSize = self.contentView.bounds.size
			self.scrollView!.frame = CGRectMake(0, 0, windowSize.width, windowSize.height-CGFloat(TOP_HEADER_HEIGHT))

			bgColor = COLOR_CLASS.controlBackgroundColor().CGColor

			if(NSAppKitVersionNumber>Double(NSAppKitVersionNumber10_9)) {
				self.appearance = NSAppearance(named: NSAppearanceNameAqua)
			}
			self.prTable!.selectionHighlightStyle = NSTableViewSelectionHighlightStyle.Regular

			if self.scrollView!.respondsToSelector(Selector("setContentInsets:")) {
				self.scrollView!.contentInsets = NSEdgeInsetsMake(0, 0, 0, 0)
			}
		}

		self.header!.layer!.backgroundColor = bgColor;

		if self.scrollView!.respondsToSelector(Selector("setScrollerInsets:")) {
			self.scrollView!.scrollerInsets = NSEdgeInsetsMake(4.0, 0, 0.0, 0)
		}
	}

	func canBecomeKeyWindow() -> Bool {
		return true
	}

	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}
}

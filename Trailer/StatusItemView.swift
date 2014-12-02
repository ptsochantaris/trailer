
class StatusItemView: NSView {

	let label: String
	let textAttributes: Dictionary<String, AnyObject>
	var tappedCallback: (() -> Void)?

	init(frame: NSRect, label: String, attributes: Dictionary<String, AnyObject>) {
		self.label = label
		self.textAttributes = attributes
		super.init(frame: frame)
		darkMode = StatusItemView.checkDarkMode()
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

	class func checkDarkMode() -> Bool {
		if NSAppKitVersionNumber>Double(NSAppKitVersionNumber10_9) {
			let c = NSAppearance.currentAppearance()
			if c.respondsToSelector(Selector("allowsVibrancy")) {
				return c.name.rangeOfString(NSAppearanceNameVibrantDark) != nil
			}
		}
		return false
	}

	var grayOut: Bool {
		get {
			return self.grayOut
		}
		set {
			if grayOut != newValue {
				self.grayOut = newValue
				needsDisplay = true
			}
		}
	}

	var darkMode: Bool {
		get {
			return self.grayOut
		}
		set {
			if(darkMode != newValue) {
				self.darkMode = newValue;
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (Int64)(0.1 * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
					NSNotificationCenter.defaultCenter().postNotificationName(DARK_MODE_CHANGED, object:nil)
				}
			}
		}
	}

	var highlighted: Bool {
		get {
			return self.highlighted
		}
		set {
			if highlighted != newValue {
				self.highlighted = newValue
				needsDisplay = true
			}
		}
	}

	override func mouseDown(theEvent: NSEvent) {
		if let t = tappedCallback { t() }
	}

	override func drawRect(dirtyRect: NSRect) {

		app.statusItem.drawStatusBarBackgroundInRect(dirtyRect, withHighlight: highlighted)

		darkMode = StatusItemView.checkDarkMode()

		let imagePoint = NSMakePoint(CGFloat(STATUSITEM_PADDING), CGFloat(0))
		let labelRect = CGRectMake(self.bounds.size.height, -5, self.bounds.size.width, self.bounds.size.height)
		var displayAttributes = textAttributes
		var icon: NSImage

		if(highlighted) {
			icon = NSImage(named: "menuIconBright")!
			displayAttributes[NSForegroundColorAttributeName] = COLOR_CLASS.selectedMenuItemTextColor()
		} else {
			if(darkMode) {
				icon = NSImage(named: "menuIconBright")!
				if(displayAttributes[NSForegroundColorAttributeName] as COLOR_CLASS == COLOR_CLASS.controlTextColor()) {
					displayAttributes[NSForegroundColorAttributeName] = COLOR_CLASS.selectedMenuItemTextColor()
				}
			} else {
				icon = NSImage(named: "menuIcon")!
			}
		}

		if(grayOut) {
			displayAttributes[NSForegroundColorAttributeName] = COLOR_CLASS.disabledControlTextColor()
		}

		icon.drawAtPoint(imagePoint, fromRect: NSZeroRect, operation: NSCompositingOperation.CompositeSourceOver, fraction: 1.0)
		label.drawInRect(labelRect, withAttributes: displayAttributes)
	}
}

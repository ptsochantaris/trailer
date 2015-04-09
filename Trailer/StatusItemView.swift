
final class StatusItemView: NSView {

	let statusLabel: String
	let textAttributes: Dictionary<String, AnyObject>
    var tappedCallback: (() -> Void)?
	let imagePrefix: String
	var labelOffset: CGFloat = 0

	init(frame: NSRect, label: String, prefix: String, attributes: Dictionary<String, AnyObject>) {
		imagePrefix = prefix
		statusLabel = label
		textAttributes = attributes
		highlighted = false
		grayOut = false
		super.init(frame: frame)
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

	var grayOut: Bool {
		didSet {
			if grayOut != oldValue {
				needsDisplay = true
			}
		}
	}

	var highlighted: Bool {
		didSet {
			if highlighted != oldValue {
				needsDisplay = true
			}
		}
	}

	override func mouseDown(theEvent: NSEvent) {
		tappedCallback?()
	}

	override func drawRect(dirtyRect: NSRect) {

		if(app.prMenu.statusItem!.view==self) {
			app.prMenu.statusItem!.drawStatusBarBackgroundInRect(dirtyRect, withHighlight: highlighted)
		} else {
			app.issuesMenu.statusItem!.drawStatusBarBackgroundInRect(dirtyRect, withHighlight: highlighted)
		}

		let imagePoint = NSMakePoint(STATUSITEM_PADDING, 0)
		let labelRect = CGRectMake(bounds.size.height + labelOffset, -5, bounds.size.width, bounds.size.height)
		var displayAttributes = textAttributes
		var icon: NSImage

		if highlighted {
			icon = NSImage(named: "\(imagePrefix)IconBright")!
			displayAttributes[NSForegroundColorAttributeName] = NSColor.selectedMenuItemTextColor()
		} else {
			if app.checkDarkMode() {
				icon = NSImage(named: "\(imagePrefix)IconBright")!
				if displayAttributes[NSForegroundColorAttributeName] as! NSColor == NSColor.controlTextColor() {
					displayAttributes[NSForegroundColorAttributeName] = NSColor.selectedMenuItemTextColor()
				}
			} else {
				icon = NSImage(named: "\(imagePrefix)Icon")!
			}
		}

		if grayOut {
			displayAttributes[NSForegroundColorAttributeName] = NSColor.disabledControlTextColor()
		}

		icon.drawAtPoint(imagePoint, fromRect: NSZeroRect, operation: NSCompositingOperation.CompositeSourceOver, fraction: 1.0)
		statusLabel.drawInRect(labelRect, withAttributes: displayAttributes)
	}
}


final class StatusItemView: NSView {

	let statusLabel: String
	let textAttributes: [String : AnyObject]
    var tappedCallback: (() -> Void)?
	var labelOffset: CGFloat = 0
	let icon: NSImage

	init(frame: NSRect, label: String, prefix: String, attributes: [String : AnyObject]) {
		statusLabel = label
		textAttributes = attributes
		highlighted = false
		grayOut = false
		icon = NSImage(named: "\(prefix)Icon")!
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
		var imageColor: NSColor

		if highlighted {
			imageColor = NSColor.selectedMenuItemTextColor()
			displayAttributes[NSForegroundColorAttributeName] = imageColor
		} else if app.darkMode {
			imageColor = NSColor.selectedMenuItemTextColor()
			if displayAttributes[NSForegroundColorAttributeName] as! NSColor == NSColor.controlTextColor() {
				displayAttributes[NSForegroundColorAttributeName] = imageColor
			}
		} else {
			imageColor = NSColor.controlTextColor()
		}

		if grayOut {
			displayAttributes[NSForegroundColorAttributeName] = NSColor.disabledControlTextColor()
		}

		statusLabel.drawInRect(labelRect, withAttributes: displayAttributes)

		tintedImage(icon, tint: imageColor).drawAtPoint(imagePoint, fromRect: NSZeroRect, operation: NSCompositingOperation.CompositeSourceOver, fraction: 1.0)
	}

	// With thanks to http://stackoverflow.com/questions/1413135/tinting-a-grayscale-nsimage-or-ciimage
	private func tintedImage(image: NSImage, tint: NSColor) -> NSImage {

		let tinted = image.copy() as! NSImage
		tinted.lockFocus()
		tint.set()

		let imageRect = NSRect(origin: NSZeroPoint, size: image.size)
		NSRectFillUsingOperation(imageRect, NSCompositingOperation.CompositeSourceAtop)

		tinted.unlockFocus()
		return tinted
	}
}

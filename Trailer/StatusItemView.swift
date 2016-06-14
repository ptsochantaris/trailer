
final class StatusItemView: NSView {

	private let tappedCallback: Completion

	var icon: NSImage!
	var textAttributes = [String : AnyObject]()
	var statusLabel = ""
	var labelOffset:CGFloat = 0
	var title: String?
	var grayOut = false

	var highlighted = false {
		didSet {
			if highlighted != oldValue {
				needsDisplay = true
			}
		}
	}

	init(callback: Completion) {
		tappedCallback = callback
		super.init(frame: NSZeroRect)
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

	override func mouseDown(theEvent: NSEvent) {
		tappedCallback()
	}

	private let STATUSITEM_PADDING: CGFloat = 1.0

	func sizeToFit() {
		let width = statusLabel.sizeWithAttributes(textAttributes).width
		let H = NSStatusBar.systemStatusBar().thickness
		let itemWidth = (H + width + STATUSITEM_PADDING*3) + labelOffset
		frame = NSMakeRect(0, 0, itemWidth, H)
		needsDisplay = true
	}

	override func drawRect(dirtyRect: NSRect) {

		app.statusItemForView(self)?.drawStatusBarBackgroundInRect(dirtyRect, withHighlight: highlighted)

		let imagePoint = NSMakePoint(STATUSITEM_PADDING, 0)
		var labelRect = CGRectMake(bounds.size.height + labelOffset, -5, bounds.size.width, bounds.size.height)
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

		let img = tintedImage(icon, tint: imageColor)
		if let t = title {

			labelRect = CGRectOffset(labelRect, -3, -3)

			let r = NSMakeRect(1, dirtyRect.height-7, dirtyRect.width-2, 7)
			let p = NSMutableParagraphStyle()
			p.alignment = .Center
			p.lineBreakMode = .ByTruncatingMiddle
			t.drawInRect(r, withAttributes: [
				NSForegroundColorAttributeName: imageColor,
				NSFontAttributeName: NSFont.menuFontOfSize(6),
				NSParagraphStyleAttributeName: p
				])

			img.drawInRect(CGRectMake(imagePoint.x+3, imagePoint.y, img.size.width-6, img.size.height-6))
		} else {
			img.drawAtPoint(imagePoint, fromRect: NSZeroRect, operation: NSCompositingOperation.CompositeSourceOver, fraction: 1.0)
		}

		statusLabel.drawInRect(labelRect, withAttributes: displayAttributes)
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


final class StatusItemView: NSView {

	private let tappedCallback: Completion

	var icon: NSImage!
	var textAttributes = [String : AnyObject]()
	var statusLabel = ""
	var labelOffset: CGFloat = 0
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

	override func mouseDown(with theEvent: NSEvent) {
		tappedCallback()
	}

	private let STATUSITEM_PADDING: CGFloat = 1.0

	func sizeToFit() {
		let width = statusLabel.size(withAttributes: textAttributes).width
		let H = NSStatusBar.system().thickness
		let itemWidth = (H + width + STATUSITEM_PADDING*3) + labelOffset
		frame = NSMakeRect(0, 0, itemWidth, H)
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect) {

		app.statusItem(for: self)?.drawStatusBarBackground(in: dirtyRect, withHighlight: highlighted)

		let imagePoint = NSMakePoint(STATUSITEM_PADDING, 0)
		var labelRect = CGRect(x: bounds.size.height + labelOffset, y: -5, width: bounds.size.width, height: bounds.size.height)
		var displayAttributes = textAttributes
		var imageColor: NSColor

		if highlighted {
			imageColor = .selectedMenuItemTextColor
			displayAttributes[NSForegroundColorAttributeName] = imageColor
		} else if app.darkMode {
			imageColor = .selectedMenuItemTextColor
			if displayAttributes[NSForegroundColorAttributeName] as! NSColor == NSColor.controlTextColor {
				displayAttributes[NSForegroundColorAttributeName] = imageColor
			}
		} else {
			imageColor = .controlTextColor
		}

		if grayOut {
			displayAttributes[NSForegroundColorAttributeName] = NSColor.disabledControlTextColor
		}

		let img = tintedImage(from: icon, tint: imageColor)
		if let t = title {

			labelRect = labelRect.offsetBy(dx: -3, dy: -3)

			let r = NSMakeRect(1, dirtyRect.height-7, dirtyRect.width-2, 7)
			let p = NSMutableParagraphStyle()
			p.alignment = .center
			p.lineBreakMode = .byTruncatingMiddle
			t.draw(in: r, withAttributes: [
				NSForegroundColorAttributeName: imageColor,
				NSFontAttributeName: NSFont.menuFont(ofSize: 6),
				NSParagraphStyleAttributeName: p
				])

			img.draw(in: CGRect(x: imagePoint.x+3, y: imagePoint.y, width: img.size.width-6, height: img.size.height-6))
		} else {
			img.draw(at: imagePoint, from: NSZeroRect, operation: .sourceOver, fraction: 1.0)
		}

		statusLabel.draw(in: labelRect, withAttributes: displayAttributes)
	}

	// With thanks to http://stackoverflow.com/questions/1413135/tinting-a-grayscale-nsimage-or-ciimage
	private func tintedImage(from image: NSImage, tint: NSColor) -> NSImage {

		let tinted = image.copy() as! NSImage
		tinted.lockFocus()
		tint.set()

		let imageRect = NSRect(origin: NSZeroPoint, size: image.size)
		NSRectFillUsingOperation(imageRect, .sourceAtop)

		tinted.unlockFocus()
		return tinted
	}
}

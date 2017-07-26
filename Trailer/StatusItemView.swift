
final class StatusItemView: NSView {

	private let tappedCallback: Completion

	var icon: NSImage!
	var textAttributes = [NSAttributedStringKey : Any]()
	var statusLabel = ""
	var labelOffset: CGFloat = 0
	var title: String?

	var grayOut = false {
		didSet {
			if grayOut != oldValue {
				needsDisplay = true
			}
		}
	}

	var highlighted = false {
		didSet {
			if highlighted != oldValue {
				needsDisplay = true
			}
		}
	}

	init(callback: @escaping Completion) {
		tappedCallback = callback
		super.init(frame: NSZeroRect)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func mouseDown(with theEvent: NSEvent) {
		tappedCallback()
	}

	static private let padding: CGFloat = 1.0

	func sizeToFit() {
		let width = Settings.hideMenubarCounts ? (title == nil ? 0 : 4) : statusLabel.size(withAttributes: textAttributes).width
		let H = NSStatusBar.system.thickness
		let itemWidth = (H + width + StatusItemView.padding*3) + labelOffset
		frame = CGRect(x: 0, y: 0, width: itemWidth, height: H)
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect) {

		app.statusItem(for: self)?.drawStatusBarBackground(in: dirtyRect, withHighlight: highlighted)

		var countAttributes = textAttributes
		var foreground: NSColor

		if highlighted {
			foreground = .selectedMenuItemTextColor
			countAttributes[NSAttributedStringKey.foregroundColor] = foreground
		} else if app.darkMode {
			foreground = .selectedMenuItemTextColor
			if countAttributes[NSAttributedStringKey.foregroundColor] as! NSColor == NSColor.controlTextColor {
				countAttributes[NSAttributedStringKey.foregroundColor] = foreground
			}
		} else {
			foreground = .controlTextColor
		}

		if grayOut {
			countAttributes[NSAttributedStringKey.foregroundColor] = NSColor.disabledControlTextColor
		}

		if(Settings.hideMenubarCounts) {
			drawIconOnly(titleColor: foreground, countAttributes: countAttributes, inRect: dirtyRect)
		} else {
			drawStandard(titleColor: foreground, countAttributes: countAttributes, inRect: dirtyRect)
		}
	}

	private func drawStandard(titleColor: NSColor, countAttributes: [NSAttributedStringKey : Any], inRect: NSRect) {

		let imagePoint = CGPoint(x: StatusItemView.padding, y: 0)
		var labelRect = CGRect(x: bounds.size.height + labelOffset, y: -5, width: bounds.size.width, height: bounds.size.height)
		let img = tintedImage(from: icon, tint: titleColor)

		if let t = title {

			labelRect = labelRect.offsetBy(dx: -3, dy: -3)

			let r = CGRect(x: 1, y: inRect.height-7, width: inRect.width-2, height: 7)
			let p = NSMutableParagraphStyle()
			p.alignment = .center
			p.lineBreakMode = .byTruncatingMiddle
			t.draw(in: r, withAttributes: [
				NSAttributedStringKey.foregroundColor: titleColor,
				NSAttributedStringKey.font: NSFont.menuFont(ofSize: 6),
				NSAttributedStringKey.paragraphStyle: p
				])

			img.draw(in: CGRect(x: imagePoint.x+3, y: imagePoint.y, width: img.size.width-6, height: img.size.height-6))
		} else {
			img.draw(at: imagePoint, from: NSZeroRect, operation: .sourceOver, fraction: 1.0)
		}

		statusLabel.draw(in: labelRect, withAttributes: countAttributes)
	}

	private func drawIconOnly(titleColor: NSColor, countAttributes: [NSAttributedStringKey : Any], inRect: NSRect) {

		let foreground = countAttributes[NSAttributedStringKey.foregroundColor] as! NSColor

		if let t = title {

			let r = CGRect(x: 1, y: inRect.height-7, width: inRect.width-2, height: 7)
			let p = NSMutableParagraphStyle()
			p.alignment = .center
			p.lineBreakMode = .byTruncatingMiddle
			t.draw(in: r, withAttributes: [
				NSAttributedStringKey.foregroundColor: titleColor,
				NSAttributedStringKey.font: NSFont.menuFont(ofSize: 6),
				NSAttributedStringKey.paragraphStyle: p
				])
			
			if statusLabel == "X" {
				let w = statusLabel.size(withAttributes: countAttributes).width
				let rect = CGRect(x: (inRect.width - w)*0.5, y: -4, width: w, height: inRect.size.height - 4)
				statusLabel.draw(in: rect, withAttributes: countAttributes)
			} else {
				let img = tintedImage(from: icon, tint: foreground)
				let w = img.size.width - 6
				let rect = CGRect(x: (inRect.width - w)*0.5, y: 0, width: w, height: img.size.height - 6)
				img.draw(in: rect)
			}
		} else {

			if statusLabel == "X" {
				let s = statusLabel.size(withAttributes: countAttributes)
				let rect = CGRect(x: (inRect.width - s.width)*0.5, y: (inRect.height - s.height)*0.5, width: s.width, height: s.height)
				statusLabel.draw(in: rect, withAttributes: countAttributes)
			} else {
				let img = tintedImage(from: icon, tint: foreground)
				img.draw(at: CGPoint(x: (inRect.width - img.size.width)*0.5, y: 0), from: NSZeroRect, operation: .sourceOver, fraction: 1.0)
			}
		}
	}

	// With thanks to http://stackoverflow.com/questions/1413135/tinting-a-grayscale-nsimage-or-ciimage
	private func tintedImage(from image: NSImage, tint: NSColor) -> NSImage {

		let tinted = image.copy() as! NSImage
		tinted.lockFocus()
		tint.set()

		let imageRect = NSRect(origin: NSZeroPoint, size: image.size)
		imageRect.fill(using: .sourceAtop)

		tinted.unlockFocus()
		return tinted
	}
}

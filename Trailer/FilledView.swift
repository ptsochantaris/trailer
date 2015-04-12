
final class FilledView: NSView {

	var backgroundColor: NSColor? {
		didSet {
			setNeedsDisplayInRect(bounds)
		}
	}

	var cornerRadius: CGFloat? {
		didSet {
			setNeedsDisplayInRect(bounds)
		}
	}

	var borderColor: NSColor? {
		didSet {
			setNeedsDisplayInRect(bounds)
		}
	}

    override func drawRect(dirtyRect: NSRect) {
        super.drawRect(dirtyRect)

		if let b = backgroundColor {
			b.set()
			if let c = cornerRadius {
				NSBezierPath(roundedRect: dirtyRect, xRadius: c, yRadius: c).addClip()
			}
			NSRectFill(dirtyRect)
		} else if let b = borderColor {
			b.set()
			let path = NSBezierPath(rect: dirtyRect)
			path.lineWidth = 0.5
			path.stroke()
		}
    }

    override var allowsVibrancy: Bool {
		return false
	}
}

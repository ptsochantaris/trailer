
final class FilledView: NSView {

	var backgroundColor: NSColor? {
		didSet {
			setNeedsDisplay(bounds)
		}
	}

	var cornerRadius: CGFloat? {
		didSet {
			setNeedsDisplay(bounds)
		}
	}

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

		if let b = backgroundColor {
			b.set()
			if let c = cornerRadius {
				NSBezierPath(roundedRect: dirtyRect, xRadius: c, yRadius: c).addClip()
			}
			NSRectFill(dirtyRect)
		}
    }

    override var allowsVibrancy: Bool {
		return false
	}
}

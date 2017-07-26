
final class FilledView: NSView {
	
	@objc var backgroundColor: NSColor? {
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
			dirtyRect.fill()
		}
	}
	
	override var allowsVibrancy: Bool {
		return false
	}
}

import Cocoa

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

        if let backgroundColor {
            backgroundColor.set()
            if let cornerRadius {
                NSBezierPath(roundedRect: dirtyRect, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
            }
            dirtyRect.fill()
        }
    }

    override var allowsVibrancy: Bool {
        false
    }
}

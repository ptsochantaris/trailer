
final class AvatarView: NSImageView {

	var spinner: NSProgressIndicator?

	init(frame frameRect: NSRect, url: String) {
		super.init(frame: frameRect)
		imageAlignment = .alignCenter
		if (!api.haveCachedAvatar(url) { [weak self] img, _ in
			if let weakSelf = self {
				weakSelf.image = img
				weakSelf.done()
			}
		}) {
			startSpinner()
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		let radius = floor(AVATAR_SIZE/2.0)
		let path = NSBezierPath(roundedRect: dirtyRect, xRadius: radius, yRadius: radius)
		path.addClip()
		super.draw(dirtyRect)
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

	func startSpinner() {
		let s = NSProgressIndicator(frame: bounds.insetBy(dx: 6.0, dy: 6.0))
		s.style = .spinningStyle
		addSubview(s)
		s.startAnimation(self)
		spinner = s
	}

	func done() {
		spinner?.stopAnimation(nil)
		spinner?.removeFromSuperview()
		spinner = nil
	}

    override var allowsVibrancy: Bool {
		return false
	}
}

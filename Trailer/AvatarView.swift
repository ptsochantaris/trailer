
final class AvatarView: NSImageView {
	
	init(frame frameRect: NSRect, url: String?) {
		super.init(frame: frameRect)
        
        guard let url = url else {
            let size = NSSize(width: AVATAR_SIZE, height: AVATAR_SIZE)
            let img = NSImage(size: size)
            img.lockFocus()
            NSColor.appTertiaryLabel.setFill()
            NSGraphicsContext.current?.cgContext.fill(NSRect(origin: .zero, size: size))
            img.unlockFocus()
            self.image = img
            return
        }
        
		imageAlignment = .alignCenter
		imageScaling = .scaleProportionallyUpOrDown
		
		var spinner: NSProgressIndicator?
		
		if (!API.haveCachedAvatar(from: url) { [weak self] img, _ in
			guard let s = self else { return }
			s.image = img
			spinner?.stopAnimation(nil)
			spinner?.removeFromSuperview()
			}) {
			let s = NSProgressIndicator(frame: bounds.insetBy(dx: 6, dy: 6))
			s.style = .spinning
			addSubview(s)
			s.startAnimation(self)
			spinner = s
		}
	}
	
	override func draw(_ dirtyRect: NSRect) {
		let radius = floor(AVATAR_SIZE/2.0)
		let path = NSBezierPath(roundedRect: dirtyRect, xRadius: radius, yRadius: radius)
		path.setClip()
		super.draw(dirtyRect)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	override var allowsVibrancy: Bool {
		return false
	}
}

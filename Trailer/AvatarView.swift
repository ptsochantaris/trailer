
class AvatarView: NSImageView {

	var spinner: NSProgressIndicator?

	init(frame frameRect:NSRect, url:NSString) {
		super.init(frame: frameRect)
		imageAlignment = NSImageAlignment.AlignCenter
		if !api.haveCachedAvatar(url, tryLoadAndCallback: { img in
			self.image = img
			self.done()
		}) {
			startSpinner()
		}
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

	func startSpinner() {
		var s = NSProgressIndicator(frame: CGRectInset(self.bounds, 6.0, 6.0));
		s.style = NSProgressIndicatorStyle.SpinningStyle
		self.addSubview(s)
		s.startAnimation(self)
		spinner = s;
	}

	func done() {
		spinner?.stopAnimation(self)
		spinner?.removeFromSuperview()
		spinner = nil
	}
}

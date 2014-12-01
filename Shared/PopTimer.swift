
class PopTimer : NSObject {

	var popTimer: NSTimer?
	let timeInterval: NSTimeInterval
	let callback: ()->()

	var isRunning: Bool {
		return popTimer != nil
	}

	func push() {
		popTimer?.invalidate()
		popTimer = NSTimer.scheduledTimerWithTimeInterval(timeInterval, target:self, selector:Selector("popped"), userInfo:nil, repeats:false)
	}

	func popped() {
		invalidate()
		callback()
	}

	func invalidate() {
		popTimer?.invalidate()
		popTimer = nil
	}

	init(timeInterval: NSTimeInterval, callback: ()->()) {
		self.timeInterval = timeInterval
		self.callback = callback
		super.init()
	}
}
